# 需求文件

## 簡介

戰情室資料讀取 API 雛型（warroom-data-api-prototype）的目的是驗證資料讀取層的可行性。
本雛型以記憶體內模擬資料取代真實 Google Sheets 資料來源，提供一支結構化 JSON API，
並配合一個簡單的 Rails 前端頁面，依專案分組顯示專案進度（305）。

**不納入範圍**：真實 Google Sheets API 串接、OAuth / Service Account 認證、資料庫、排程同步、
即時更新、權限管理、搜尋排序等複雜互動、響應式設計及美化樣式。306 臭蟲議題資料原本規劃一併納入，
但為避免範圍過大導致無法完成，本階段先聚焦 305 專案進度，306 留待後續迭代再議。

**技術棧說明**：本雛型採 Ruby on Rails 獨立伺服器實作（含真實可運作的 API 與頁面互動），
不受 `.kiro/steering/project-standards.md` 中「純 HTML/CSS/JS、僅發布至 `docs/` 靜態站」限制
之限制；此為刻意的技術選型，目的是驗證一個可實際運作的資料讀取層，而非靜態展示頁面。

---

## 詞彙表

- **API**：Application Programming Interface，本文件中指 Rails JSON 端點。
- **Endpoint**：單一 HTTP 路由與其對應的處理邏輯，回傳 JSON 回應。
- **Actor**：遵循 service_actor 模式的服務物件，封裝單一商業邏輯。
- **ProjectProgress_Actor**：`Sheets::FetchProjectProgress` Actor，負責提供 305 專案進度資料。
- **ProjectProgress_Endpoint**：回傳 305 專案進度資料的 HTTP 端點（`GET /api/project_progress`）。
- **模擬資料**：記憶體內的 Hash / Array 或 fixture 檔案，用以替代真實 Google Sheets 資料。
- **ISO 8601**：國際日期格式，本文件中指 `YYYY-MM-DD` 字串格式。
- **Turbo Frame**：Rails Turbo 提供的局部頁面更新機制，不觸發整頁重載。
- **Dashboard_Page**：呈現戰情室資料的前端 Rails 頁面。
- **統一錯誤格式**：`{ "error": { "code": "<錯誤代碼>", "message": "<描述>" } }` 的 JSON 結構。
- **Blueprint**：遵循 Blueprinter gem 慣例的序列化物件，統一定義要輸出給 API／View 的欄位清單，避免欄位定義在多處重複。

---

## 需求

### 需求 1：305 專案進度 Endpoint

**使用者故事：** 身為開發者，我希望能呼叫 API 取得所有 305 專案進度資料，以便驗證資料讀取層是否正確讀取並結構化進度資料。

#### 驗收標準

1. THE **ProjectProgress_Endpoint** SHALL 回應 HTTP `GET /api/project_progress` 請求。
2. WHEN **ProjectProgress_Endpoint** 收到有效請求，THE **ProjectProgress_Actor** SHALL 從模擬資料讀取所有專案進度紀錄，並回傳 HTTP 200 及 JSON 回應。
3. THE **ProjectProgress_Endpoint** SHALL 回傳 JSON 格式為 `{ "<專案名稱>": [ <任務物件陣列> ] }`，以專案名稱為鍵值進行分組。
4. WHEN **ProjectProgress_Actor** 回傳任務資料，THE **ProjectProgress_Endpoint** SHALL 確保每筆任務物件包含以下欄位：`project_name`（專案名稱）、`task_name`（任務名稱）、`status`（狀態）、`owner`（負責人）、`planned_completion_date`（預計完成日期）、`actual_completion_date`（實際完成日期）、`delay_days`（延誤天數）。
5. WHEN 任務物件的 `planned_completion_date` 或 `actual_completion_date` 欄位值非空字串，THE **ProjectProgress_Actor** SHALL 將該日期值轉換為 ISO 8601（`YYYY-MM-DD`）格式後再回傳。
6. WHEN 任務物件的日期欄位值為空字串或 null，THE **ProjectProgress_Actor** SHALL 將該欄位以 `null` 回傳，不進行轉換。

---

### 需求 2：依專案名稱分組

**使用者故事：** 身為前端開發者，我希望 API 回傳的 JSON 以專案名稱為鍵值分組，以便前端能直接按專案渲染資料，不需額外處理。

#### 驗收標準

1. THE **ProjectProgress_Actor** SHALL 將所有任務紀錄依 `project_name` 欄位值分組，產生以專案名稱為鍵值的 Hash 結構。
2. WHEN 模擬資料中某個專案名稱出現於多筆紀錄，THE **ProjectProgress_Actor** SHALL 將這些紀錄合併至同一個鍵值下的陣列中。
3. WHEN 模擬資料中無任何紀錄，THE **ProjectProgress_Actor** SHALL 回傳空物件 `{}`。

---

### 需求 3：基本錯誤處理

**使用者故事：** 身為 API 使用者，我希望在資料讀取失敗時收到結構一致的錯誤訊息，以便快速識別問題原因。

#### 驗收標準

1. IF **ProjectProgress_Actor** 找不到指定的模擬資料分頁，THEN THE **API** SHALL 回傳 HTTP 404 及統一錯誤格式 JSON，其中 `code` 為 `"sheet_not_found"`。
2. IF **ProjectProgress_Actor** 讀取的資料缺少必要欄位或格式不符預期，THEN THE **API** SHALL 回傳 HTTP 422 及統一錯誤格式 JSON，其中 `code` 為 `"invalid_data_format"`。
3. IF **ProjectProgress_Actor** 發生資料來源存取權限不足的錯誤，THEN THE **API** SHALL 回傳 HTTP 403 及統一錯誤格式 JSON，其中 `code` 為 `"access_denied"`。
4. IF **ProjectProgress_Actor** 發生上述三種情況以外的未預期錯誤，THEN THE **API** SHALL 回傳 HTTP 500 及統一錯誤格式 JSON，其中 `code` 為 `"internal_error"`。
5. THE **API** SHALL 以統一錯誤格式 `{ "error": { "code": "<錯誤代碼>", "message": "<描述>" } }` 回傳所有錯誤回應。

---

### 需求 4：日期正規化

**使用者故事：** 身為前端開發者，我希望 API 回傳的日期欄位統一為 ISO 8601 格式，以便不需在前端處理多種日期格式。

#### 驗收標準

1. THE **ProjectProgress_Actor** SHALL 支援解析以下日期格式並轉換為 ISO 8601（`YYYY-MM-DD`）：`YYYY/M/D`、`YYYY/MM/DD`、`YYYY-M-D`、`YYYY-MM-DD`。
2. WHEN 日期字串符合上述任一格式，THE **ProjectProgress_Actor** SHALL 輸出格式為 `YYYY-MM-DD` 的字串（月與日補零至兩位數）。
3. IF 日期欄位值為空字串或 null，THEN THE **ProjectProgress_Actor** SHALL 保留該欄位值為 `null`，不嘗試解析。
4. IF 日期欄位值不符合任何支援格式，THEN THE **ProjectProgress_Actor** SHALL 保留原始字串值不變。

---

### 需求 5：前端頁面顯示

**使用者故事：** 身為開發者，我希望能透過簡單的前端頁面瀏覽 API 回傳的資料，以便目視驗證資料結構與內容是否正確。

#### 驗收標準

1. THE **Dashboard_Page** SHALL 以 `GET /dashboard` 路由提供 HTML 頁面。
2. WHEN **Dashboard_Page** 載入完成，THE **Dashboard_Page** SHALL 依專案名稱分區塊顯示資料，每個專案區塊包含一個 305 任務清單表格。
3. THE **Dashboard_Page** SHALL 使用 Rails Turbo Frame 進行局部更新，切換專案時不觸發整頁重載。
4. THE **Dashboard_Page** SHALL 顯示 305 任務表格欄位：任務名稱、狀態、負責人、預計完成日期、實際完成日期、延誤天數。

---

### 需求 6：依專案篩選

**使用者故事：** 身為戰情室使用者，我希望能透過下拉選單切換要檢視的專案，以便快速聚焦特定專案的狀態。

#### 驗收標準

1. THE **Dashboard_Page** SHALL 提供下拉選單，列出所有可用的專案名稱（來自 305 資料）。
2. WHEN 使用者從下拉選單選擇一個專案，THE **Dashboard_Page** SHALL 透過 Turbo Frame 局部更新頁面內容，僅顯示該專案的任務資料。
3. WHEN 使用者從下拉選單選擇「全部專案」，THE **Dashboard_Page** SHALL 透過 Turbo Frame 局部更新頁面內容，顯示所有專案的資料區塊。

---

### 需求 7：頁面錯誤顯示

**使用者故事：** 身為開發者，我希望頁面能顯示 API 回傳的錯誤訊息，且單一專案資料缺失不會影響其他專案的顯示，以便在雛型階段快速識別資料問題。

#### 驗收標準

1. WHEN **Dashboard_Page** 從 API 收到錯誤回應，THE **Dashboard_Page** SHALL 在頁面上顯示該錯誤的 `message` 欄位內容。
2. IF 某一個專案的 305 資料為空，THEN THE **Dashboard_Page** SHALL 在該專案的區塊顯示「目前無資料」，不影響其他專案區塊的顯示。單一專案層級的獨立錯誤不適用於本雛型架構（單一 Actor 呼叫為整體成功或整體失敗，個別錯誤情境由需求 7.1 的頁面層級錯誤顯示涵蓋）。

---

### 需求 8：商業邏輯封裝

**使用者故事：** 身為後端開發者，我希望資料讀取邏輯一律封裝在 service_actor 中，以便保持 Controller 精簡、邏輯可獨立測試。

#### 驗收標準

1. THE **ProjectProgress_Actor** SHALL 遵循 service_actor pattern，以 `call` 方法作為唯一執行入口。
2. THE **ProjectProgress_Endpoint** 的 Controller 動作 SHALL 僅負責呼叫對應 Actor 並將結果渲染為 JSON，不包含資料讀取或轉換邏輯。
3. THE **ProjectProgress_Actor** SHALL 從記憶體內模擬資料（Hash/Array 或 fixture 檔案）讀取資料，不使用資料庫查詢。
4. THE **ProjectProgress_Endpoint** 及 **Dashboard_Page** SHALL 透過共用的 Blueprint（例如 `ProjectTaskBlueprint`）序列化任務資料，任務欄位清單僅在 Blueprint 中定義一次，不得在 Controller 或 View 中重複列舉。
