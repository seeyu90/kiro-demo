# 設計文件

## Overview

warroom-data-api-real-source 是 warroom-data-api-prototype 的延續，目標是將資料來源從記憶體內固定常數替換為真實的 Google Sheets 305 專案進度表。

替換範圍僅限於 `Sheets::FetchProjectProgress` Actor 的**內部資料讀取層**：新增 `SheetsApiClient` 封裝 Google Sheets API 的初始化與呼叫，Actor 改為呼叫 `SheetsApiClient` 取得原始列陣列，再執行與雛型相同的解析、正規化、驗證與分組邏輯。

所有對外介面均**與雛型完全一致、不變動**：
- `GET /api/project_progress` 回應格式不變
- `GET /dashboard` 頁面結構不變
- `ProjectTaskBlueprint` 序列化欄位不變
- `Api::ProjectProgressController` 不變
- `DashboardController` 不變
- 移除 `simulate_error` 參數，四種錯誤由真實情境自然觸發

新增 gem 依賴：
- `google-apis-sheets_v4`（Google Sheets API v4 官方 Ruby 客戶端）
- `googleauth`（Google OAuth2 認證，Service Account 支援）

---

## Architecture

```
HTTP 請求
    │
    ├──► GET /api/project_progress
    │         │
    │         ▼
    │    Api::ProjectProgressController#index       ← 與雛型一致，不變動
    │         │
    │         ▼
    │    Sheets::FetchProjectProgress (Actor)        ← 僅替換內部讀取邏輯
    │         │
    │         ▼
    │    SheetsApiClient                             ← 新增：封裝 Sheets API 呼叫
    │         │
    │         ▼
    │    Google Sheets API (spreadsheets.values.get)
    │
    └──► GET /dashboard
              │
              ▼
         DashboardController#index                  ← 與雛型一致，不變動
              │
              ▼
         Sheets::FetchProjectProgress (Actor)        ← 同上
              │
              ▼
         SheetsApiClient → Google Sheets API
              │
              ▼
         ERB View + Turbo Frame                     ← 與雛型一致，不變動
```

**請求流程**：

1. HTTP 請求進入 Rails Router
2. Router 分派至對應 Controller action（與雛型相同）
3. Controller 呼叫 `Sheets::FetchProjectProgress.result()`（不再傳入 `simulate_error`）
4. Actor 呼叫 `SheetsApiClient.fetch_rows`，取得 Google Sheets 原始列陣列
5. Actor 跳過標題列（第 1 列），過濾空列，將各列映射為任務 Hash
6. Actor 執行欄位正規化（日期格式、`delay_days` 型別轉換）
7. Actor 執行 `validate_records!` 驗證必要欄位
8. Actor 回傳 success result（含 `grouped_data`）或 failure result（含 `failure_code` 與 `message`）
9. Controller 將 Actor 結果渲染為 JSON（API）或傳入 View（Dashboard）

**雛型 vs 本階段差異對照**：

| 層級 | 雛型 | 本階段 |
|------|------|--------|
| 資料來源 | `MockData::ProjectProgress::RECORDS`（記憶體常數） | Google Sheets API（`SheetsApiClient`） |
| `simulate_error` 參數 | 有 | 移除 |
| 錯誤觸發 | 手動模擬 | 真實 API 例外 |
| Controller / Blueprint / View | — | **不變動** |

---

## Components and Interfaces

### 新增：`SheetsApiClient`

**檔案**：`app/clients/sheets_api_client.rb`

負責初始化 `google-apis-sheets_v4` service 物件、執行 `spreadsheets.values.get` 呼叫，並回傳原始列陣列（`Array<Array<String>>` 或 `nil`）。將 Google API 的具體細節完全隔離於此類，Actor 不直接依賴任何 Google gem。

```ruby
# frozen_string_literal: true

class SheetsApiClient
  SPREADSHEET_ID = "11gwDnOqEiGqj_VF2XF7AzxiJTiOW_k2knF6-4yQCej8"
  SHEET_RANGE    = "2026!A:G"
  SCOPES         = ["https://www.googleapis.com/auth/spreadsheets.readonly"].freeze

  # 回傳原始列陣列（含標題列），若 API 呼叫失敗則重新拋出例外
  # @return [Array<Array<String>>] 原始列資料
  # @raise [Google::Apis::ClientError]  403 / 404 等 API 層級錯誤
  # @raise [Google::Apis::ServerError]  5xx 伺服器端錯誤
  # @raise [StandardError]              憑證載入失敗或其他未預期錯誤
  def self.fetch_rows
    new.fetch_rows
  end

  def fetch_rows
    service = build_service
    response = service.get_spreadsheet_values(
      SPREADSHEET_ID,
      SHEET_RANGE,
      value_render_option: "FORMATTED_VALUE"
    )
    response.values || []
  end

  private

  def build_service
    service = Google::Apis::SheetsV4::SheetsService.new
    service.authorization = credentials
    service
  end

  # 憑證讀取策略：Rails credentials 優先，fallback 至環境變數
  def credentials
    json = rails_credentials_json || env_credentials_json
    raise "找不到 Google Service Account 憑證，請設定 Rails credentials 或環境變數 GOOGLE_SHEETS_CREDENTIALS_JSON" if json.nil?

    Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(json),
      scope: SCOPES
    )
  end

  def rails_credentials_json
    raw = Rails.application.credentials.dig(:google_sheets, :service_account_json)
    raw.present? ? raw.to_s : nil
  rescue => _e
    nil
  end

  def env_credentials_json
    json = ENV["GOOGLE_SHEETS_CREDENTIALS_JSON"]
    json.present? ? json : nil
  end
end
```

**憑證讀取策略**：

1. 優先從 Rails encrypted credentials 讀取：`Rails.application.credentials.google_sheets.service_account_json`
2. 若不存在，fallback 至環境變數 `GOOGLE_SHEETS_CREDENTIALS_JSON`（值為 JSON 字串）
3. 兩者均無法取得時，拋出明確錯誤訊息，由 Actor 捕捉並轉為 `failure_code: :internal_error`

**Google Sheets API 例外類型對應**：

| 例外類型 | 說明 |
|----------|------|
| `Google::Apis::ClientError` status 404 | 試算表或分頁不存在 |
| `Google::Apis::ClientError` status 403 | Service Account 無讀取權限 |
| `Google::Apis::RateLimitError` | 配額超過 |
| `Google::Apis::ServerError` | Google 伺服器端錯誤 |
| `StandardError` | 憑證載入失敗或其他未預期錯誤 |

---

### 修改：`Sheets::FetchProjectProgress` Actor

**檔案**：`app/actors/sheets/fetch_project_progress.rb`

移除 `simulate_error` 輸入、移除 `MockData` 依賴、移除 `error_mapping` 私有方法。`call` 方法改為呼叫 `SheetsApiClient.fetch_rows`，其餘私有方法（`normalize_record`、`normalize_date`、`validate_records!`、`group_by_project`）維持不變。

```ruby
# frozen_string_literal: true

module Sheets
  class FetchProjectProgress < ApplicationActor
    # 移除 input :simulate_error

    output :grouped_data
    output :failure_code
    output :message

    class ValidationError < StandardError; end

    COLUMN_KEYS = %i[
      project_name task_name status owner
      planned_completion_date actual_completion_date delay_days
    ].freeze

    def call
      rows = SheetsApiClient.fetch_rows
      records = parse_rows(rows)
      normalized = records.map { |record| normalize_record(record) }
      validate_records!(normalized)
      self.grouped_data = group_by_project(normalized)
    rescue ValidationError => e
      fail!(failure_code: :invalid_data_format, message: e.message)
    rescue Google::Apis::ClientError => e
      if e.status_code == 404 || e.message.to_s.include?("Unable to parse range")
        fail!(failure_code: :sheet_not_found, message: "找不到指定分頁或試算表：#{e.message}")
      elsif e.status_code == 403
        fail!(failure_code: :access_denied, message: "資料來源存取權限不足：#{e.message}")
      else
        fail!(failure_code: :internal_error, message: "Google Sheets API 錯誤：#{e.message}")
      end
    rescue => e
      fail!(failure_code: :internal_error, message: "未預期的內部錯誤：#{e.message}")
    end

    private

    # 將 API 回傳的列陣列（含標題列）轉換為任務 Hash 陣列
    def parse_rows(rows)
      return [] if rows.nil? || rows.empty?

      rows[1..].filter_map do |row|
        # 跳過空列（nil 或所有元素皆為空字串）
        next if row.nil? || row.all? { |cell| cell.to_s.strip.empty? }

        # 長度不足 7 時以 nil 填補
        padded = row + [nil] * [0, 7 - row.length].max
        values = padded[0, 7]

        # G 欄 delay_days：nil／空字串轉 nil，有效整數字串轉 Integer，否則保留原值
        delay_raw = values[6]
        delay_value =
          if delay_raw.nil? || delay_raw.to_s.strip.empty?
            nil
          else
            begin
              Integer(delay_raw, 10)
            rescue ArgumentError, TypeError
              delay_raw
            end
          end

        COLUMN_KEYS.zip(values[0, 6] + [delay_value]).to_h
      end
    end

    # 以下方法與雛型完全一致，不變動
    def normalize_record(record)
      record.merge(
        planned_completion_date: normalize_date(record[:planned_completion_date]),
        actual_completion_date:  normalize_date(record[:actual_completion_date])
      )
    end

    def normalize_date(date_str)
      return nil if date_str.nil? || date_str.to_s.empty?

      match = date_str.to_s.match(%r{\A(\d{4})[-/](\d{1,2})[-/](\d{1,2})\z})
      return date_str unless match

      year, month, day = match.captures
      "#{year}-#{month.rjust(2, '0')}-#{day.rjust(2, '0')}"
    end

    def validate_records!(records)
      records.each do |record|
        missing = %i[project_name task_name status owner].select { |k| record[k].to_s.strip.empty? }
        raise ValidationError, "缺少必要欄位：#{missing.join(', ')}" if missing.any?
      end
    end

    def group_by_project(records)
      records.group_by { |record| record[:project_name] }
    end
  end
end
```

**介面**：

| 項目 | 說明 |
|------|------|
| 輸入 | 無（移除 `simulate_error`） |
| 輸出（成功） | `grouped_data`：Hash，鍵為專案名稱，值為任務 Hash 陣列 |
| 輸出（失敗） | `failure_code`（Symbol）+ `message`（String） |

---

### 不變動：`Api::ProjectProgressController`

**檔案**：`app/controllers/api/project_progress_controller.rb`

與雛型完全一致，不變動。移除 `simulate_error` 的唯一需要動作在 Controller：不再讀取或傳遞 `params[:simulate_error]`。呼叫改為：

```ruby
result = Sheets::FetchProjectProgress.result()
```

其餘 success/failure 分支、`error_status` 方法均不變動。

---

### 不變動：`ProjectTaskBlueprint`

**檔案**：`app/blueprints/project_task_blueprint.rb`

與雛型完全一致，不變動。欄位定義維持 `project_name`、`task_name`、`status`、`owner`、`planned_completion_date`、`actual_completion_date`、`delay_days` 七個欄位。

---

### 不變動：其餘元件

- `DashboardController`：不變動
- View 層（`app/views/dashboard/`）：不變動
- 路由（`config/routes.rb`）：不變動

---

## Data Models

### 任務紀錄（Task Record）

每筆任務紀錄為 Ruby Hash，欄位如下：

| 欄位名稱 | 類型 | 說明 |
|----------|------|------|
| `project_name` | String | 專案名稱（分組用鍵值），對應 Google Sheets A 欄 |
| `task_name` | String | 任務名稱，對應 B 欄 |
| `status` | String | 狀態（待開始、進行中、已完成等），對應 C 欄 |
| `owner` | String | 負責人，對應 D 欄；多人時保留頓號分隔原字串 |
| `planned_completion_date` | String \| nil | 預計完成日期（正規化後為 ISO 8601），對應 E 欄 |
| `actual_completion_date` | String \| nil | 實際完成日期（正規化後為 ISO 8601），對應 F 欄 |
| `delay_days` | Integer \| String \| nil | 延誤天數，對應 G 欄；可為負數（提早完成） |

### Google Sheets 欄位對應

| 欄位 | 鍵值 | 說明 |
|------|------|------|
| A | `project_name` | 專案名稱 |
| B | `task_name` | 任務名稱 |
| C | `status` | 狀態 |
| D | `owner` | 負責人 |
| E | `planned_completion_date` | 預計完成日期（Sheets 回傳 `YYYY/MM/DD` 格式） |
| F | `actual_completion_date` | 實際完成日期（同上） |
| G | `delay_days` | 延誤天數（數字字串，可為負） |

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
    "message": "找不到指定分頁或試算表：..."
  }
}
```

### 日期正規化規則

`valueRenderOption: FORMATTED_VALUE` 下，Google Sheets 日期型別儲存格回傳 `YYYY/MM/DD` 格式；但試算表中也可能混有手動輸入的各種格式，`normalize_date` 統一處理。

| 輸入範例 | 輸出 |
|----------|------|
| `2026/7/22` | `2026-07-22` |
| `2026/07/22` | `2026-07-22` |
| `2026-7-5` | `2026-07-05` |
| `2026-07-05` | `2026-07-05` |
| `nil` / `""` | `null` |
| 無法解析值（如 `"TBD"`） | 原始字串不變 |

### `delay_days` 型別轉換規則

| 輸入值 | 輸出 |
|--------|------|
| `"5"` | `5`（Integer） |
| `"-4"` | `-4`（Integer） |
| `"0"` | `0`（Integer） |
| `nil` / `""` | `nil` |
| `"TBD"` / 非數字字串 | 原始字串不變 |

---

## Error Handling

### Actor 層錯誤處理

Actor 使用 `service_actor` 的 `fail!` 機制回傳結構化失敗結果：

| 觸發情境 | failure_code | HTTP 狀態 |
|----------|--------------|-----------|
| Google Sheets API 回傳 HTTP 404，或分頁名稱不存在（API 回傳 "Unable to parse range"） | `:sheet_not_found` | 404 |
| Google Sheets API 回傳 HTTP 403 | `:access_denied` | 403 |
| 任意紀錄的 `project_name`、`task_name`、`status` 或 `owner` 為空白 | `:invalid_data_format` | 422 |
| 憑證載入失敗、逾時、配額超過（`RateLimitError`）、其他未預期例外 | `:internal_error` | 500 |

**例外捕捉順序**（Actor `call` 方法）：

1. `ValidationError`（內部，`validate_records!` 拋出）→ `:invalid_data_format`
2. `Google::Apis::ClientError`（判斷 status_code 404/403）→ `:sheet_not_found` / `:access_denied`
3. `StandardError`（所有其他例外，含憑證錯誤、`ServerError`、`RateLimitError`）→ `:internal_error`

`Google::Apis::RateLimitError` 與 `Google::Apis::ServerError` 均繼承自 `StandardError`（非 `ClientError`），因此自然落入最後一個 `rescue` 分支。

### Controller 層錯誤處理

Controller 根據 `result.failure_code` 對應 HTTP 狀態碼，統一回傳：

```json
{ "error": { "code": "<failure_code>", "message": "<描述>" } }
```

| failure_code | HTTP 狀態 |
|---|---|
| `:sheet_not_found` | 404 |
| `:access_denied` | 403 |
| `:invalid_data_format` | 422 |
| `:internal_error` | 500 |

此對應邏輯與雛型完全一致，不變動。

### View 層錯誤處理

與雛型完全一致，不變動：`@error` 不為 nil 時，Dashboard 頁面在主內容區顯示錯誤訊息。

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

以下 Correctness Properties 針對 Actor 的**資料解析層**（純函式邏輯）設計。延續雛型階段的作法，不引入額外的 Property-Based Testing 套件，改以涵蓋邊界情況的具代表性多組範例（RSpec `context`/`it` 表格式測試）驗證每個 Property。Google Sheets API 呼叫本身（`SheetsApiClient`）以 mock 隔離，不納入這些測試範圍。

---

### Property 1: 空列跳過不影響有效資料數量

*For any* 列陣列（包含任意數量的空列與非空列），`parse_rows` 的輸出筆數必須等於輸入中非空列（排除標題列後）的數量，空列不得出現在輸出中。

**Validates: Requirements 2.2, 2.5**

---

### Property 2: 列長度不足時 nil 填補完整性

*For any* 長度介於 0 至 6 的列陣列，`parse_rows` 解析後每筆任務 Hash 必須包含全部 7 個鍵（`COLUMN_KEYS`），且不足的欄位值為 `nil`。

**Validates: Requirements 2.4**

---

### Property 3: 日期欄位格式一致性

*For any* 符合 `YYYY/M/D`、`YYYY/MM/DD`、`YYYY-M-D`、`YYYY-MM-DD` 四種格式之一的日期字串，`normalize_date` 的輸出必須符合正規表達式 `/\A\d{4}-\d{2}-\d{2}\z/`。

**Validates: Requirements 3.1**

---

### Property 4: nil 與空字串日期保留為 nil

*For any* `nil` 值或全空白字串，`normalize_date` 的輸出必定為 `nil`。

**Validates: Requirements 3.2**

---

### Property 5: 無法解析的日期保留原始值

*For any* 不符合支援格式的非空字串（如 `"TBD"`、`"未定"`、`"2026.07.31"`），`normalize_date` 的輸出必須等於輸入值，不拋出例外。

**Validates: Requirements 3.3**

---

### Property 6: `delay_days` 有效整數字串轉型

*For any* 有效整數字串（包含負數，如 `"-4"`、`"0"`、`"100"`），`parse_rows` 解析後該筆記錄的 `delay_days` 欄位值必須為 Integer 型別，且數值相等。

**Validates: Requirements 3.4**

---

### Property 7: 分組完整性（資料不遺失）

*For any* 非空的任務 Hash 陣列，`group_by_project` 輸出的所有陣列元素總數必須等於輸入筆數，無資料遺失。

**Validates: Requirements 8.1, 8.2**

---

### Property 8: 分組鍵值完整性

*For any* 非空的任務 Hash 陣列，`group_by_project` 輸出的鍵值集合必須與輸入中 `project_name` 的唯一值集合完全相同，不多不少。

**Validates: Requirements 8.1**

---

### Property 9: 錯誤回應格式一致性

*For any* 觸發 Actor 失敗的情境（透過 mock `SheetsApiClient` 拋出各類例外），API 回應的 JSON body 必須包含 `error.code` 與 `error.message` 兩個鍵，缺一不可。

**Validates: Requirements 4.1, 4.2, 4.3, 4.4, 4.5**

---

### Property 10: Blueprint 欄位完整性

*For any* 任務 Hash，`ProjectTaskBlueprint.render_as_hash` 的輸出必須恰好包含 `project_name`、`task_name`、`status`、`owner`、`planned_completion_date`、`actual_completion_date`、`delay_days` 這 7 個鍵，不多不少。

**Validates: Requirements 6.1, 7.3**

---

## Testing Strategy

### 技術選型

不引入額外的 Property-Based Testing 套件，沿用雛型階段（`warroom-data-api-prototype`）已驗證過的作法：每個 Property 用一組涵蓋邊界情況的具代表性範例（`context`/`it` 搭配陣列迭代）驗證，不使用 `rspec-rantly`／`propcheck` 等隨機生成工具，維持與既有測試風格一致、不新增依賴。

### 單元測試（RSpec）

**`SheetsApiClient`**：
- 憑證優先從 Rails credentials 讀取（stub `Rails.application.credentials`）
- Rails credentials 不存在時 fallback 至環境變數 `GOOGLE_SHEETS_CREDENTIALS_JSON`
- 兩者均不存在時拋出含明確中文描述的 `StandardError`
- `fetch_rows` 正常回傳列陣列
- `fetch_rows` 在 `Google::Apis::ClientError`（403/404）時重新拋出

**`Sheets::FetchProjectProgress` Actor**（stub `SheetsApiClient.fetch_rows`）：
- 正常資料 → 驗證 `grouped_data` 結構與分組正確性
- 包含空列 → 驗證空列被跳過
- 列長度不足 7 → 驗證 nil 填補後仍產生完整 Hash
- 日期格式各種組合（四種支援格式）→ 驗證 `normalize_date` 輸出
- 空值日期 → 驗證輸出為 `nil`
- 負數 `delay_days`（如 `"-4"`）→ 驗證轉為 `-4`（Integer）
- 非數字 `delay_days`（如 `"TBD"`）→ 驗證保留原始字串
- `project_name`、`task_name`、`status` 或 `owner` 任一欄為空白 → 驗證回傳 `failure_code: :invalid_data_format`
- `SheetsApiClient` 拋出 `ClientError` 404 → 驗證 `failure_code: :sheet_not_found`
- `SheetsApiClient` 拋出 `ClientError` 403 → 驗證 `failure_code: :access_denied`
- `SheetsApiClient` 拋出 `StandardError`（憑證錯誤）→ 驗證 `failure_code: :internal_error`
- `SheetsApiClient` 拋出 `RateLimitError` → 驗證 `failure_code: :internal_error`
- 傳入 `simulate_error` query parameter → 驗證被忽略，不產生效果

**`ProjectTaskBlueprint`**：
- `render_as_hash` 輸出恰好包含 7 個欄位

### Property 測試（具代表性範例，非隨機生成）

每個 Property 對應一組 RSpec `context`，內含涵蓋邊界情況的具代表性範例（例如 Property 3 涵蓋四種支援日期格式各一組範例、Property 6 涵蓋正數／負數／零的整數字串），比照雛型階段 `fetch_project_progress_spec.rb` 的寫法：

- Property 1：空列跳過不影響有效資料數量
- Property 2：列長度不足時 nil 填補完整性
- Property 3：日期欄位格式一致性
- Property 4：nil 與空字串日期保留為 nil
- Property 5：無法解析的日期保留原始值
- Property 6：`delay_days` 有效整數字串轉型（含空字串 → `nil`）
- Property 7：分組完整性（資料不遺失）
- Property 8：分組鍵值完整性
- Property 9：錯誤回應格式一致性
- Property 10：Blueprint 欄位完整性

Properties 3–6 純函式，直接測試 `normalize_date` 與 `parse_rows` 私有方法（透過 `send` 或提取為模組）。Properties 7–8 測試 `group_by_project`。Property 9 透過 mock `SheetsApiClient` 測試 Actor + Controller 整合。

### 整合測試（Request Spec，stub `SheetsApiClient.fetch_rows`）

- `GET /api/project_progress` → 200 回傳符合格式的 JSON（欄位齊全、日期 ISO 8601）
- `GET /api/project_progress` 當 `SheetsApiClient` 拋出 `ClientError` 404 → 404 及統一錯誤格式
- `GET /api/project_progress` 當 `SheetsApiClient` 拋出 `ClientError` 403 → 403 及統一錯誤格式
- `GET /api/project_progress` 當資料含空白 `project_name` → 422 及統一錯誤格式
- `GET /api/project_progress` 當 `SheetsApiClient` 拋出 `StandardError` → 500 及統一錯誤格式
- `GET /api/project_progress?simulate_error=sheet_not_found` → 正常回傳（該參數被忽略）
- `GET /dashboard` → 200 回傳 HTML，包含下拉選單與專案區塊
- `GET /dashboard?project=<專案名稱>` → Turbo Frame 局部更新，`@display_data` 只含該專案

### 端對端驗證

- 手動訪問 `/dashboard`，確認頁面呈現真實 Google Sheets 資料
- 切換下拉選單，確認 Turbo Frame 局部更新（不整頁重載）
- `curl http://localhost:3000/api/project_progress`，驗證 JSON 結構與雛型格式一致
- 暫時移除 Rails credentials 與環境變數，訪問 `/api/project_progress`，確認回傳 500 並含明確錯誤訊息
