# 需求文件

## 簡介

`warroom-issue-dashboard-static-prototype` 已完成 306 臭蟲議題資料的靜態展示畫面驗證（`docs/issues.html`，
模擬資料）。本 spec 是該 prototype 的延續：把真實 Google Sheets 306 試算表（`306_臭蟲議題紀錄`，
ID `1RdU2p9b7fwNgO5e59jN-00a5KLOQ91xrFhj2NenyKTc`）串接進 `warroom-data-api-prototype` Rails 專案，
沿用該專案既有的 Controller → Actor → Client → Blueprint 分層架構（見
[.kiro/steering/rails-standards.md](../../steering/rails-standards.md)），並將畫面呈現方式對齊
`docs/issues.html` 已驗證過的版面（KPI 摘要卡片、依專案分類統計、每日趨勢圖、議題明細清單）。

真實 306 試算表分頁結構（Task 1 已透過解析試算表原生 XLSX 匯出檔的 `xl/workbook.xml` 取得完整分頁
清單，**確認**狀態為最終結果，非推測）：

| 分頁 | 可見性 | 確認狀態 | 欄位 |
|---|---|---|---|
| `month_kpi` | 顯示 | 已確認 | `year_month, 客訴, 測試, 總Bug, 攔截率, 完成數, 未結案, 平均天數, SLA達標率, Top3` |
| `daily_kpi` | 顯示 | 已確認 | `日期, 客訴, 測試, 其他, 總計, 未結束數量, 未結束IDs, slack_message` |
| `raw_2023` | 隱藏 | 已確認（原推測正確） | `issue_id, subject, type, tracker, status, assigned_to, start_date, due_date, work_days, sheet_name, project` |
| `raw_2024` | 隱藏 | 已確認（原推測正確） | 同上 |
| `raw_2025` | 隱藏 | 已確認（原推測正確） | 同上 |
| `raw_2026` | 顯示 | 已確認（原推測正確） | 同上 |
| `raw_2027` | 隱藏 | 已確認（**Task 1 新發現**，原規劃未涵蓋） | 同上；目前僅有標題列，無資料列 |

分頁隱藏狀態（`state="hidden"`）僅影響 Google Sheets 使用者介面顯示，**不影響** Google Sheets API
`spreadsheets.values.get` 讀取，故 `IssueSheetsClient` 可正常讀取 `raw_2023`〜`raw_2025` 的隱藏分頁
資料，無需額外處理。

試算表中另外還有四個分頁，Task 1 已確認其真實名稱：`工程師比例表`（原文件推測名「工程師負載表」）、
`專案工程師對照表`（原文件推測名「專案清單表」）、`2026_測試臭蟲`（先前描述為「缺少 work_days／
sheet_name／project 欄位、日期格式為 YYYY/M/D 的類似議題列表」）、`2026_客訴問題`（先前描述為
「僅含 issue_id, project, subject, status, start_date, due_date 六欄的精簡摘要列表」）。**本階段皆
不納入範圍**：`工程師比例表`／`專案工程師對照表` 經評估後排除（見 static prototype 需求文件的決策
記錄）；`2026_測試臭蟲`／`2026_客訴問題` 從名稱推測可能是 `raw_2026` 依類型拆分的子集視圖，但用途
與是否與 `raw_2026` 資料重複仍待後續確認，暫不納入範圍。

**不納入範圍**：`工程師比例表`、`專案工程師對照表`、`2026_測試臭蟲`、`2026_客訴問題`、即時同步／
Webhook／排程更新、資料庫或本地快取層、OAuth 使用者登入、資料寫入（僅唯讀）。

**技術棧說明**：本 spec 延續 `warroom-data-api-prototype`／`warroom-data-api-real-source` 的技術選型，
採 Ruby on Rails 獨立伺服器實作，使用 `google-apis-sheets_v4` + `googleauth`，以 service_actor 封裝讀取
邏輯，blueprinter 負責序列化，遵循 [rails-standards.md](../../steering/rails-standards.md) 的分層與錯誤
格式慣例。不受 `project-standards.md` 中「純 HTML/CSS/JS、僅發布至 `docs/` 靜態站」限制之約束。

---

## 詞彙表

- **IssueSheetsClient**：封裝對 306 試算表（ID `1RdU2p9b7fwNgO5e59jN-00a5KLOQ91xrFhj2NenyKTc`）各分頁
  `spreadsheets.values.get` 呼叫的內部物件，與既有 `SheetsApiClient`（305 用）分屬不同 Client，各自對應
  不同試算表 ID，不共用同一個類別（避免耦合兩個資料來源的分頁結構）。
- **IssueDashboard_Actor**：`Sheets::FetchIssueDashboard` Actor，負責讀取並正規化 306 三類讀取資料
  （月度 KPI、每日趨勢、議題明細）與一類衍生資料（依專案分類統計），對齊 `docs/issues.html` prototype
  已驗證的資料形狀。
- **IssueDashboard_Endpoint**：回傳 306 全部資料的 HTTP JSON 端點（`GET /api/issue_dashboard`）。
- **IssueDashboard_Page**：呈現 306 資料的 Rails 前端頁面（`GET /issues`）。
- **月度 KPI**：對應 `month_kpi` 分頁的單月統計列。
- **每日趨勢**：對應 `daily_kpi` 分頁的逐日統計列。
- **議題明細**：對應 `raw_2023`〜`raw_2026` 分頁合併後的逐筆議題紀錄。
- **Redmine_Issue_URL**：議題編號對應的 Redmine 議題頁面連結，格式為
  `https://redmine.amastek.com.tw/issues/{issue_id}`。
- **統一錯誤格式**：`{ "error": { "code": "<錯誤代碼>", "message": "<描述>" } }`，定義見
  [rails-standards.md](../../steering/rails-standards.md)。

---

## 需求

### 需求 1：確認真實分頁名稱與範圍

**使用者故事：** 身為後端開發者，我希望在開始串接前先確認試算表實際分頁名稱，以便 Client 的分頁請求
不會因分頁名稱猜測錯誤而失敗。

**狀態：已完成。** 透過解析試算表原生 XLSX 匯出檔的 `xl/workbook.xml`（比 Google Sheets API 的
`spreadsheets.get` 更直接可靠，同樣取得官方分頁清單）取得完整分頁清單與可見性狀態，結果見「簡介」
段落的分頁結構表格：`raw_2023`〜`raw_2026` 原推測正確；新發現 `raw_2027`（隱藏，目前僅標題列）；
工程師負載表／專案清單表的真實名稱為 `工程師比例表`／`專案工程師對照表`。

#### 驗收標準

1. 實作開始前，THE 開發者 SHALL 透過 Google Sheets API（或人工開啟試算表）取得
   `1RdU2p9b7fwNgO5e59jN-00a5KLOQ91xrFhj2NenyKTc` 的完整分頁名稱清單，確認 `raw_2023`〜`raw_2026`
   的實際分頁名稱是否與本文件推測一致。✅ 已完成，見上方「狀態」。
2. IF 實際分頁名稱與推測不同，THEN THE 開發者 SHALL 以實際名稱更新本 spec 與後續 `IssueSheetsClient`
   常數定義，不得沿用錯誤名稱。✅ 已依 Task 1 發現更新（新增 `raw_2027`）。

---

### 需求 2：Google Sheets API 認證

**使用者故事：** 身為後端開發者，我希望 306 資料讀取沿用既有的 Service Account 認證機制，以便不需
重新設計憑證管理流程。

#### 驗收標準

1. THE **IssueSheetsClient** SHALL 沿用 [rails-standards.md](../../steering/rails-standards.md) 定義的
   憑證讀取策略（Rails credentials 優先，環境變數 fallback），可與 305 的 `SheetsApiClient` 共用同一組
   Service Account 憑證（同一 Google Cloud 專案），不需另外設定第二組憑證來源。
2. THE **IssueSheetsClient** SHALL 以唯讀 scope `https://www.googleapis.com/auth/spreadsheets.readonly`
   認證。

---

### 需求 3：讀取月度 KPI

**使用者故事：** 身為戰情室使用者，我希望看到與 prototype 相同的月度 KPI 卡片，但資料是真實試算表內容。

#### 驗收標準

1. WHEN **IssueDashboard_Actor** 被呼叫，THE **IssueSheetsClient** SHALL 對 `month_kpi` 分頁發起
   `spreadsheets.values.get` 請求，`valueRenderOption: 'FORMATTED_VALUE'`。
2. THE **IssueDashboard_Actor** SHALL 將每一列解析為 Hash，欄位對應：`year_month, complaint, testing,
   total_bug, block_rate, completed, unresolved, avg_days, sla_rate`，與 prototype 的 `MONTH_KPI`
   形狀一致。
3. THE **IssueDashboard_Actor** SHALL 不解析 `month_kpi` 分頁的 `Top3` 欄位，不納入輸出——負責人不作為
   本頁面的統計分類主軸（見需求 3a），該欄位維持存在於原始試算表但本階段刻意不使用。

---

### 需求 3a：依專案分類統計（取代 Top3 責任人排行）

**使用者故事：** 身為戰情室使用者，我希望看到依專案分類的客訴／測試／其他數量統計，而非依負責人排行，
以便正確反映客訴問題由全專案承擔、測試問題歸屬個別開發者的責任歸屬差異。

#### 驗收標準

1. THE **IssueDashboard_Actor** SHALL 提供 `project_breakdown` 輸出：依 `issues`（需求 5）的 `project`
   欄位分組，統計各專案的 `complaint`／`testing`／`other` 筆數與 `total`（三者加總），與 prototype 的
   `computeProjectBreakdown` 邏輯一致。
2. `project_breakdown` 的統計範圍 SHALL 為 **IssueDashboard_Actor** 讀取到的全部議題（`issues` 輸出的
   完整集合），不限定於當前所選月份——議題明細本身無可靠的月份篩選欄位（`start_date` 與
   `month_kpi.year_month` 語意不完全對應），本階段不強行套用月份篩選，避免統計失真。
3. THE **IssueDashboard_Actor** SHALL 不提供／不解析 `month_kpi` 分頁的 `Top3` 欄位（見需求 3.3）。

---

### 需求 4：讀取每日趨勢

**使用者故事：** 身為戰情室使用者，我希望看到與 prototype 相同的每日趨勢圖，但資料是真實試算表內容。

#### 驗收標準

1. WHEN **IssueDashboard_Actor** 被呼叫，THE **IssueSheetsClient** SHALL 對 `daily_kpi` 分頁發起請求。
2. THE **IssueDashboard_Actor** SHALL 將每一列解析為 Hash：`date, complaint, testing, other, total`，
   與 prototype 的 `DAILY_KPI` 形狀一致；`未結束數量`／`未結束IDs`／`slack_message` 欄位本階段不納入
   輸出（prototype 畫面未使用）。
3. WHEN `總計`（`total`）欄位為空字串，THE **IssueDashboard_Actor** SHALL 將其視為 `0`，不中斷解析。
4. THE **IssueDashboard_Actor** SHALL 依日期升冪排序輸出，確保趨勢圖 X 軸順序正確（試算表本身已按
   日期排序，但仍應由程式保證，不依賴來源順序）。

---

### 需求 5：讀取議題明細

**使用者故事：** 身為戰情室使用者，我希望看到與 prototype 相同的議題明細清單，但資料是真實試算表內容。

#### 驗收標準

1. WHEN **IssueDashboard_Actor** 被呼叫，THE **IssueSheetsClient** SHALL 對 `raw_2023`〜`raw_2027`
   （Task 1 確認後的完整清單，含新發現的 `raw_2027`）各分頁發起請求，合併為單一列陣列（僅保留第一個
   分頁的標題列）；分頁隱藏狀態不影響讀取（見「簡介」段落）。
2. THE **IssueDashboard_Actor** SHALL 將每一列解析為 Hash：`issue_id, subject, type, tracker, status,
   assigned_to, start_date, due_date, work_days, project`（試算表本身已含 `sheet_name`／`project` 欄位，
   不需如 305 的 Client 額外附加分頁標記）。
3. WHEN `start_date`／`due_date` 欄位為非空字串，THE **IssueDashboard_Actor** SHALL 沿用既有
   `normalize_date` 邏輯轉換為 ISO 8601 格式。
4. WHEN `work_days` 欄位為有效整數字串，THE **IssueDashboard_Actor** SHALL 轉換為 Integer；否則保留
   原始值，不拋出例外。
5. IF 任一列的 `issue_id`／`subject`／`status` 為空白，THEN THE **IssueDashboard_Actor** SHALL 跳過該筆
   紀錄，不納入輸出，其餘正常列不受影響。
6. THE **IssueDashboard_Endpoint** 及 **IssueDashboard_Page** SHALL 依 `type` 欄位標示每筆議題的
   「歸屬類型」：`Complaint`（客訴）標示為「專案共同責任」，`TestingBug`（測試）標示為「個人責任」，
   其餘標示為「其他」；此標示 SHALL 為顯示層依 `type` 動態計算，不作為 Actor 輸出的獨立資料欄位
   （與 prototype 的 `attributionLabel(type)` 邏輯一致）。
7. THE **IssueDashboard_Page** SHALL 將議題明細表格的欄位依序顯示為：議題編號、專案、主旨、歸屬類型、
   狀態、負責人、開始日期、到期日期、工作天數，不顯示 `type`／`tracker` 原始欄位（分類意義已由
   「歸屬類型」呈現，避免重複資訊），與 prototype 的 `ISSUE_COLUMNS` 順序一致。
8. THE **IssueDashboard_Page** SHALL 將「議題編號」欄位渲染為可點擊連結，導向對應的
   **Redmine_Issue_URL**（`https://redmine.amastek.com.tw/issues/{issue_id}`），並以新分頁開啟
   （`target="_blank"`，含 `rel="noopener noreferrer"`）。

---

### 需求 6：錯誤處理

**使用者故事：** 身為 API 使用者，我希望 306 資料來源的錯誤情境與既有 API 一致，以便共用同一套錯誤
處理邏輯。

#### 驗收標準

1. THE **IssueDashboard_Actor** SHALL 遵循 [rails-standards.md](../../steering/rails-standards.md) 的
   統一錯誤格式與 `failure_code` 對應表（`sheet_not_found` / `access_denied` / `internal_error`）。
2. IF 三個讀取資料類別（月度 KPI、每日趨勢、議題明細；`project_breakdown` 為衍生資料不另計）中任一
   類別讀取失敗，THEN THE **IssueDashboard_Actor** SHALL 讓整個請求失敗（回傳單一錯誤），不做部分
   成功回傳（與 305 prototype 的「單一 Actor 呼叫為整體成功或整體失敗」原則一致）。

---

### 需求 7：對外介面與 Prototype 一致

**使用者故事：** 身為前端開發者，我希望 Rails 頁面渲染出的畫面與已驗證過的 `docs/issues.html` prototype
在結構與呈現方式上一致，以便使用者體驗不因資料來源替換而改變。

#### 驗收標準

1. THE **IssueDashboard_Page** SHALL 以 `GET /issues` 路由提供 HTML 頁面。
2. THE **IssueDashboard_Page** SHALL 顯示與 prototype 相同的三個區塊：月度 KPI 摘要卡片（含月份選擇、
   依專案分類統計）、每日趨勢圖、議題明細清單（可依專案／狀態篩選，含歸屬類型標示與 Redmine 連結）。
3. THE **IssueDashboard_Endpoint** SHALL 以 `GET /api/issue_dashboard` 回傳 JSON，結構為
   `{ month_kpi: [...], daily_kpi: [...], issues: [...], project_breakdown: [...] }`。
4. THE **IssueDashboard_Endpoint** 及 **IssueDashboard_Page** SHALL 透過 Blueprint 序列化各資料類別
   （欄位定義單一來源），不在 Controller 或 View 中重複列舉欄位。

---

### 需求 8：議題明細篩選（延續 prototype UX）

**使用者故事：** 身為戰情室使用者，我希望能像 prototype 一樣依專案與狀態篩選議題明細，以便快速找到
特定範圍的議題。

#### 驗收標準

1. THE **IssueDashboard_Page** SHALL 提供依「專案」篩選（`project` query param），預設「全部專案」。
2. THE **IssueDashboard_Page** SHALL 提供依「狀態」篩選（`status` query param），未帶參數時預設選中
   「新建立」，聚焦最需要處理的新進議題，不預設顯示全部狀態，與 prototype 一致。
3. WHEN 使用者變更專案或狀態篩選，THE **IssueDashboard_Page** SHALL 以 Turbo Frame 局部更新議題明細
   清單，不觸發整頁重載，與既有 `warroom-data-api-prototype` Dashboard 頁面的互動模式一致。
4. WHEN 篩選後無符合條件的議題，THE **IssueDashboard_Page** SHALL 顯示「目前無符合條件的議題」。

---

### 需求 9：月度 KPI 月份切換（延續 prototype UX）

**使用者故事：** 身為戰情室使用者，我希望能像 prototype 一樣切換月份查看不同月度 KPI，以便回顧歷史
月份表現。

#### 驗收標準

1. THE **IssueDashboard_Page** SHALL 提供月份選擇（`month` query param），未帶參數時預設最新月份
   （`month_kpi` 資料中 `year_month` 最大值）。
2. WHEN 使用者切換月份，THE **IssueDashboard_Page** SHALL 以 Turbo Frame 局部更新 KPI 卡片，不觸發
   整頁重載；依專案分類統計（`project_breakdown`）不隨月份篩選（見需求 3a.2），月份切換不影響其內容。
