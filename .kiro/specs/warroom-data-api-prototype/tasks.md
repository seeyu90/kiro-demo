# Implementation Plan: 戰情室資料讀取 API 雛型

## Overview

以 Ruby on Rails 建立可實際運行的 API 雛型，封裝 305 專案進度資料讀取邏輯。
所有商業邏輯透過 `service_actor` pattern 封裝於 Actor 層，前端採用 ERB + Turbo Frame 局部更新，
資料來源為記憶體內模擬資料，無資料庫依賴。

每項任務均可獨立開發、驗證並 Commit。

---

## Tasks

- [-] 1. 初始化 Rails 專案骨架
  - [x] 1.1 建立 Rails 專案（略過資料庫）
    - 執行 `rails new warroom-data-api-prototype --skip-active-record --skip-active-storage --skip-action-mailbox --skip-action-text --skip-test`
    - 確認專案目錄結構正確生成
    - _需求：8.1、8.3_

  - [x] 1.2 加入 service_actor、turbo-rails、blueprinter 與 rspec-rails gem
    - 在 `Gemfile` 新增 `gem "service_actor"`、`gem "turbo-rails"`、`gem "blueprinter"`
    - 在 `:development, :test` group 新增 `gem "rspec-rails"`（本專案測試框架，`rails new` 已用 `--skip-test` 跳過 Minitest）
    - 執行 `bundle install`
    - 執行 `rails generate rspec:install`
    - 執行 `rails turbo:install`（安裝 Turbo）
    - _需求：8.1、8.4_

  - [-] 1.3 建立 `ApplicationActor` 基底類別
    - 建立 `app/actors/application_actor.rb`，繼承 `Actor::Base`
    - 確認 `app/actors/` 目錄在 Rails autoload 路徑中（或加入 `config/application.rb`）
    - _需求：8.1_

  - [ ]* 1.4 驗證 Rails server 可正常啟動
    - 執行 `rails server -p 3000`，確認無啟動錯誤
    - _需求：8.1_

- [ ] 2. 模擬資料層與 Actor 資料邏輯
  - [ ] 2.1 建立 `MockData::ProjectProgress::RECORDS`
    - 建立 `lib/mock_data/project_progress.rb`
    - 實作含至少 2 個專案、每專案至少 3 筆任務的模擬資料陣列（frozen）
    - 日期欄位混用 `YYYY/M/D`、`YYYY/MM/DD`、`YYYY-M-D`、`YYYY-MM-DD` 四種格式，並包含 `nil` 值
    - 包含至少一筆 `delay_days` 為負數的紀錄（提早完成情境，對照真實 305 表資料）
    - 確認 `lib/` 已加入 Rails autoload（`config.autoload_lib`）
    - _需求：8.3_

  - [ ] 2.2 建立 `Sheets::FetchProjectProgress` Actor — 日期正規化
    - 建立 `app/actors/sheets/fetch_project_progress.rb`
    - 實作 `normalize_date` 私有方法：支援 `YYYY/M/D`、`YYYY/MM/DD`、`YYYY-M-D`、`YYYY-MM-DD` 轉換為 `YYYY-MM-DD`
    - `nil` 或空字串輸入必須回傳 `nil`；無法解析的值保留原始字串
    - _需求：4.1、4.2、4.3、4.4_

  - [ ]* 2.3 撰寫 Property 2 測試：日期格式一致性
    - **Property 2：日期格式一致性**
    - 對任意符合支援格式的日期輸入，輸出必須符合 `/\A\d{4}-\d{2}-\d{2}\z/`
    - **驗證：需求 4.1、4.2**

  - [ ]* 2.4 撰寫 Property 3 測試：空值保留
    - **Property 3：空值保留**
    - 對任意 `nil` 或空字串輸入，`normalize_date` 輸出必定為 `nil`
    - **驗證：需求 4.3**

  - [ ] 2.5 實作 Actor — 分組、驗證與錯誤處理
    - 定義 `Sheets::FetchProjectProgress::ValidationError < StandardError`（供 `validate_records!` 使用）
    - 宣告 `input :simulate_error`（可選 Symbol，涵蓋 `sheet_not_found`／`invalid_data_format`／`access_denied`／`internal_error` 四種）、`output :grouped_data`、`output :failure_code`、`output :message`
    - `call` 方法開頭：若 `simulate_error` 有值，直接以 `fail!` 回傳對應模擬錯誤，不執行後續讀取
    - 否則讀取 `RECORDS`、正規化日期、驗證必要欄位、依 `project_name` 分組
    - 實作 `validate_records!`：檢查 `project_name`、`task_name`、`status`、`owner` 不為空，不符合時 `raise ValidationError`
    - 以 `fail!` 回傳結構化失敗結果（`failure_code` + `message`）
    - _需求：1.2、1.3、1.4、1.5、1.6、2.1、2.2、2.3、3.1–3.5、8.1、8.3_

  - [ ]* 2.6 撰寫 Property 1 測試：分組完整性
    - **Property 1：分組完整性**
    - 對任意非空 `RECORDS`，`grouped_data` 所有陣列元素總數必須等於 `RECORDS` 筆數
    - **驗證：需求 2.1、2.2**

  - [ ]* 2.7 撰寫 Property 6 測試：分組鍵值完整性
    - **Property 6：分組鍵值完整性**
    - `grouped_data` 鍵值集合必須與原始 `RECORDS` 中 `project_name` 唯一值集合完全相同
    - **驗證：需求 2.1、2.3**

  - [ ]* 2.8 撰寫 Actor 單元測試
    - 正常資料 → 驗證 `grouped_data` 結構與分組正確性
    - 缺少必要欄位資料（真實不合法 fixture，非 `simulate_error`）→ 驗證回傳 `failure_code: :invalid_data_format`
    - `simulate_error: :sheet_not_found` → 驗證回傳 `failure_code: :sheet_not_found`
    - `simulate_error: :invalid_data_format` → 驗證回傳 `failure_code: :invalid_data_format`
    - `simulate_error: :access_denied` → 驗證回傳 `failure_code: :access_denied`
    - `simulate_error: :internal_error` → 驗證回傳 `failure_code: :internal_error`
    - _需求：2.1、2.2、2.3、3.2_

  - [ ] 2.9 建立 `ProjectTaskBlueprint` 序列化層
    - 建立 `app/blueprints/project_task_blueprint.rb`，繼承 `Blueprinter::Base`
    - 定義欄位：`project_name`、`task_name`、`status`、`owner`、`planned_completion_date`、`actual_completion_date`、`delay_days`
    - 欄位清單只在此定義一次，供 API Controller 與 Dashboard Controller 共用
    - _需求：8.4_

  - [ ]* 2.10 撰寫 Property 7 測試：Blueprint 欄位完整性
    - **Property 7：Blueprint 欄位完整性**
    - 對任意任務紀錄，`ProjectTaskBlueprint.render_as_hash` 輸出必須恰好包含全部 7 個欄位，不多不少
    - **驗證：需求 8.4**

- [ ] 3. 檢查點 — Actor 層驗證
  - 確認所有 Actor 單元測試與 Property 測試通過，如有問題請提出。

- [ ] 4. API Controller 與路由
  - [ ] 4.1 建立 `Api::ProjectProgressController`
    - 建立 `app/controllers/api/project_progress_controller.rb`
    - 實作 `index` action：呼叫 `Sheets::FetchProjectProgress.call(simulate_error: params[:simulate_error]&.to_sym)`
    - 成功時以 `ProjectTaskBlueprint.render_as_hash` 序列化各專案任務陣列後 `render json:`；失敗時依 `failure_code` 對應 HTTP 狀態碼並回傳統一錯誤格式
    - Controller 內部不得直接參照 `MockData` 或呼叫任何日期轉換方法
    - _需求：1.1、1.2、3.1–3.5、8.2、8.4_

  - [ ] 4.2 設定路由
    - 編輯 `config/routes.rb`，新增 `namespace :api { get "project_progress", to: "project_progress#index" }`
    - _需求：1.1_

  - [ ]* 4.3 撰寫 Property 4 測試：錯誤格式一致性
    - **Property 4：錯誤格式一致性**
    - 對任意觸發 Actor 失敗的輸入，API 回應 JSON body 必須包含 `error.code` 與 `error.message` 兩個鍵
    - **驗證：需求 3.5**

  - [ ]* 4.4 撰寫 Property 5 測試：Controller 純粹性
    - **Property 5：Controller 純粹性**
    - Controller action 原始碼中不得直接參照 `MockData` 模組或呼叫任何日期轉換方法
    - **驗證：需求 8.2**

  - [ ]* 4.5 撰寫 API Request Spec
    - `GET /api/project_progress` → 200，回傳符合 `{ "<專案名稱>": [<任務陣列>] }` 格式的 JSON
    - `GET /api/project_progress?simulate_error=sheet_not_found` → 404 及統一錯誤格式
    - `GET /api/project_progress?simulate_error=invalid_data_format` → 422 及統一錯誤格式
    - `GET /api/project_progress?simulate_error=access_denied` → 403 及統一錯誤格式
    - `GET /api/project_progress?simulate_error=internal_error` → 500 及統一錯誤格式
    - _需求：1.1、1.2、3.1–3.5_

- [ ] 5. 檢查點 — API 層驗證
  - 確認所有 API 測試通過，curl 可取得正確 JSON 回應，如有問題請提出。

- [ ] 6. Dashboard Controller 與 View
  - [ ] 6.1 建立 `DashboardController`
    - 建立 `app/controllers/dashboard_controller.rb`
    - 實作 `index` action：呼叫 Actor，設定 `@grouped_data`、`@project_names`、`@selected_project`
    - 依 `@selected_project` 過濾出 `filtered`（有選擇專案時用 `Hash#slice`，否則等於 `@grouped_data`），
      再以 `ProjectTaskBlueprint.render_as_hash` 序列化為 `@display_data` 供 View 使用
    - 設定 `@error`
    - _需求：5.1、5.2、6.2、6.3、7.1、8.4_

  - [ ] 6.2 設定 Dashboard 路由
    - 編輯 `config/routes.rb`，新增 `root "dashboard#index"` 與 `get "/dashboard", to: "dashboard#index"`
    - _需求：5.1_

  - [ ] 6.3 建立 Dashboard 主樣板 `app/views/dashboard/index.html.erb`
    - 實作下拉選單（GET 表單提交 `?project=XXX`），列出所有專案名稱及「全部專案」選項
    - 以 `turbo_frame_tag "project-content"` 包裹主內容區
    - 於 Turbo Frame 內迭代 `@display_data`（而非 `@grouped_data`）渲染各專案區塊；`@error` 不為 nil 時顯示錯誤訊息
    - _需求：5.2、5.3、6.1、6.3、7.1_

  - [ ] 6.4 建立 `_project_block.html.erb` 局部樣板
    - 顯示欄位：任務名稱、狀態、負責人、預計完成日期、實際完成日期、延誤天數
    - 無資料時顯示「目前無資料」
    - _需求：5.4、7.2_

  - [ ]* 6.5 撰寫 Dashboard Request Spec
    - `GET /dashboard` → 200，回傳包含下拉選單與專案區塊的 HTML
    - `GET /dashboard?project=系統優化` → Turbo Frame 局部更新，僅顯示指定專案
    - _需求：5.1、5.2、5.3、6.2_

- [ ] 7. 最終檢查點 — 全面驗證
  - 確認所有測試通過，如有問題請提出。

---

## Notes

- 標記 `*` 的子任務為選填，可跳過以加速 MVP 開發
- 每項任務參照對應需求編號以利追溯
- 檢查點確保每個階段漸進驗證
- Property 測試驗證系統的普遍正確性，單元測試驗證具體範例與邊界條件
- Controller 嚴禁包含資料讀取或日期轉換邏輯（全部委派 Actor）

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2"] },
    { "id": 1, "tasks": ["1.3"] },
    { "id": 2, "tasks": ["1.4", "2.1"] },
    { "id": 3, "tasks": ["2.2"] },
    { "id": 4, "tasks": ["2.3", "2.4", "2.5"] },
    { "id": 5, "tasks": ["2.6", "2.7", "2.8", "2.9"] },
    { "id": 6, "tasks": ["2.10", "4.1", "4.2", "4.3", "4.4"] },
    { "id": 7, "tasks": ["4.5", "6.1"] },
    { "id": 8, "tasks": ["6.2", "6.3"] },
    { "id": 9, "tasks": ["6.4"] },
    { "id": 10, "tasks": ["6.5"] }
  ]
}
```
