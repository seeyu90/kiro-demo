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
- **SheetsClient**：封裝 Google Sheets API 呼叫的內部物件（`SheetsApiClient` 或同等模組），負責初始化 `google-apis-sheets_v4` service 物件、對 5 個類型分頁分別執行 `spreadsheets.values.get` 呼叫、合併回傳單一原始列陣列。
- **類型分頁**：試算表中依任務類型各自獨立的分頁，本階段涵蓋 `功能`、`PR`、`調整`、`遺漏`、`臭蟲` 共 5 個，欄位結構完全相同。與 `warroom-data-api-prototype` requirements.md 排除的「306 臭蟲議題」是不同的資料來源，`臭蟲` 分頁本身是 305 進度表的一種任務類型，兩者無關。
- **Service_Account**：Google Cloud Service Account，用於以程式方式向 Google Sheets API 認證，不需人工登入。
- **Credentials_JSON**：Service Account 的 JSON 金鑰檔，存放於 Rails credentials 或環境變數，不寫在程式碼或版控中。
- **ISO 8601**：國際日期格式，本文件中指 `YYYY-MM-DD` 字串格式。
- **Turbo Frame**：Rails Turbo 提供的局部頁面更新機制，不觸發整頁重載。
- **Dashboard_Page**：呈現戰情室資料的前端 Rails 頁面；介面與雛型一致，不變動。
- **Blueprint**：遵循 Blueprinter gem 慣例的序列化物件；`ProjectTaskBlueprint` 定義任務輸出欄位，介面與雛型一致，不變動。
- **統一錯誤格式**：`{ "error": { "code": "<錯誤代碼>", "message": "<描述>" } }` 的 JSON 結構。
- **FORMATTED_VALUE**：Google Sheets API 的 `valueRenderOption` 參數值，指示 API 回傳儲存格的顯示字串（日期型別儲存格將回傳 `YYYY/MM/DD` 格式）。
- **模擬資料**：雛型階段使用的 `lib/mock_data/project_progress.rb` 記憶體常數，本階段由真實 Google Sheets API 取代，不再使用。

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

1. WHEN **ProjectProgress_Actor** 被呼叫，THE **SheetsClient** SHALL 對試算表 ID `11gwDnOqEiGqj_VF2XF7AzxiJTiOW_k2knF6-4yQCej8` 的 5 個類型分頁（`功能`、`PR`、`調整`、`遺漏`、`臭蟲`）各自以範圍 `A:G` 發起 `spreadsheets.values.get` 請求，並指定 `valueRenderOption: 'FORMATTED_VALUE'`。
2. WHEN **SheetsClient** 取得 5 個分頁的回應，THE **SheetsClient** SHALL 將其合併為單一列陣列：僅保留第一個分頁的標題列，其餘分頁只併入資料列（不重複的標題列）。
3. WHEN **ProjectProgress_Actor** 收到合併後的列陣列，THE **ProjectProgress_Actor** SHALL 跳過第 1 列（標題列），從第 2 列起逐列解析為任務紀錄。
4. WHEN 解析列資料時，THE **ProjectProgress_Actor** SHALL 依以下欄位對應產生任務 Hash（每個類型分頁欄位結構相同）：A 欄 → `project_name`、B 欄 → `task_name`、C 欄 → `status`、D 欄 → `owner`、E 欄 → `planned_completion_date`、F 欄 → `actual_completion_date`、G 欄 → `delay_days`（試算表既有公式算好的值，直接讀取）。
5. WHEN 列陣列長度不足 7 個元素，THE **ProjectProgress_Actor** SHALL 以 `nil` 填補不足的欄位，不拋出陣列索引例外。
6. WHEN **SheetsClient** 收到空列（列陣列為 `nil` 或所有元素皆為空字串），THE **ProjectProgress_Actor** SHALL 跳過該列，不將其納入解析結果。

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
3. IF 任意紀錄的 `project_name`、`task_name`、`status` 或 `owner` 為空白，THEN THE **ProjectProgress_Actor** SHALL 跳過該筆紀錄、不納入 `grouped_data`，其餘正常紀錄仍照常回傳成功結果；不因單筆紀錄不完整而讓整個 request 失敗（真實試算表資料難免有少量不完整列，需與其他正常列分開處理）。
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
4. THE **ProjectProgress_Endpoint** 及 **Dashboard_Page** SHALL 繼續透過 `ProjectTaskBlueprint` 序列化任務資料，Blueprint 定義不變動。

---

### 需求 7：對外介面與雛型一致

**使用者故事：** 身為前端開發者，我希望替換資料來源後，API Endpoint 與 Dashboard 頁面的 HTTP 介面及回應格式均與雛型相同，以便前端及測試腳本不需任何修改。

#### 驗收標準

1. THE **ProjectProgress_Endpoint** SHALL 繼續回應 `GET /api/project_progress`，回傳格式 `{ "<專案名稱>": [ <任務物件陣列> ] }` 不變。
2. THE **Dashboard_Page** SHALL 繼續回應 `GET /dashboard`，頁面結構與雛型一致，不變動。
3. WHEN **ProjectProgress_Endpoint** 回傳成功回應，每筆任務物件 SHALL 包含欄位：`project_name`、`task_name`、`status`、`owner`、`planned_completion_date`、`actual_completion_date`、`delay_days`，與雛型一致。

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
