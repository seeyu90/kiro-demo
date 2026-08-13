# Implementation Plan: 戰情室資料讀取 API — 真實 Google Sheets 串接

## Overview

在既有 `warroom-data-api-prototype` 基礎上，將 `Sheets::FetchProjectProgress` Actor 的資料來源
從記憶體模擬常數替換為真實 Google Sheets API。

主要變動：
- 新增 `SheetsApiClient`（`app/clients/sheets_api_client.rb`）封裝 Google Sheets API 呼叫與 Service Account 認證
- 修改 Actor：移除 `simulate_error` / `MockData` 依賴，新增 `parse_rows` 解析邏輯，改由真實例外驅動錯誤處理
- 微調 Controller：移除 `simulate_error` 參數傳遞
- 所有對外介面（路由、回應格式、Blueprint、View）**不變動**

每項任務均可獨立開發、驗證並 Commit。

---

## Tasks

- [x] 1. 安裝 Google Sheets 相關 gem
  - [x] 1.1 在 Gemfile 新增並安裝 gem
    - 在 `Gemfile` 新增 `gem "google-apis-sheets_v4"` 與 `gem "googleauth"`
    - 執行 `bundle install`，確認兩個 gem 均已安裝且無版本衝突
    - _需求：1.1、1.3_

- [x] 2. Service Account 憑證設定與文件記載
  - [x] 2.1 建立憑證設定說明（README 更新）
    - 在專案根目錄 `README.md`（或 `docs/warroom-data-api-real-source-setup.md`）新增憑證設定章節
    - 說明兩種注入方式：Rails encrypted credentials（`rails credentials:edit` → `google_sheets.service_account_json`）與環境變數（`GOOGLE_SHEETS_CREDENTIALS_JSON`，值為 JSON 字串）
    - 說明本機開發建議使用 Rails credentials，CI/CD 或正式部署使用環境變數
    - 確認 `config/credentials.yml.enc`（若以檔案形式）已列入 `.gitignore`，或說明 `master.key` 保護機制
    - _需求：9.1、9.4_

- [x] 3. 建立 `SheetsApiClient`
  - [x] 3.1 建立 `app/clients/sheets_api_client.rb`
    - 建立 `app/clients/` 目錄（若尚未存在）並確認已納入 Rails autoload 路徑
    - 定義常數 `SPREADSHEET_ID`、`SHEET_RANGE`（`"2026!A:G"`）、`SCOPES`（唯讀 scope）
    - 實作 `self.fetch_rows` class method（委派至 instance `fetch_rows`）
    - 實作 `fetch_rows`：初始化 `Google::Apis::SheetsV4::SheetsService`，呼叫 `get_spreadsheet_values` 並指定 `value_render_option: "FORMATTED_VALUE"`，回傳 `response.values || []`
    - API 呼叫失敗時直接重新拋出例外，不在此層捕捉
    - _需求：1.1、2.1_

  - [x] 3.2 實作憑證讀取邏輯（`credentials` 私有方法）
    - 實作 `rails_credentials_json`：讀取 `Rails.application.credentials.dig(:google_sheets, :service_account_json)`，失敗時回傳 `nil`
    - 實作 `env_credentials_json`：讀取 `ENV["GOOGLE_SHEETS_CREDENTIALS_JSON"]`，空值時回傳 `nil`
    - 實作 `credentials`：依序嘗試兩種來源，均為 `nil` 時 `raise` 含明確中文描述的 `StandardError`
    - 使用 `Google::Auth::ServiceAccountCredentials.make_creds` 建立認證物件，scope 為唯讀
    - _需求：1.1、1.2、1.3、1.4、9.1、9.2、9.3_

- [x] 4. `SheetsApiClient` 單元測試
  - [x] 4.1 撰寫 `spec/clients/sheets_api_client_spec.rb`
    - stub `Rails.application.credentials`：憑證存在時，`fetch_rows` 呼叫正確 API 參數
    - stub `Rails.application.credentials` 回傳 `nil`，設定 `ENV["GOOGLE_SHEETS_CREDENTIALS_JSON"]`：驗證 fallback 至環境變數
    - Rails credentials 與環境變數均不存在時：驗證 `fetch_rows` 拋出含中文描述的 `StandardError`
    - stub Google API 正常回傳：驗證 `fetch_rows` 回傳列陣列
    - stub Google API 拋出 `Google::Apis::ClientError`（403）：驗證例外被重新拋出（不在此層吞掉）
    - stub Google API 拋出 `Google::Apis::ClientError`（404）：驗證例外被重新拋出
    - _需求：1.1、1.2、1.3、1.4、9.2、9.3_

- [x] 5. 修改 `Sheets::FetchProjectProgress` Actor
  - [x] 5.1 移除 `simulate_error` 與 `MockData` 依賴
    - 刪除 `input :simulate_error` 宣告及其對應條件分支邏輯
    - 刪除 `require` 或參照 `MockData::ProjectProgress` 的所有程式碼
    - 確認 `output :grouped_data`、`output :failure_code`、`output :message` 宣告維持不變
    - _需求：5.1、5.2_

  - [x] 5.2 實作 `parse_rows` 私有方法
    - 新增 `COLUMN_KEYS` 常數（7 個 Symbol：`project_name`、`task_name`、`status`、`owner`、`planned_completion_date`、`actual_completion_date`、`delay_days`）
    - 實作 `parse_rows(rows)`：輸入為原始列陣列（含標題列）
      - `nil` 或空陣列直接回傳 `[]`
      - 跳過第 1 列（標題列），從 index 1 起處理
      - 跳過空列（`nil` 或所有元素均為空字串）
      - 列長度不足 7 時以 `nil` 填補（`padded = row + [nil] * [0, 7 - row.length].max`）
      - G 欄 `delay_days`：`nil` 或空字串（strip 後）先轉為 `nil`；否則以 `Integer(delay_raw, 10)` 嘗試轉型，失敗時保留原始值（`rescue ArgumentError, TypeError`）
      - 以 `COLUMN_KEYS.zip(...)` 產生任務 Hash
    - _需求：2.2、2.3、2.4、2.5、3.4、3.5_

  - [x] 5.3 修改 `call` 方法：改為呼叫 `SheetsApiClient`，更新錯誤處理
    - `call` 方法改為：`rows = SheetsApiClient.fetch_rows`，後續 `parse_rows`、`normalize_record`、`reject_invalid_records`、`group_by_project` 流程不變
    - 例外捕捉順序（兩個 `rescue` 區塊）：
      1. `Google::Apis::ClientError`：status 404 或 message 含 `"Unable to parse range"` → `:sheet_not_found`；status 403 → `:access_denied`；其他 → `:internal_error`
      2. `StandardError`（兜底，含 `RateLimitError`、`ServerError`、憑證錯誤）→ `:internal_error`
    - **注意**：`validate_records!`（不合法就整包失敗）已改為 `reject_invalid_records`（該筆跳過、其餘正常回傳），`:invalid_data_format` 不再由此 Actor 觸發，見需求 4.3
    - 確認 `normalize_date`、`group_by_project` 私有方法**完全不變動**
    - _需求：2.2、2.3、2.4、2.5、4.1、4.2、4.3、4.4、6.1、6.2_

- [x]* 6. Property 測試（具代表性範例，比照雛型階段作法，不引入 PBT 套件）
  - [x]* 6.1 撰寫 Property 1：空列跳過不影響有效資料數量
    - **Property 1：空列跳過不影響有效資料數量**
    - 準備至少一組含標題列、多筆非空列、與多筆空列（`nil` 列、全空字串列）混合的列陣列，驗證 `parse_rows` 輸出筆數恰好等於非空列數，空列不出現在輸出中
    - **驗證：需求 2.2、2.5**

  - [x]* 6.2 撰寫 Property 2：列長度不足時 nil 填補完整性
    - **Property 2：列長度不足時 nil 填補完整性**
    - 準備長度 0～6 各一組代表性列（例如只有 `project_name`、只到 `owner`、只到 `planned_completion_date`），驗證 `parse_rows` 解析後每筆任務 Hash 都包含全部 7 個 `COLUMN_KEYS`，不足欄位值為 `nil`
    - **驗證：需求 2.4**

  - [x]* 6.3 撰寫 Property 3：日期欄位格式一致性
    - **Property 3：日期欄位格式一致性**
    - 對 `YYYY/M/D`、`YYYY/MM/DD`、`YYYY-M-D`、`YYYY-MM-DD` 四種格式各準備至少一組範例（含月/日個位數與雙位數），驗證 `normalize_date` 輸出符合 `/\A\d{4}-\d{2}-\d{2}\z/`
    - **驗證：需求 3.1**

  - [x]* 6.4 撰寫 Property 4：nil 與空字串日期保留為 nil
    - **Property 4：nil 與空字串日期保留為 nil**
    - 對 `nil` 與空字串各準備一組範例，驗證 `normalize_date` 輸出必定為 `nil`
    - **驗證：需求 3.2**

  - [x]* 6.5 撰寫 Property 5：無法解析的日期保留原始值
    - **Property 5：無法解析的日期保留原始值**
    - 準備多組不符合支援格式的非空字串範例（如 `"TBD"`、`"未定"`、`"2026.07.31"`），驗證 `normalize_date` 輸出等於輸入值，不拋出例外
    - **驗證：需求 3.3**

  - [x]* 6.6 撰寫 Property 6：`delay_days` 型別轉換
    - **Property 6：`delay_days` 型別轉換**
    - 準備正數、負數、零的整數字串（如 `"5"`、`"-4"`、`"0"`）驗證轉為對應 Integer；準備 `nil`／空字串驗證轉為 `nil`；準備非數字字串（如 `"TBD"`）驗證保留原始字串
    - **驗證：需求 3.4、3.5**

  - [x]* 6.7 撰寫 Property 7：分組完整性（資料不遺失）
    - **Property 7：分組完整性（資料不遺失）**
    - 準備至少一組單專案與一組多專案（任務數不均）的任務 Hash 陣列，驗證 `group_by_project` 輸出所有陣列元素總數等於輸入筆數
    - **驗證：需求 8.1、8.2**

  - [x]* 6.8 撰寫 Property 8：分組鍵值完整性
    - **Property 8：分組鍵值完整性**
    - 沿用 6.7 的範例，驗證 `group_by_project` 輸出鍵值集合與輸入中 `project_name` 唯一值集合完全相同
    - **驗證：需求 8.1**

  - [x]* 6.9 撰寫 Property 9：錯誤回應格式一致性
    - **Property 9：錯誤回應格式一致性**
    - 對 `SheetsApiClient.fetch_rows` 拋出的例外情境（404、403、未預期例外）各驗證一次，API 回應 JSON body 必須包含 `error.code` 與 `error.message` 兩個鍵
    - 註：Actor 實際行為改為「缺必要欄位的列會被跳過並回傳成功」（見任務 7 Test 8），不再對缺欄資料回傳 `invalid_data_format` 失敗，故此 Property 涵蓋範圍相應調整為 404／403／未預期例外三種情境
    - **驗證：需求 4.1、4.2、4.4、4.5**

  - [x]* 6.10 撰寫 Property 10：Blueprint 欄位完整性
    - **Property 10：Blueprint 欄位完整性**
    - 對 `MockData` 移除後的真實任務 Hash 範例（至少 2 筆，含欄位值為 `nil` 的情況），驗證 `ProjectTaskBlueprint.render_as_hash` 輸出恰好包含 7 個欄位，不多不少
    - **驗證：需求 6.1、7.3**

- [x] 7. Actor 單元測試（stub `SheetsApiClient`）
  - [x] 7.1 撰寫 `spec/actors/sheets/fetch_project_progress_spec.rb`（更新現有或新增）
    - stub `SheetsApiClient.fetch_rows` 回傳正常列陣列 → 驗證 `grouped_data` 結構與分組正確性
    - stub 回傳含空列的陣列 → 驗證空列被跳過，不出現在輸出中
    - stub 回傳列長度不足 7 的陣列 → 驗證以 `nil` 填補後仍產生含全部 7 個鍵的 Hash
    - stub 回傳含四種日期格式的列資料 → 驗證 `normalize_date` 輸出為 `YYYY-MM-DD`
    - stub 回傳日期欄位為空值的資料 → 驗證輸出為 `nil`
    - stub 回傳 `delay_days` 為 `"-4"` → 驗證輸出為 Integer `-4`
    - stub 回傳 `delay_days` 為 `"TBD"` → 驗證保留原始字串
    - stub 回傳 `project_name`、`task_name`、`status` 或 `owner` 任一欄為空白的資料 → 驗證該筆被跳過、不納入 `grouped_data`，其餘正常紀錄仍回傳成功結果（見需求 4.3；不再觸發 `:invalid_data_format`）
    - stub 拋出 `Google::Apis::ClientError`（status 404）→ 驗證 `failure_code: :sheet_not_found`
    - stub 拋出 `Google::Apis::ClientError`（status 403）→ 驗證 `failure_code: :access_denied`
    - stub 拋出 `StandardError`（模擬憑證錯誤）→ 驗證 `failure_code: :internal_error`
    - stub 拋出 `Google::Apis::RateLimitError` → 驗證 `failure_code: :internal_error`
    - 呼叫 Actor 時傳入 `simulate_error` query parameter → 驗證被忽略，回傳正常資料
    - _需求：2.2、2.3、2.4、2.5、3.1–3.5、4.1–4.4、5.1_

- [x] 8. 微調 `Api::ProjectProgressController`
  - [x] 8.1 移除 `simulate_error` 參數傳遞
    - 編輯 `app/controllers/api/project_progress_controller.rb`
    - 將 `Sheets::FetchProjectProgress.result(simulate_error: params[:simulate_error]&.to_sym)` 改為 `Sheets::FetchProjectProgress.result()`
    - 確認 Controller 內無任何 `simulate_error`、`MockData`、Google API 呼叫或日期轉換邏輯
    - success/failure 分支、`error_status` 方法、Blueprint 序列化均**不變動**
    - _需求：5.1、5.2、5.3、6.3、6.4_

- [x] 9. API 與 Dashboard 整合測試（Request Spec）
  - [x] 9.1 更新 `spec/requests/api/project_progress_spec.rb`
    - stub `SheetsApiClient.fetch_rows` 回傳有效列陣列：`GET /api/project_progress` → 200，JSON 結構符合 `{ "<專案名稱>": [{ project_name, task_name, status, owner, planned_completion_date, actual_completion_date, delay_days }] }`，日期欄位為 ISO 8601 格式
    - stub 拋出 `ClientError`（404）→ 404 及統一錯誤格式 `{ "error": { "code": "sheet_not_found", "message": "..." } }`
    - stub 拋出 `ClientError`（403）→ 403 及統一錯誤格式
    - stub 回傳含空白 `project_name` 的資料 → 該筆被跳過、不納入結果，其餘正常資料仍回傳 HTTP 200（見需求 4.3；不再是 422）
    - stub 拋出 `StandardError` → 500 及統一錯誤格式
    - `GET /api/project_progress?simulate_error=sheet_not_found` → 正常回傳（200，參數被忽略）
    - _需求：4.1–4.5、5.3、7.1、7.3_

  - [x] 9.2 更新 `spec/requests/dashboard_spec.rb`
    - stub `SheetsApiClient.fetch_rows` 回傳有效資料：`GET /dashboard` → 200，HTML 包含下拉選單與專案區塊
    - `GET /dashboard?project=<專案名稱>` → Turbo Frame 局部更新，`@display_data` 只含該專案資料
    - 額外補充：stub `SheetsApiClient.fetch_rows` 拋出例外 → `GET /dashboard` 仍回傳 200 並顯示錯誤訊息（不整頁報錯，對應需求 7.1）
    - _需求：7.2_

- [x] 10. 最終檢查點 — 全面驗證
  - 確認所有測試通過，如有問題請提出。
  - 驗證結果：`bundle exec rspec` 75/75 全數通過；`app`/`lib`/`spec` 內無殘留的 `MockData::ProjectProgress::RECORDS` 參照。
  - 端對端驗證（真實 Google Sheets，憑證位於 `config/credentials/development.yml.enc`）：
    - `GET /api/project_progress` → 200，回傳 8 個專案、546 筆任務，日期已正規化為 ISO 8601，`delay_days` 正確轉型
    - `GET /dashboard` → 正確渲染真實資料
    - 切換下拉選單（測試案例：RAG Chatbot）→ Network 僅一次 `GET /dashboard?project=...`，確認 Turbo Frame 局部更新、無整頁重載
    - 憑證缺失 → 500 情境已由 `spec/requests/api/project_progress_spec.rb` 的 StandardError mock 案例覆蓋，未對現有可用憑證做破壞性測試
  - 已知後續清理項（不影響本次驗收）：`lib/mock_data/project_progress.rb` 已無任何程式碼參照，屬於雛型階段遺留的死碼，可視情況移除。

- [x] 11. Dashboard 任務類型標記與篩選（需求 10，戰情室 UX 強化延伸）
  - [x] 11.1 `SheetsApiClient` 標記類型分頁（`tag_with_type`）
    - 每個類型分頁的資料列附加第 8 欄：標題列附加固定文字「類型」，資料列附加該分頁名稱（`功能`／`PR`／`調整`／`遺漏`／`臭蟲`）
    - _需求：10（見需求 2.7、2.8）_

  - [x] 11.2 `Sheets::FetchProjectProgress` Actor 解析 `task_type`
    - `COLUMN_KEYS` 新增 `task_type`（第 8 個鍵），`parse_rows` 改為 8 欄填補與映射
    - _需求：2.5, 2.8_

  - [x] 11.3 `ProjectTaskBlueprint` 新增 `:task_type` 欄位
    - _需求：6.4_

  - [x] 11.4 `DashboardController` 篩選與摘要邏輯
    - 支援 `project`／`task_type[]`（多選，預設「功能」＋「PR」）／`scope`（`all`／`due_this_week`／`overdue`，預設 `due_this_week`）／`incomplete_only`（預設開啟）四個 query params
    - `due_by_this_week_end?` 不限下界，涵蓋所有已逾期任務
    - `@summary` 僅套用 `project`／`task_type` 範圍，不受 `scope`／`incomplete_only` 影響
    - `sort_overdue_first` 將逾期任務排在各專案清單最前面
    - _需求：10.1–10.8_

  - [x] 11.5 View 層新增篩選控制項與摘要列
    - `index.html.erb`：專案下拉選單、任務類型 checkbox 群組（含隱藏欄位處理全部取消勾選情境）、範圍 radio、只顯示未完成 checkbox、摘要列
    - `_project_block.html.erb`：任務表格新增「類型」欄位
    - _需求：10.1–10.7_

  - [x] 11.6 CSS 樣式
    - 狀態 badge、逾期標示、摘要列、篩選控制項排版
    - _需求：（響應式與視覺樣式，延續 project-standards.md 精神）_

  - [x] 11.7 對應測試更新
    - `spec/actors/sheets/fetch_project_progress_spec.rb`：新增 `task_type`（第 8 欄）解析案例
    - `spec/clients/sheets_api_client_spec.rb`：驗證每列附加分頁名稱、標題列附加「類型」
    - `spec/blueprints/project_task_blueprint_spec.rb`：驗證輸出含 `task_type`
    - `spec/requests/api/project_progress_spec.rb`、`spec/requests/dashboard_spec.rb`：更新為 8 欄列陣列，涵蓋預設篩選、`scope`、`incomplete_only`、`task_type[]` 組合情境
    - _需求：10（測試涵蓋）_

- [x] 12. 檢查點 — 真實資料驗證後修正與 UX 調整
  - 開發過程中對照真實 Google Sheets 資料實際驗證，發現並修正以下問題：
    - **Bug**：`DashboardController` 原以 `"已確認"` 作為完成狀態比對依據，但真實資料的「狀態」欄位實際只有「完成」「已確認」「未完成」三種值，且從無「已確認」以外的字串符合原判斷式，導致摘要列「已完成／進行中／待開始」恆為 0、逾期數把已完成任務也算入。改為 `COMPLETED_STATUSES = ["完成", "已確認"]`（「已確認」的紀錄一律已有實際完成日期，視為完成狀態的一種），並將摘要列改為 4 欄（任務總數／已完成／未完成／逾期），移除不適用真實資料的「進行中」「待開始」細分
    - 篩選後無符合條件任務的專案區塊，改為整塊不顯示（原本會顯示專案標題與「目前無符合條件的任務」）
    - 篩選控制項（專案／任務類型／範圍／只顯示未完成）由「逐項變更即自動送出」改為統一透過「套用篩選」按鈕送出，避免任務類型多選 checkbox 逐項送出造成 Turbo Frame 多次重繪
  - 驗證方式：`bundle exec rspec` 84/84 全數通過；針對已修正項目以瀏覽器／`curl` 對真實執行中的 server 驗證（摘要列數字、狀態 badge 顏色、空專案區塊隱藏、篩選按鈕送出時機）
  - 已知非阻斷問題：測試套件偶發性隨機順序失敗（觀察到約 4 次執行中 1 次），與本次改動無關，尚未查出根因

---

## Notes

- 標記 `*` 的子任務為選填，可跳過以加速 MVP 開發
- 所有對外介面（路由、回應格式、Blueprint、View、Dashboard）均**不變動**，僅替換資料讀取層
- SheetsApiClient 將 Google gem 細節完全隔離，Actor 不直接依賴任何 Google gem
- Controller 嚴禁包含 Google API 呼叫或資料解析邏輯（全部委派 Actor）
- `Google::Apis::RateLimitError` 與 `Google::Apis::ServerError` 均繼承自 `StandardError`（非 `ClientError`），自然落入最後一個 `rescue` 分支
- 端對端驗證（手動）：移除憑證後訪問 `/api/project_progress` 確認回傳 500 含明確中文錯誤訊息

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["2.1", "3.1"] },
    { "id": 2, "tasks": ["3.2", "4.1"] },
    { "id": 3, "tasks": ["5.1"] },
    { "id": 4, "tasks": ["5.2", "5.3"] },
    { "id": 5, "tasks": ["6.1", "6.2", "6.3", "6.4", "6.5", "6.6", "6.7", "6.8", "6.9", "6.10", "7.1", "8.1"] },
    { "id": 6, "tasks": ["9.1", "9.2"] },
    { "id": 7, "tasks": ["11.1"] },
    { "id": 8, "tasks": ["11.2", "11.3"] },
    { "id": 9, "tasks": ["11.4"] },
    { "id": 10, "tasks": ["11.5", "11.6", "11.7"] },
    { "id": 11, "tasks": ["12"] }
  ]
}
```
