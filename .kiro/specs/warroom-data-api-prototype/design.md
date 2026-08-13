# 設計文件

## Overview

戰情室資料讀取 API 雛型採 Ruby on Rails 完整 stack，以 service_actor pattern 封裝商業邏輯，
前端使用 Rails ERB view 搭配 Turbo Frame 實作局部更新。所有資料來自記憶體內固定模擬資料，無資料庫依賴。

本系統的目的是驗證資料讀取層的可行性。它提供一個 JSON API endpoint 回傳 305 專案進度資料（以專案名稱分組），
並提供一個簡單的 Dashboard 頁面，讓開發者可以目視驗證資料結構與內容。

---

## Architecture

```
HTTP 請求
    │
    ├──► GET /api/project_progress
    │         │
    │         ▼
    │    Api::ProjectProgressController#index
    │         │
    │         ▼
    │    Sheets::FetchProjectProgress (Actor)
    │         │
    │         ▼
    │    MockData::ProjectProgress::RECORDS
    │
    └──► GET /dashboard?project=XXX
              │
              ▼
         DashboardController#index
              │
              ▼
         Sheets::FetchProjectProgress (Actor)
              │
              ▼
         MockData::ProjectProgress::RECORDS
              │
              ▼
         ERB View + Turbo Frame
```

**請求流程**：

1. HTTP 請求進入 Rails Router
2. Router 分派至對應 Controller action
3. Controller 呼叫 `Sheets::FetchProjectProgress.call`
4. Actor 從 `MockData::ProjectProgress::RECORDS` 讀取資料，執行日期正規化與分組
5. Actor 回傳 success result（含 `grouped_data`）或 failure result（含 `failure_code` 與 `message`）
6. Controller 將 Actor 結果渲染為 JSON（API）或傳入 View（Dashboard）

---

## Components and Interfaces

### 模擬資料層：`MockData::ProjectProgress`

**檔案**：`lib/mock_data/project_progress.rb`

```ruby
module MockData
  module ProjectProgress
    RECORDS = [
      {
        project_name: "系統優化",
        task_name: "資料庫索引調整",
        status: "進行中",
        owner: "王小明",
        planned_completion_date: "2026/7/31",
        actual_completion_date: nil,
        delay_days: nil
      },
      {
        project_name: "系統優化",
        task_name: "快取層導入",
        status: "待開始",
        owner: "李美華",
        planned_completion_date: "2026/8/15",
        actual_completion_date: nil,
        delay_days: nil
      },
      {
        project_name: "行動版改版",
        task_name: "UI 元件重構",
        status: "已完成",
        owner: "陳大偉",
        planned_completion_date: "2026/07/10",
        actual_completion_date: "2026/7/12",
        delay_days: 2
      },
      {
        project_name: "行動版改版",
        task_name: "API 效能優化",
        status: "已完成",
        owner: "陳大偉",
        planned_completion_date: "2026-8-5",
        actual_completion_date: "2026-08-01",
        delay_days: -4
      }
      # 至少包含 2 個專案、每專案至少 3 筆任務
    ].freeze
  end
end
```

- 日期欄位混用 `YYYY/M/D`、`YYYY/MM/DD`、`YYYY-M-D`、`YYYY-MM-DD` 四種格式，涵蓋需求 4.1 列出的所有支援格式
- 部分紀錄的日期欄位為 `nil`，以驗證空值處理
- 包含一筆 `delay_days` 為負數的紀錄（`-4`，代表提早完成），對照真實 305 表中存在提早完成（負延誤天數）的實際案例，避免誤植為只會是非負整數

---

### Service Actor：`Sheets::FetchProjectProgress`

**檔案**：`app/actors/sheets/fetch_project_progress.rb`

```ruby
module Sheets
  class FetchProjectProgress < ApplicationActor
    class ValidationError < StandardError; end

    input :simulate_error, type: Symbol, default: nil, allow_nil: true
    # simulate_error 供雛型展示／測試全部 4 種錯誤格式使用（sheet_not_found、
    # invalid_data_format、access_denied、internal_error）。因本階段資料來源固定為
    # 記憶體常數，sheet_not_found／access_denied／internal_error 這三種在正常流程下
    # 不會自然發生，僅能靠此參數模擬（例如 API 呼叫 ?simulate_error=sheet_not_found）；
    # invalid_data_format 除了可用 simulate_error 模擬，也可由不合法的 fixture 資料
    # 透過 validate_records! 自然觸發。待未來串接真實 Google Sheets API 時可移除。
    output :grouped_data   # Hash：{ "專案名稱" => [任務 Hash 陣列] }
    output :failure_code   # Symbol：:sheet_not_found | :invalid_data_format | :access_denied | :internal_error
    output :message        # String：錯誤描述

    SIMULATED_ERROR_MESSAGES = {
      sheet_not_found: "找不到指定分頁（模擬情境）",
      invalid_data_format: "資料格式不符預期（模擬情境）",
      access_denied: "資料來源存取權限不足（模擬情境）",
      internal_error: "未預期的內部錯誤（模擬情境）"
    }.freeze

    def call
      if simulate_error
        return fail!(failure_code: simulate_error,
                      message: SIMULATED_ERROR_MESSAGES.fetch(simulate_error, "模擬錯誤"))
      end

      records = MockData::ProjectProgress::RECORDS
      normalized = records.map { |r| normalize_record(r) }
      validate_records!(normalized)

      self.grouped_data = normalized.group_by { |r| r[:project_name] }
    rescue ValidationError => e
      fail!(failure_code: :invalid_data_format, message: e.message)
    rescue => e
      fail!(failure_code: :internal_error, message: e.message)
    end

    private

    def normalize_record(record)
      record.merge(
        planned_completion_date: normalize_date(record[:planned_completion_date]),
        actual_completion_date:  normalize_date(record[:actual_completion_date])
      )
    end

    def normalize_date(value)
      return nil if value.nil? || value.to_s.strip.empty?
      date = Date.parse(value.to_s.gsub("/", "-"))
      date.strftime("%Y-%m-%d")
    rescue ArgumentError
      value
    end

    def validate_records!(records)
      required = %i[project_name task_name status owner]
      records.each do |r|
        missing = required.select { |k| r[k].nil? || r[k].to_s.strip.empty? }
        raise ValidationError, "缺少必要欄位：#{missing.join(', ')}" if missing.any?
      end
    end
  end
end
```

**介面**：

| 項目            | 說明                                                              |
|-----------------|-------------------------------------------------------------------|
| 輸入            | `simulate_error`（Symbol，可選，僅供雛型模擬 4 種錯誤格式展示用） |
| 輸出（成功）    | `grouped_data`：Hash，鍵為專案名稱，值為任務 Hash 陣列           |
| 輸出（失敗）    | `failure_code`（Symbol）+ `message`（String）                    |

---

### Blueprint 序列化層：`ProjectTaskBlueprint`

**檔案**：`app/blueprints/project_task_blueprint.rb`

依團隊慣例使用 `blueprinter` gem，統一定義要輸出給 API 與 Dashboard View 的任務欄位，
避免欄位清單同時寫在 Controller 與 View 兩處而重複維護。

```ruby
class ProjectTaskBlueprint < Blueprinter::Base
  identifier :task_name

  fields :project_name, :task_name, :status, :owner,
         :planned_completion_date, :actual_completion_date, :delay_days
end
```

- API Controller：`ProjectTaskBlueprint.render_as_hash(tasks)` 序列化每個專案鍵值下的任務陣列，再 `render json:`
- Dashboard Controller：同一 Blueprint 序列化 `@display_data` 內的任務陣列，View 端存取的欄位名稱與 API 回應完全一致

---

### API Controller：`Api::ProjectProgressController`

**檔案**：`app/controllers/api/project_progress_controller.rb`

```ruby
module Api
  class ProjectProgressController < ApplicationController
    def index
      result = Sheets::FetchProjectProgress.call(simulate_error: params[:simulate_error]&.to_sym)

      if result.success?
        serialized = result.grouped_data.transform_values { |tasks| ProjectTaskBlueprint.render_as_hash(tasks) }
        render json: serialized
      else
        status = error_status(result.failure_code)
        render json: { error: { code: result.failure_code, message: result.message } },
               status: status
      end
    end

    private

    def error_status(code)
      { sheet_not_found: 404, invalid_data_format: 422,
        access_denied: 403, internal_error: 500 }.fetch(code, 500)
    end
  end
end
```

Controller 不含任何資料讀取或轉換邏輯。

---

### Dashboard Controller：`DashboardController`

**檔案**：`app/controllers/dashboard_controller.rb`

```ruby
class DashboardController < ApplicationController
  def index
    result = Sheets::FetchProjectProgress.call
    if result.success?
      @grouped_data     = result.grouped_data
      @project_names    = @grouped_data.keys
      @selected_project = params[:project].presence
      filtered          = @selected_project ? @grouped_data.slice(@selected_project) : @grouped_data
      @display_data     = filtered.transform_values { |tasks| ProjectTaskBlueprint.render_as_hash(tasks) }
      @error            = nil
    else
      @grouped_data     = {}
      @project_names    = []
      @selected_project = nil
      @display_data     = {}
      @error            = result.message
    end
  end
end
```

`@display_data` 才是 View 實際迭代 render 的資料：未選擇專案（`params[:project]` 為空）時等於 `@grouped_data`（需求 6.3「全部專案」）；選定專案時用 `Hash#slice` 只留下該鍵（需求 6.2）。

---

### View 層

**視圖結構**：

```
app/views/dashboard/
  index.html.erb           # 主頁面：下拉選單 + turbo_frame_tag
  _project_block.html.erb  # 局部樣板：單一專案區塊（表格）
```

`index.html.erb` 以 GET 表單提交 `?project=XXX`，Turbo Frame（`id="project-content"`）
攔截請求並局部更新，不觸發整頁重載；Turbo Frame 內迭代 `@display_data`（而非 `@grouped_data`）
逐一 render `_project_block.html.erb`，選定專案時 `@display_data` 只含該專案一個鍵。

`_project_block.html.erb` 顯示欄位：任務名稱、狀態、負責人、預計完成日期、實際完成日期、延誤天數。
若該區塊無資料，顯示「目前無資料」提示文字。

---

### 路由

```ruby
# config/routes.rb
Rails.application.routes.draw do
  root "dashboard#index"
  get "/dashboard", to: "dashboard#index"

  namespace :api do
    get "project_progress", to: "project_progress#index"
  end
end
```

---

## Data Models

### 任務紀錄（Task Record）

模擬資料的每筆任務紀錄為 Ruby Hash，欄位如下：

| 欄位名稱                  | 類型            | 說明                              |
|---------------------------|-----------------|-----------------------------------|
| `project_name`            | String          | 專案名稱（分組用鍵值）            |
| `task_name`               | String          | 任務名稱                          |
| `status`                  | String          | 狀態（如：待開始、進行中、已完成）|
| `owner`                   | String          | 負責人                            |
| `planned_completion_date` | String \| nil   | 預計完成日期（正規化後為 ISO 8601）|
| `actual_completion_date`  | String \| nil   | 實際完成日期（正規化後為 ISO 8601）|
| `delay_days`              | Integer \| nil  | 延誤天數                          |

### API 回應結構（成功）

```json
{
  "系統優化": [
    {
      "project_name": "系統優化",
      "task_name": "資料庫索引調整",
      "status": "進行中",
      "owner": "王小明",
      "planned_completion_date": "2026-07-31",
      "actual_completion_date": null,
      "delay_days": null
    }
  ],
  "行動版改版": [...]
}
```

### API 回應結構（失敗）

```json
{
  "error": {
    "code": "sheet_not_found",
    "message": "找不到指定分頁"
  }
}
```

### 日期正規化規則

| 輸入範例     | 輸出         |
|--------------|--------------|
| `2026/7/22`  | `2026-07-22` |
| `2026/07/22` | `2026-07-22` |
| `2026-7-5`   | `2026-07-05` |
| `2026-07-05` | `2026-07-05` |
| `nil` / `""` | `null`       |
| 無法解析值   | 原始字串不變 |

---

## Error Handling

### Actor 層錯誤處理

Actor 使用 `service_actor` 的 `fail!` 機制回傳結構化失敗結果：

| 情境                         | failure_code           | HTTP 狀態 |
|------------------------------|------------------------|-----------|
| 找不到模擬資料分頁（透過 `simulate_error` 觸發）         | `:sheet_not_found`     | 404       |
| 缺少必要欄位或格式不符（自然觸發，或透過 `simulate_error`）| `:invalid_data_format` | 422       |
| 存取權限不足（透過 `simulate_error` 觸發）                | `:access_denied`       | 403       |
| 其他未預期錯誤（透過 `simulate_error` 觸發，或程式例外）  | `:internal_error`      | 500       |

`sheet_not_found`、`access_denied`、`internal_error` 這三種在本雛型的固定記憶體資料來源下
不會自然發生，僅能透過 Actor 的 `simulate_error` 輸入參數（對應 API 的 `?simulate_error=`
query param）人為觸發，用來驗證錯誤格式與頁面錯誤顯示；`invalid_data_format` 除了可用
`simulate_error` 模擬，也可由不合法的 fixture 資料透過 `validate_records!` 自然觸發。

### Controller 層錯誤處理

Controller 根據 `result.failure_code` 對應 HTTP 狀態碼，統一回傳：

```json
{ "error": { "code": "<failure_code>", "message": "<描述>" } }
```

### View 層錯誤處理

- `@error` 不為 nil 時，Dashboard 頁面在主內容區顯示錯誤訊息
- 即使整體 Actor 呼叫失敗，已渲染的其他 Turbo Frame 區塊不受影響
- 個別專案區塊無資料時，顯示「目前無資料」，不影響其他專案區塊

---

## Correctness Properties

以下正確性屬性為本雛型的核心驗證基礎，可透過 Property-Based Testing（PBT）執行：

### Property 1: 分組完整性

**Validates: Requirements 2.1, 2.2**

對任意非空的 `RECORDS` 陣列，`grouped_data` 中所有陣列的元素總數必須等於 `RECORDS` 的筆數，無資料遺失。

### Property 2: 日期格式一致性

**Validates: Requirements 4.1, 4.2**

對任意符合 `YYYY/M/D`、`YYYY/MM/DD`、`YYYY-M-D`、`YYYY-MM-DD` 格式的日期輸入，Actor 輸出的日期字串必須符合 `/\A\d{4}-\d{2}-\d{2}\z/`。

### Property 3: 空值保留

**Validates: Requirements 4.3**

對任意 `nil` 或空字串的日期輸入，`normalize_date` 的輸出必定為 `nil`（JSON 中序列化為 `null`）。

### Property 4: 錯誤格式一致性

**Validates: Requirements 3.5**

對任意觸發 Actor 失敗的輸入，API 回應的 JSON body 必須包含 `error.code` 與 `error.message` 兩個鍵，缺一不可。

### Property 5: Controller 純粹性

**Validates: Requirements 8.2**

Controller action 的原始碼中不得直接參照 `MockData` 模組或呼叫任何日期轉換方法；所有邏輯必須委派給 Actor。

### Property 6: 分組鍵值完整性

**Validates: Requirements 2.1**

`grouped_data` 的所有鍵值集合必須與原始 `RECORDS` 中 `project_name` 欄位的唯一值集合完全相同，無多餘鍵值。

### Property 7: Blueprint 欄位完整性

**Validates: Requirements 8.4**

對任意任務紀錄，`ProjectTaskBlueprint.render_as_hash` 的輸出必須恰好包含 `project_name`、`task_name`、
`status`、`owner`、`planned_completion_date`、`actual_completion_date`、`delay_days` 這 7 個鍵，不多不少。

---

## Testing Strategy

### 單元測試

- **`Sheets::FetchProjectProgress` Actor**：
  - 正常資料 → 驗證 `grouped_data` 結構與分組正確性
  - 日期格式各種組合（含四種支援格式）→ 驗證 `normalize_date` 輸出
  - 空值日期 → 驗證輸出為 `null`
  - 負數 `delay_days` → 驗證原值不變、不被誤判為無效資料
  - 缺少必要欄位的資料 → 驗證回傳 `failure_code: :invalid_data_format`
  - `simulate_error: :sheet_not_found` → 驗證回傳 `failure_code: :sheet_not_found`
  - `simulate_error: :invalid_data_format` → 驗證回傳 `failure_code: :invalid_data_format`
  - `simulate_error: :access_denied` → 驗證回傳 `failure_code: :access_denied`
  - `simulate_error: :internal_error` → 驗證回傳 `failure_code: :internal_error`
  - `ProjectTaskBlueprint.render_as_hash` 輸出 → 驗證恰好包含 7 個欄位

### 整合測試（Request Spec）

- `GET /api/project_progress` → 200 回傳符合格式的 JSON
- `GET /api/project_progress?simulate_error=sheet_not_found` → 404 及統一錯誤格式
- `GET /api/project_progress?simulate_error=invalid_data_format` → 422 及統一錯誤格式
- `GET /api/project_progress?simulate_error=access_denied` → 403 及統一錯誤格式
- `GET /api/project_progress?simulate_error=internal_error` → 500 及統一錯誤格式
- `GET /dashboard` → 200 回傳 HTML，包含下拉選單與專案區塊
- `GET /dashboard?project=系統優化` → Turbo Frame 局部更新，僅顯示指定專案（`@display_data` 只含一個鍵）

### 端對端驗證

- 手動訪問 `/dashboard`，確認頁面呈現正確
- 切換下拉選單，確認 Turbo Frame 局部更新（不整頁重載）
- 直接呼叫 `curl http://localhost:3000/api/project_progress`，驗證 JSON 結構
