# 設計文件

## Overview

在 `warroom-data-api-prototype` Rails 專案中新增一組獨立於 305 資料流的 306 資料流，遵循
[rails-standards.md](../../steering/rails-standards.md) 的 Controller → Actor → Client → Blueprint
分層。新增檔案不修改既有 305 的任何檔案（`SheetsApiClient`、`Sheets::FetchProjectProgress`、
`ProjectTaskBlueprint`、`DashboardController` 皆維持不動），兩條資料流平行存在、互不影響。

畫面呈現方式直接對齊已由使用者確認過的 `docs/issues.html` prototype：KPI 卡片＋月份選擇、每日趨勢
SVG 折線圖、議題明細清單（可篩選）、工程師負載表、專案清單表。渲染邏輯從 prototype 的純前端 JS
(`docs/js/issues.js`) 移植為 Rails ERB + Turbo Frame（篩選由伺服器端處理，而非前端 JS 過濾），
視覺／CSS 由 Rails 端的 `application.css`（已有主題變數系統，見 06f9e41 深色／淺色主題切換）承接。

---

## Architecture

```
warroom-data-api-prototype/
├── app/
│   ├── clients/
│   │   ├── sheets_api_client.rb          ← 既有，305 用，不動
│   │   └── issue_sheets_client.rb        ← 新增，306 用
│   ├── actors/sheets/
│   │   ├── fetch_project_progress.rb     ← 既有，不動
│   │   └── fetch_issue_dashboard.rb      ← 新增
│   ├── blueprints/
│   │   ├── project_task_blueprint.rb     ← 既有，不動
│   │   ├── month_kpi_blueprint.rb        ← 新增
│   │   ├── daily_kpi_blueprint.rb        ← 新增
│   │   ├── issue_blueprint.rb            ← 新增
│   │   ├── engineer_load_blueprint.rb    ← 新增
│   │   └── project_list_blueprint.rb     ← 新增
│   ├── controllers/
│   │   ├── dashboard_controller.rb       ← 既有，不動
│   │   ├── issues_controller.rb          ← 新增（GET /issues，HTML）
│   │   └── api/
│   │       ├── project_progress_controller.rb  ← 既有，不動
│   │       └── issue_dashboard_controller.rb    ← 新增（GET /api/issue_dashboard，JSON）
│   └── views/issues/
│       ├── index.html.erb                ← 新增（頁面骨架 + 5 個區塊）
│       └── _issue_list.html.erb          ← 新增（Turbo Frame 局部：議題明細清單，供篩選局部更新）
└── config/routes.rb                      ← 新增路由
```

---

## Components and Interfaces

### `IssueSheetsClient`（`app/clients/issue_sheets_client.rb`）

```ruby
class IssueSheetsClient
  SPREADSHEET_ID = "1RdU2p9b7fwNgO5e59jN-00a5KLOQ91xrFhj2NenyKTc"

  # 分頁名稱依需求 1 確認結果調整；raw_2023~raw_2026／工程師負載表／專案清單表為推測值。
  MONTH_KPI_SHEET    = "month_kpi"
  DAILY_KPI_SHEET    = "daily_kpi"
  ISSUE_SHEETS       = %w[raw_2023 raw_2024 raw_2025 raw_2026].freeze
  ENGINEER_LOAD_SHEET = "工程師負載"   # TODO: 需求 1 確認實際分頁名稱
  PROJECT_LIST_SHEET  = "專案清單"     # TODO: 需求 1 確認實際分頁名稱

  SCOPES = ["https://www.googleapis.com/auth/spreadsheets.readonly"].freeze

  def self.fetch_month_kpi_rows = new.fetch_rows(MONTH_KPI_SHEET, "A:J")
  def self.fetch_daily_kpi_rows = new.fetch_rows(DAILY_KPI_SHEET, "A:E")
  def self.fetch_issue_rows
    new.fetch_and_merge_rows(ISSUE_SHEETS, "A:K")
  end
  def self.fetch_engineer_load_rows = new.fetch_rows(ENGINEER_LOAD_SHEET, "A:H")
  def self.fetch_project_list_rows = new.fetch_rows(PROJECT_LIST_SHEET, "A:G")

  def fetch_rows(sheet_name, range_suffix)
    response = build_service.get_spreadsheet_values(
      SPREADSHEET_ID, "#{sheet_name}!#{range_suffix}",
      value_render_option: "FORMATTED_VALUE"
    )
    (response.values || []).map { |row| retag_utf8(row) }
  end

  def fetch_and_merge_rows(sheet_names, range_suffix)
    combined = []
    sheet_names.each_with_index do |sheet_name, index|
      rows = fetch_rows(sheet_name, range_suffix)
      combined.concat(index.zero? ? rows : rows.drop(1))
    end
    combined
  end

  # build_service / credentials / retag_utf8：與既有 SheetsApiClient 相同實作，
  # 依 rails-standards.md 慣例（可抽共用 module，或維持獨立實作，視實作階段決定）。
end
```

- 與 305 的 `SheetsApiClient` 是否要抽出共用的憑證/UTF-8 重標記邏輯（例如
  `Concerns::GoogleSheetsAuthenticatable` module），留待實作階段依 karpathy-guidelines 判斷：
  若抽象化能明顯減少重複且不增加理解成本才做，否則維持兩份獨立小型實作（各自僅 ~80 行，重複尚可
  接受，避免過早抽象）。
- `IssueSheetsClient` 與 `SheetsApiClient` 分屬不同試算表 ID，刻意不合併為同一類別（見詞彙表）。

### `Sheets::FetchIssueDashboard`（`app/actors/sheets/fetch_issue_dashboard.rb`）

```ruby
module Sheets
  class FetchIssueDashboard < ApplicationActor
    output :month_kpi
    output :daily_kpi
    output :issues
    output :project_breakdown
    output :engineer_load
    output :project_list
    output :failure_code
    output :message

    def call
      self.month_kpi          = parse_month_kpi(IssueSheetsClient.fetch_month_kpi_rows)
      self.daily_kpi           = parse_daily_kpi(IssueSheetsClient.fetch_daily_kpi_rows)
      self.issues               = parse_issues(IssueSheetsClient.fetch_issue_rows)
      self.project_breakdown  = compute_project_breakdown(issues)
      self.engineer_load       = parse_engineer_load(IssueSheetsClient.fetch_engineer_load_rows)
      self.project_list         = parse_project_list(IssueSheetsClient.fetch_project_list_rows)
    rescue Google::Apis::ClientError => e
      # 錯誤對應邏輯與既有 Sheets::FetchProjectProgress 相同（見 rails-standards.md）
      handle_client_error(e)
    rescue => e
      fail!(failure_code: :internal_error, message: "未預期的內部錯誤：#{e.message}")
    end

    private

    # parse_month_kpi：欄位對應 year_month/complaint/testing/total_bug/block_rate/
    #   completed/unresolved/avg_days/sla_rate；不解析 Top3 欄位（需求 3.3——負責人不作為統計主軸）。
    #
    # parse_daily_kpi：欄位對應 date/complaint/testing/other/total；total 空字串視為 0；
    #   結果依 date 升冪排序。
    #
    # parse_issues：欄位對應 issue_id/subject/type/tracker/status/assigned_to/start_date/
    #   due_date/work_days/project（跳過 sheet_name 欄，該欄僅為來源標記不需輸出）；
    #   start_date/due_date 呼叫既有 normalize_date；work_days 嘗試轉 Integer 失敗則保留原值；
    #   issue_id/subject/status 任一為空白則跳過該列。
    #
    # compute_project_breakdown(issues)：與 prototype 的 computeProjectBreakdown 邏輯一致，依
    #   project 分組統計 complaint/testing/other 筆數與 total（需求 3a）；純記憶體運算，不再次
    #   呼叫 IssueSheetsClient。
    #
    # parse_engineer_load：欄位對應 name/project/allocation_pct/effective_month/expire_month/
    #   (跳過空白欄) /total_pct；全欄空白列跳過。
    #
    # parse_project_list：欄位對應 name/abbr/status/allocation_pct/effective_month/
    #   expire_month/owner_rd。
  end
end
```

### Blueprints

各 Blueprint 僅定義欄位清單（Blueprinter 慣例），例如：

```ruby
class MonthKpiBlueprint < Blueprinter::Base
  identifier :year_month
  fields :complaint, :testing, :total_bug, :block_rate, :completed,
         :unresolved, :avg_days, :sla_rate
end

class IssueBlueprint < Blueprinter::Base
  identifier :issue_id
  fields :subject, :type, :tracker, :status, :assigned_to,
         :start_date, :due_date, :work_days, :project

  # 「歸屬類型」不是 Actor 輸出欄位，而是 View 依 type 動態計算的顯示邏輯（需求 5.6），
  # 故不在此 Blueprint 中定義；View helper（例如 IssuesHelper#attribution_label(type)）
  # 直接複用 prototype 的 attributionLabel(type) 對應規則。
end

class ProjectBreakdownBlueprint < Blueprinter::Base
  identifier :project
  fields :complaint, :testing, :other, :total
end
```

（`DailyKpiBlueprint`／`EngineerLoadBlueprint`／`ProjectListBlueprint` 比照辦理，欄位對應需求 4/6。）

### Controllers ／ Routes

```ruby
# config/routes.rb 新增：
get "/issues", to: "issues#index"
namespace :api do
  get "issue_dashboard", to: "issue_dashboard#index"
end
```

```ruby
class IssuesController < ApplicationController
  def index
    result = Sheets::FetchIssueDashboard.result
    return render_error(result) unless result.success?

    @month_kpi     = result.month_kpi
    @daily_kpi     = result.daily_kpi
    @engineer_load = result.engineer_load
    @project_list  = result.project_list
    @selected_month = params[:month].presence || @month_kpi.map { |m| m[:year_month] }.max

    @filtered_issues = filter_issues(result.issues, params[:project], params[:status])
  end

  private

  def filter_issues(issues, project, status)
    issues
      .select { |i| project.blank? || i[:project] == project }
      .select { |i| status.blank? || i[:status] == status }
  end
end
```

- 篩選邏輯（`project`／`status` query params）在 Controller 完成，Actor 僅負責讀取＋正規化全量資料，
  與 305 的 `warroom-dashboard-ux-enhancements` 需求 10（Controller 層篩選）慣例一致。
- 月份切換／議題篩選皆透過 Turbo Frame 局部更新對應區塊（`turbo_frame_tag "kpi-cards"`、
  `turbo_frame_tag "issue-list"`），沿用既有 `dashboard/index.html.erb` 的 Turbo Frame 模式。

### View 結構（`app/views/issues/index.html.erb`）

比照 `docs/issues.html` 的五個區塊（月度 KPI／每日趨勢／議題明細／工程師負載／專案清單），差異：
- 月份選單、專案／狀態篩選改為 `<select>` + `form_with` 觸發 GET 請求（Turbo Frame 局部更新），
  取代 prototype 的純前端 JS 事件監聽。
- 每日趨勢圖：手刻 SVG 邏輯可直接搬移自 `docs/js/issues.js` 的 `renderTrendChart`，但改為 ERB 迴圈於
  伺服器端輸出 `<svg>`（避免額外引入前端框架，符合 rails-standards 的最簡方案原則），或維持極輕量的
  内嵌 `<script>` 於頁面載入後渲染（兩種皆可，實作階段依複雜度決定；SVG 資料點數量少，伺服器端 ERB
  產生較單純、不需額外 JS 檔案）。
- 依專案分類統計：直接以 `<table>` 渲染 `@project_breakdown`（`ProjectBreakdownBlueprint` 序列化），
  取代 prototype 已移除的 Top3 排行；不隨月份切換更新（見需求 3a.2）。
- 議題明細清單「歸屬類型」欄位：View helper（`IssuesHelper#attribution_label(type)` /
  `#attribution_class(type)`）依 `type` 回傳徽章文字與 CSS class，邏輯與 prototype 的
  `attributionLabel`／`attributionClass` 一致，渲染為 `<span class="attribution-badge ...">`。

---

## Data Models

| 資料集 | 欄位 |
|---|---|
| `month_kpi` | `year_month, complaint, testing, total_bug, block_rate, completed, unresolved, avg_days, sla_rate` |
| `daily_kpi` | `date, complaint, testing, other, total` |
| `issues` | `issue_id, subject, type, tracker, status, assigned_to, start_date, due_date, work_days, project` |
| `project_breakdown` | `project, complaint, testing, other, total`（由 `issues` 衍生計算，非直接讀取自試算表） |
| `engineer_load` | `name, project, allocation_pct, effective_month, expire_month, total_pct` |
| `project_list` | `name, abbr, status, allocation_pct, effective_month, expire_month, owner_rd` |

與 prototype 的模擬資料常數（`MONTH_KPI`／`DAILY_KPI`／`ISSUES`／`ENGINEER_LOAD`／`PROJECT_LIST`，
見 [warroom-issue-dashboard-static-prototype/design.md](../warroom-issue-dashboard-static-prototype/design.md)）
欄位一一對應（`MONTH_KPI` 已移除 `top3`），確保畫面呈現邏輯可直接沿用。

---

## Error Handling

沿用 [rails-standards.md](../../steering/rails-standards.md) 統一錯誤格式與 `failure_code` 對應表。
五個讀取類別（`project_breakdown` 為衍生計算，不另外呼叫 API，故不計入）中任一讀取失敗即整體失敗
（需求 7.2），`IssuesController` 於失敗時渲染錯誤訊息（比照既有 `DashboardController` 的頁面層級
錯誤顯示）。

---

## Testing Strategy

- **單元測試**（RSpec，比照既有 `spec/clients/`、`spec/actors/` 慣例）：
  - `IssueSheetsClient`：stub `Google::Apis::SheetsV4::SheetsService`，驗證分頁名稱／range 正確、
    UTF-8 重標記、合併邏輯（`raw_2023`〜`raw_2026`）僅保留第一個分頁標題列。
  - `Sheets::FetchIssueDashboard`：驗證五類資料解析正確（含 `project_breakdown` 分組統計、日期正規化、空列跳過、
    整數轉換失敗容錯）、錯誤對應（404/403/其他）。
- **Request specs**：`GET /api/issue_dashboard` 回傳結構符合需求 8.3；`GET /issues` 帶
  `project`／`status`／`month` query params 時回傳正確篩選結果。
- **端對端驗證**（比照 `warroom-data-api-real-source` Task 10 的驗證方式）：設定真實 Service Account
  憑證後，訪問 `/issues` 確認畫面呈現與 `docs/issues.html` prototype 一致，且資料為真實試算表內容
  （非模擬資料）。
