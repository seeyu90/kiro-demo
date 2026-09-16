# Requirements Document

## Introduction

warroom-data-api-real-source 是 warroom-data-api-prototype 的延續，目標是將資料來源從記憶體內模擬資料替換為真實的 Google Sheets 305 專案進度表，同時保持所有對外介面（API Endpoint、Dashboard 頁面、Blueprint、Controller、View）與雛型完全一致。

本階段的範圍：串接 Google Sheets API 以讀取試算表資料、將原有四種錯誤情境對應至真實 API 例外、確保 Service Account 憑證安全存放。

**不納入範圍**：306 臭蟲議題資料、即時同步／Webhook／排程更新、資料庫或本地快取層、OAuth 使用者登入、響應式設計及樣式調整。

**技術棧說明**：本 spec 採 Ruby on Rails 獨立伺服器實作，使用 `google-apis-sheets_v4` + `googleauth` 官方組合存取 Google Sheets API，並以 service_actor 封裝讀取邏輯，blueprinter 負責序列化。此為繼承自 warroom-data-api-prototype 的刻意技術選型，不受 `.kiro/steering/project-standards.md` 中「純 HTML/CSS/JS、僅發布至 `docs/` 靜態站」限制之約束。

---

## Glossary

- **API**：Application Programming Interface，本文件中指 Rails JSON 端點或 Google Sheets REST API。
- **Endpoint**：單一 HTTP 路由與其對應的處理邏輯，回傳 JSON 回應。
- **Actor**：遵循 service_actor 模式的服務物件，封裝單一商業邏輯。
- **ProjectProgress_Actor**：`Sheets::FetchProjectProgress` Actor，負責提供 305 專案進度資料；本階段替換其內部資料讀取邏輯，對外輸出介面維持不變。
- **ProjectProgress_Endpoint**：回傳 305 專案進度資料的 HTTP 端點（`GET /api/project_progress`）；介面與雛型一致，不變動。
- **SheetsClient**：封裝 Google Sheets API 呼叫的內部物件（`ProjectProgressSheetsClient`），負責初始化 `google-apis-sheets_v4` service 物件、對**年度分頁**執行 `spreadsheets.values.get` 呼叫、將來源欄位重新對應為對外的列格式後回傳。
- **年度分頁**：以年度命名的分頁（目前為 `2026`），由 n8n 從各專案 Slack 頻道同步，欄位 A~J 為 `sheetName`、`專案名稱`、`類型`、`任務名稱`、`狀態`、`負責人`、`預計完成日期`、`實際完成日期`、`最後更新`、`record_key`。**這是 305 的唯一資料來源。**
- **類型分頁**（已不再讀取）：`功能`、`PR`、`調整`、`遺漏`、`臭蟲` 五個依類型切出來的衍生視圖。改為讀年度分頁的理由見需求 2 的附註。
- **類型設定分頁**：`類型 → 寬限天數` 對照表（目前 功能 0、PR 2、臭蟲 0、調整 0、遺漏 0），供延誤天數計算扣除。
- **Service_Account**：Google Cloud Service Account，用於以程式方式向 Google Sheets API 認證，不需人工登入。
- **Credentials_JSON**：Service Account 的 JSON 金鑰檔，存放於 Rails credentials 或環境變數，不寫在程式碼或版控中。
- **ISO 8601**：國際日期格式，本文件中指 `YYYY-MM-DD` 字串格式。
- **Turbo Frame**：Rails Turbo 提供的局部頁面更新機制，不觸發整頁重載。
- **Dashboard_Page**：呈現戰情室資料的前端 Rails 頁面；介面與雛型一致，不變動。
- **Blueprint**：遵循 Blueprinter gem 慣例的序列化物件；`ProjectTaskBlueprint` 定義任務輸出欄位，介面與雛型一致，不變動。
- **統一錯誤格式**：`{ "error": { "code": "<錯誤代碼>", "message": "<描述>" } }` 的 JSON 結構。
- **FORMATTED_VALUE**：Google Sheets API 的 `valueRenderOption` 參數值，指示 API 回傳儲存格的顯示字串（日期型別儲存格將回傳 `YYYY/MM/DD` 格式）。
- **模擬資料**：雛型階段使用的 `lib/mock_data/project_progress.rb` 記憶體常數，本階段由真實 Google Sheets API 取代，不再使用。
- **task_type**：任務類型，直接讀取自年度分頁的「類型」欄。除了 `功能`、`PR`、`調整`、`遺漏`、`臭蟲` 之外，實際資料還存在 `未分類`（沒有對應的類型分頁，這正是不能用類型分頁當來源的原因之一）。

---

## Requirements

### 需求 1：Google Sheets API 認證

**使用者故事：** 身為後端開發者，我希望系統能以 Service Account 向 Google Sheets API 認證，以便在不需要人工登入的情況下讀取試算表資料。

#### 驗收標準

1. THE **SheetsClient** SHALL 使用從 Rails credentials 或環境變數讀取的 Service Account JSON 金鑰，向 Google Sheets API 進行 OAuth2 認證。
2. THE **Credentials_JSON** SHALL 僅從 Rails credentials（`Rails.application.credentials`）或環境變數讀取，不得硬寫在任何原始碼檔案或提交至版控。
3. WHEN **SheetsClient** 初始化時，THE **SheetsClient** SHALL 以 `https://www.googleapis.com/auth/spreadsheets.readonly` scope 請求認證，不請求寫入權限。
4. IF **SheetsClient** 初始化時 Credentials_JSON 不存在或格式不合法，THEN THE **ProjectProgress_Actor** SHALL 以 `failure_code: :internal_error` 回傳失敗結果。

---

### 需求 2：讀取 Google Sheets 305 專案進度資料

**使用者故事：** 身為後端開發者，我希望 Actor 能從指定的 Google Sheets 分頁讀取 305 專案進度資料，以便取代記憶體模擬資料，提供真實內容給 API 與 Dashboard。

#### 驗收標準

1. WHEN **ProjectProgress_Actor** 被呼叫，THE **SheetsClient** SHALL 對試算表（ID 由環境變數 `PROJECT_PROGRESS_SPREADSHEET_ID` 決定）的**年度分頁**（名稱由 `PROJECT_PROGRESS_SHEET_NAME` 決定，預設 `2026`）以範圍 `A:J` 發起單一次 `spreadsheets.values.get` 請求，並指定 `valueRenderOption: 'FORMATTED_VALUE'`。

   > **為什麼不讀類型分頁：** 原本讀 `功能`／`PR`／`調整`／`遺漏`／`臭蟲` 五個分頁。以真實資料比對後發現年度分頁 499 筆、五個類型分頁合計僅 483 筆，差異的 16 筆類型為 `未分類`（沒有對應分頁，永遠讀不到，其中含 4 筆未完成任務）；另有 18 筆兩邊內容不一致，且一律是年度分頁較新（例：RAG「平台 前端」年度分頁已是「完成／實際完成日 2026-09-16」，類型分頁仍是「未完成」；3 筆 HRM 任務年度分頁已填「未完成」，類型分頁仍是空白）。類型分頁是衍生視圖且會落後於來源，故一律以年度分頁為準。

2. WHEN **SheetsClient** 取得年度分頁的回應，THE **SheetsClient** SHALL 將來源欄位重新對應為既有的對外列格式 `[專案名稱, 任務名稱, 狀態, 負責人, 預計完成日期, 實際完成日期, 延誤天數, 類型]`，其中「延誤天數」一律為 `nil`（年度分頁無此欄，改由 Actor 計算，見需求 4.3b），並以固定標題列取代來源標題列。
3. WHEN **ProjectProgress_Actor** 收到列陣列，THE **ProjectProgress_Actor** SHALL 跳過第 1 列（標題列），從第 2 列起逐列解析為任務紀錄。
4. WHEN 解析列資料時，THE **ProjectProgress_Actor** SHALL 依以下欄位對應產生任務 Hash：第 1 欄 → `project_name`、2 → `task_name`、3 → `status`、4 → `owner`、5 → `planned_completion_date`、6 → `actual_completion_date`、7 → `delay_days`、8 → `task_type`。
5. WHEN 列陣列長度不足應有欄數，THE **SheetsClient** SHALL 於欄位對應前先以 `nil` 補滿（Google Sheets API 會省略列尾端的空白儲存格），確保欄位不會錯位。
6. WHEN **SheetsClient** 收到空列（列陣列為 `nil` 或所有元素皆為空字串），THE **ProjectProgress_Actor** SHALL 跳過該列，不將其納入解析結果。
7. WHEN 年度分頁本身沒有任何列，THE **SheetsClient** SHALL 回傳空陣列。
8. WHEN 任務的類型在「類型設定」分頁中沒有對應列，THE **ProjectProgress_Actor** SHALL 視為寬限天數 0。
9. WHEN 呼叫端未指定任務類型，THE **ProjectProgress_Actor** SHALL 預設選取 `功能`、`PR` 與 `未分類`。`未分類` 代表尚未被歸類、而非不重要，不納入預設會讓這些任務在預設檢視下等於不存在。

---

### 需求 3：欄位正規化

**使用者故事：** 身為前端開發者，我希望 API 回傳的欄位格式與雛型階段一致，以便前端不需因資料來源替換而修改任何程式碼。

#### 驗收標準

1. WHEN 日期欄位（`planned_completion_date`、`actual_completion_date`）的值為非空字串，THE **ProjectProgress_Actor** SHALL 呼叫現有 `normalize_date` 方法將其轉換為 ISO 8601（`YYYY-MM-DD`）格式。
2. WHEN 日期欄位的值為 `nil` 或空字串，THE **ProjectProgress_Actor** SHALL 將該欄位值設為 `nil`，不進行解析。
3. IF 日期欄位值不符合任何支援格式（`YYYY/M/D`、`YYYY/MM/DD`、`YYYY-M-D`、`YYYY-MM-DD`），THEN THE **ProjectProgress_Actor** SHALL 保留原始字串值不變，不觸發 `invalid_data_format` 錯誤。
4. WHEN `delay_days` 欄位的值為有效整數字串（包含負數），THE **ProjectProgress_Actor** SHALL 將其轉換為 Integer 型別。
5. IF `delay_days` 欄位的值為 `nil`、空字串或非數字字串，THEN THE **ProjectProgress_Actor** SHALL 保留原始值，不觸發 `invalid_data_format` 錯誤。
6. WHEN `owner` 欄位的值包含「姓名、姓名」（以頓號分隔的多人字串），THE **ProjectProgress_Actor** SHALL 將其視為普通字串保留原值，不拆分。

---

### 需求 4：錯誤對應至真實情境

**使用者故事：** 身為 API 使用者，我希望 Google Sheets API 的各類錯誤能對應至與雛型相同的統一錯誤格式，以便不需修改錯誤處理邏輯。

#### 驗收標準

1. IF Google Sheets API 回傳 HTTP 404，或任一類型分頁名稱在試算表中不存在（API 回傳訊息包含 `"Unable to parse range"`），THEN THE **ProjectProgress_Actor** SHALL 以 `failure_code: :sheet_not_found` 及 HTTP 404 回傳失敗結果。
2. IF Google Sheets API 回傳 HTTP 403，THEN THE **ProjectProgress_Actor** SHALL 以 `failure_code: :access_denied` 及 HTTP 403 回傳失敗結果。
3. IF 任意紀錄的 `project_name` 或 `task_name` 為空白，THEN THE **ProjectProgress_Actor** SHALL 跳過該筆紀錄、不納入 `grouped_data`，其餘正常紀錄仍照常回傳成功結果；不因單筆紀錄不完整而讓整個 request 失敗。少了這兩個欄位，該列無從辨識是什麼任務，是唯一真正「不完整」的情況。
3a. IF 任意紀錄的 `status` 或 `owner` 為空白，THEN THE **ProjectProgress_Actor** SHALL 保留該筆紀錄並分別正規化為 `"未完成"` 與 `"未指派"`，使其一併納入未完成／逾期統計與清單。

   > 原本 `status` 與 `owner` 都列在必要欄位、空白即整列跳過。以真實試算表驗算後發現：HRM 有
   > 5 筆狀態欄空白但其餘齊全的任務（2 筆已逾期），RAG 有 3 筆未完成但無人認領的任務，全部
   > 都不會出現在畫面上。這兩種空白都不代表資料不完整——狀態空白是填表的人還沒更新，負責人
   > 空白代表這件事還沒有人認領，而未完成又無人認領的工作，對戰情室來說比已指派的更需要被
   > 看見。把它們藏起來與這個頁面存在的目的正好相反。
3b. THE **ProjectProgress_Actor** SHALL 以 `max(工作日數 − 該類型寬限天數, 0)` 計算 `delay_days`，不採用試算表上任何既有的延誤欄位值。工作日數排除週六日（無國定假日表，故不扣國定假日），基準日為：已完成任務取「實際完成日期」、未完成且已逾期的任務取「今天」；未到期、無預計完成日期、或已完成卻無實際完成日期者一律回傳 `nil`（畫面顯示「—」，不判定準時）。寬限天數即時讀自「類型設定」分頁，讀取失敗時全部視為 0，不使整個 request 失敗。

   > 原本直接讀取試算表的「延誤天數」欄。以真實資料驗算後發現該欄與畫面上的「逾期」判斷基準不同（會出現「顯示 +7 天、實際已過 13 個日曆日」），且該欄混用公式與手填，456 筆已完成任務中只有 84.4% 對得上單純的工作日差；改用 `max(工作日 − 寬限天數, 0)` 後命中率 98.9%，可確認這就是業務認定的算法。

4. IF Google Sheets API 請求逾時、配額超過，或發生上述情況以外的未預期例外（含憑證載入失敗），THEN THE **ProjectProgress_Actor** SHALL 以 `failure_code: :internal_error` 及 HTTP 500 回傳失敗結果。
5. THE **API** SHALL 以統一錯誤格式 `{ "error": { "code": "<錯誤代碼>", "message": "<描述>" } }` 回傳所有錯誤回應；此格式與雛型一致，不變動。

---

### 需求 5：移除 simulate_error 機制

**使用者故事：** 身為後端開發者，我希望移除雛型階段的模擬錯誤參數，以便 Actor 介面更簡潔，且所有錯誤均由真實情境自然觸發。

#### 驗收標準

1. THE **ProjectProgress_Actor** SHALL 移除 `simulate_error` 輸入參數及其對應的條件分支邏輯。
2. THE **ProjectProgress_Endpoint** 的 Controller SHALL 不再讀取或傳遞 `simulate_error` query parameter。
3. WHEN **ProjectProgress_Actor** 被呼叫時收到 `simulate_error` query parameter，THE **ProjectProgress_Endpoint** SHALL 忽略該參數，不產生任何效果。

---

### 需求 6：Actor 輸出介面維持不變

**使用者故事：** 身為後端開發者，我希望替換資料來源後，Actor 的輸出介面與雛型完全相同，以便 Controller、View 及 Blueprint 均無需修改。

#### 驗收標準

1. WHEN **ProjectProgress_Actor** 成功讀取並解析資料，THE **ProjectProgress_Actor** SHALL 輸出 `grouped_data`：以專案名稱為鍵值、任務 Hash 陣列為值的 Hash，結構與雛型一致。
2. WHEN **ProjectProgress_Actor** 失敗，THE **ProjectProgress_Actor** SHALL 輸出 `failure_code`（Symbol）與 `message`（String），與雛型一致。
3. THE **ProjectProgress_Endpoint** 的 Controller SHALL 不包含任何 Google Sheets API 呼叫或資料解析邏輯，所有讀取與轉換邏輯均委派給 **ProjectProgress_Actor**。
4. THE **ProjectProgress_Endpoint** 及 **Dashboard_Page** SHALL 繼續透過 `ProjectTaskBlueprint` 序列化任務資料；Blueprint 新增 `task_type` 欄位（見需求 10），其餘既有欄位定義不變動。

---

### 需求 7：對外介面與雛型一致

**使用者故事：** 身為前端開發者，我希望替換資料來源後，API Endpoint 與 Dashboard 頁面的 HTTP 介面及回應格式均與雛型相同，以便前端及測試腳本不需任何修改。

#### 驗收標準

1. THE **ProjectProgress_Endpoint** SHALL 繼續回應 `GET /api/project_progress`，回傳格式 `{ "<專案名稱>": [ <任務物件陣列> ] }` 不變。
2. THE **Dashboard_Page** SHALL 繼續回應 `GET /dashboard`，頁面結構與雛型一致，不變動。
3. WHEN **ProjectProgress_Endpoint** 回傳成功回應，每筆任務物件 SHALL 包含欄位：`project_name`、`task_name`、`status`、`owner`、`planned_completion_date`、`actual_completion_date`、`delay_days`、`task_type`（新增，見需求 10）。

---

### 需求 8：依專案名稱分組

**使用者故事：** 身為前端開發者，我希望從真實 Google Sheets 讀取的資料仍以專案名稱為鍵值分組，以便前端不需修改任何渲染邏輯。

#### 驗收標準

1. THE **ProjectProgress_Actor** SHALL 將所有解析後的任務紀錄依 `project_name` 欄位值分組，產生以專案名稱為鍵值的 Hash 結構。
2. WHEN 試算表中某個專案名稱出現於多列，THE **ProjectProgress_Actor** SHALL 將這些紀錄合併至同一個鍵值下的陣列中。
3. WHEN 試算表中無任何有效資料列（跳過標題與空列後），THE **ProjectProgress_Actor** SHALL 回傳空物件 `{}`。

---

### 需求 9：Service Account 憑證安全存放

**使用者故事：** 身為後端開發者，我希望 Service Account 憑證以安全方式存放，以便金鑰不進入版控，且部署時可透過環境設定注入。

#### 驗收標準

1. THE **Credentials_JSON** 的存放路徑 SHALL 為下列之一：Rails encrypted credentials（`config/credentials.yml.enc`）或環境變數（如 `GOOGLE_SHEETS_CREDENTIALS_JSON`），兩種方式均須在 README 或部署說明中記載。
2. THE **SheetsClient** SHALL 在初始化時依序嘗試從 Rails credentials 讀取，若不存在則回退至環境變數讀取，以支援本機開發與正式部署兩種情境。
3. IF 任一存放方式均無法取得有效 Credentials_JSON，THEN THE **ProjectProgress_Actor** SHALL 以 `failure_code: :internal_error` 及明確的中文錯誤訊息回傳失敗結果。
4. THE **Credentials_JSON** 檔案路徑（若以檔案形式存放）或任何含金鑰內容的設定檔 SHALL 列入 `.gitignore`，不得提交至版控。

---

### 需求 10：Dashboard 任務類型與未完成／逾期篩選（戰情室 UX 強化延伸）

**使用者故事：** 身為戰情室使用者，我希望 Dashboard 預設顯示全部專案，任務類型可多選並預設聚焦「功能」＋「PR」＋「未分類」，範圍預設為「本週到期」（含所有已逾期任務，不限本週內），以便直接看到真實 Google Sheets 資料中最需要處理的工作，不需自己再篩選。

本需求延續 [warroom-dashboard-ux-enhancements](../warroom-dashboard-ux-enhancements/requirements.md) spec 於靜態展示頁（`docs/`）已定義的 UX 邏輯，套用至本 spec 的真實 Rails Dashboard（`app/views/dashboard/`），資料來源改為 `grouped_data`（來自真實 Google Sheets，經 `task_type` 標記）。

#### 驗收標準

1. THE **Dashboard_Page** SHALL 在未帶 `project` 參數（首次載入）時，預設顯示全部專案，不預先收斂至單一專案。
2. THE **Dashboard_Page** SHALL 提供任務類型**多選**篩選（`task_type[]` query param），選項為試算表中實際出現的類型；「功能」與「PR」排列於其他類型之前。
3. THE **Dashboard_Page** SHALL 在未帶 `task_type[]` 參數（首次載入）時，預設勾選「功能」與「PR」兩者；若使用者將全部勾選取消（`task_type[]` 帶空值），視為不套用類型篩選，顯示所有類型。
4. THE **Dashboard_Page** SHALL NOT 提供任務狀態（已完成／未完成）的**獨立**篩選控制項；「只看未完成」改由「範圍」的 `incomplete` 檢視提供（見需求 5）。

   > 這一項調整過三次：原本是「只顯示未完成」的勾選框，但 `due_this_week`／`overdue` 兩個範圍在程式中一併排除了已完成任務，導致取消勾選時畫面毫無變化（控制項等同故障）。修正範圍語意後一度改為三選一的狀態篩選，再評估認為多一軸篩選增加操作負擔而移除；但移除後「看所有未完成任務」就沒有任何入口了（`due_this_week` 只涵蓋本週，16 筆未完成中有 5 筆看不到），故改為在「範圍」這一組具名檢視中加入 `incomplete`——維持單一控制項，同時保留這個最常見的意圖。

5. THE **Dashboard_Page** SHALL 提供「範圍」篩選（`scope` query param：`all`／`incomplete`／`due_this_week`／`overdue`，單選），未帶參數時預設為 `due_this_week`。範圍是一組**具名檢視**，各自回答一個常見問題。除 `incomplete` 之外都是**日期條件**，不得因任務已完成或未完成而排除；各檢視對未完成／已完成任務的條件如下（一律以 `Date.current` 伺服器當地時間為基準）：

   | 範圍 | 未完成任務 | 已完成任務 |
   |---|---|---|
   | `all` | 無日期條件 | 無日期條件 |
   | `incomplete` | 無日期條件（全部列出） | 一律排除 |
   | `due_this_week` | `planned_completion_date` 不晚於本週週日，不限下界（涵蓋所有逾期未完成，不論逾期發生於本週內或更早） | `planned_completion_date` 或 `actual_completion_date` 落在本週 |
   | `overdue` | `planned_completion_date` 早於今天 | `delay_days` 大於 0（當初逾期完成的） |

   > 已完成任務不能沿用未完成那條日期條件：`due_this_week` 對未完成不限下界是對的（一月就該交、現在還沒交，今天依然欠著），但同一條件套在已完成任務上，等於把歷來每一筆完成的任務都算進「本週」。以實際資料驗證：一筆預計 2026-09-03、實際 2026-09-16 完成的 RAG 任務（delay 到本週才完成）原本在任何篩選組合下都看不到，這正是使用者回報的缺口。
6. WHEN 任一專案區塊經篩選後仍有逾期任務，THE **Dashboard_Page** SHALL 將逾期任務排列於該區塊清單最前面。
7. THE **Dashboard_Page** SHALL 在任務列表上方顯示摘要列（任務總數、已完成、未完成、逾期），統計範圍套用「專案」「任務類型」「範圍」「預計完成日期」**全部**篩選條件，與下方任務列表統計同一批任務；摘要列上方 SHALL 顯示文字說明統計依據。摘要列與任務列表中「逾期」標籤 SHALL 採用同一個定義：`planned_completion_date` 早於今天且未完成，或已完成但 `delay_days` 大於 0（與需求 5 表格中 `overdue` 範圍的定義一致）。

   > 原本摘要列只套用「專案」與「任務類型」，刻意不受「範圍」與日期區間影響，用意是當一個
   > 不受篩選影響的「整體健康度」錨點（沿用自靜態原型 spec
   > `warroom-dashboard-ux-enhancements/requirements.md` 需求 4.4）。實際使用時發現這個假設
   > 不成立：「範圍」是本頁最主要的時間切面篩選，使用者選「範圍＝本週到期」自然預期看到
   > 「這週的統計」，卻仍是全部任務的總數，被回報不合理——需要额外一段說明文字去解釋
   > 「其實不會跟著變」，正是行為本身該改而非該多加說明的訊號。改為摘要列跟著全部篩選走，
   > 與任務列表呈現一致的統計範圍。此為 Rails 版本對原靜態原型行為的刻意偏離，`docs/` 靜態
   > 展示頁不受影響。
   >
   > 另外，原本摘要列與任務列表的「逾期」標籤只認「未完成且已過期」，不含「完成但當初
   > 遲交」；而「範圍＝已逾期」的篩選（需求 5）從一開始就兩者都算，三處對「逾期」用了兩種
   > 定義卻沒有區分，導致同一頁面上「範圍＝已逾期」列出 70 筆、摘要卡「逾期」卻寫 6，且
   > 完成但遲交的任務（例如延誤 +7 天）沒有逾期標籤，容易被誤讀成資料錯誤。改為三處統一用
   > 較寬的定義後不再兜不起來。**刻意不擴及** `executive_summary`（專案健康度分級）與
   > `pm_weekly_report`（任務狀態分類）：那兩頁沿用原本「未完成且已過期」的窄定義
   > （`Sheets::FetchProjectProgress.overdue?`），這次調整只影響本頁專用的
   > `overdue_or_completed_late?`。
8. THE **Dashboard_Page** SHALL 確保切換專案下拉選單時，保留使用者當下的任務類型／範圍／日期區間篩選。
9. THE **Dashboard_Page** SHALL NOT 提供「年度」篩選；時間維度一律由日期區間（`from`／`to`）表達。

   > 曾短暫加過年度下拉。但 305 的資料源鎖在單一年度分頁（`PROJECT_PROGRESS_SHEET_NAME`），實測 476 筆全部屬於同一年，下拉永遠只有「全部年度」與當年兩個選項，等於沒有作用；而日期區間表達力涵蓋年度（整年＝1/1～12/31），反之不然。日後若真要跨年度瀏覽，需要的是「讀哪幾個年度分頁」的資料源機制，不是在已載入資料上再篩一次年份——留著那個下拉只會讓人誤以為可以跨年查詢。
10. THE **Dashboard_Page** SHALL NOT 提供頁面層級的「重新整理資料」按鈕；全站唯一的快取重新整理入口位於入口頁（`POST /refresh`，一次清除所有 Sheets 快取）。頁面亦不再顯示「資料更新於 X 分鐘前」時效標籤。
