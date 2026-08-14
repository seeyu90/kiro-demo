# 設計文件

## 概述

在 `warroom-data-api-prototype` Rails 專案中新增一組獨立於 305 資料流的 306 資料流，遵循
[rails-standards.md](../../steering/rails-standards.md) 的 Controller → Actor → Client → Blueprint
分層。新增檔案不修改既有 305 的任何檔案（`SheetsApiClient`、`Sheets::FetchProjectProgress`、
`ProjectTaskBlueprint`、`DashboardController` 皆維持不動），兩條資料流平行存在、互不影響。

畫面呈現方式直接對齊已由使用者確認過的 `docs/issues.html` prototype：KPI 卡片＋月份選擇、依專案分類
統計、每日趨勢 SVG 折線圖、議題明細清單（可篩選，含歸屬類型徽章與議題編號 Redmine 連結）。工程師
負載表／專案清單表經評估後不納入本 spec 範圍（見 requirements.md）。渲染邏輯從 prototype 的純前端 JS
(`docs/js/issues.js`) 移植為 Rails ERB + Turbo Frame（篩選由伺服器端處理，而非前端 JS 過濾），
視覺／CSS 由 Rails 端的 `application.css`（已有主題變數系統，見 06f9e41 深色／淺色主題切換）承接。

---

## 架構

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
│   │   └── project_breakdown_blueprint.rb ← 新增
│   ├── controllers/
│   │   ├── dashboard_controller.rb       ← 既有，不動
│   │   ├── issues_controller.rb          ← 新增（GET /issues，HTML）
│   │   ├── home_controller.rb            ← 新增（GET /，入口頁，需求 10）
│   │   └── api/
│   │       ├── project_progress_controller.rb  ← 既有，不動
│   │       └── issue_dashboard_controller.rb    ← 新增（GET /api/issue_dashboard，JSON）
│   ├── helpers/
│   │   └── issues_helper.rb              ← 新增（attribution_label／attribution_class）
│   └── views/
│       ├── home/
│       │   └── index.html.erb            ← 新增（入口頁，兩張卡片連結，需求 10）
│       └── issues/
│           ├── index.html.erb            ← 新增（頁面骨架 + 3 個區塊）
│           └── _issue_list.html.erb      ← 新增（Turbo Frame 局部：議題明細清單，供篩選局部更新）
└── config/routes.rb                      ← 修改（root 改指向 home#index，需求 10.1）
```

---

## 元件與介面

### `IssueSheetsClient`（`app/clients/issue_sheets_client.rb`）

```ruby
class IssueSheetsClient
  SPREADSHEET_ID = "1RdU2p9b7fwNgO5e59jN-00a5KLOQ91xrFhj2NenyKTc"

  # 分頁名稱已依需求 1（Task 1）確認，取自試算表 xl/workbook.xml 的官方分頁清單。
  # raw_2023~raw_2025、raw_2027 為隱藏分頁（不影響 API 讀取）；raw_2027 目前僅有標題列、無資料列。
  MONTH_KPI_SHEET    = "month_kpi"
  DAILY_KPI_SHEET    = "daily_kpi"
  ISSUE_SHEETS       = %w[raw_2023 raw_2024 raw_2025 raw_2026 raw_2027].freeze

  SCOPES = ["https://www.googleapis.com/auth/spreadsheets.readonly"].freeze

  def self.fetch_month_kpi_rows = new.fetch_rows(MONTH_KPI_SHEET, "A:J")
  def self.fetch_daily_kpi_rows = new.fetch_rows(DAILY_KPI_SHEET, "A:E")
  def self.fetch_issue_rows
    new.fetch_and_merge_rows(ISSUE_SHEETS, "A:K")
  end

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
    output :failure_code
    output :message

    def call
      self.month_kpi          = parse_month_kpi(IssueSheetsClient.fetch_month_kpi_rows)
      self.daily_kpi           = parse_daily_kpi(IssueSheetsClient.fetch_daily_kpi_rows)
      self.issues               = parse_issues(IssueSheetsClient.fetch_issue_rows)
      self.project_breakdown  = compute_project_breakdown(issues)
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
    #   issue_id/subject/status 任一為空白則跳過該列；tracker 為「測試」的列亦整批跳過（需求 5a），
    #   不納入 issues 輸出（連帶不納入衍生的 project_breakdown），對齊 prototype 需求 4.6。
    #
    # compute_project_breakdown(issues)：與 prototype 的 computeProjectBreakdown 邏輯一致，依
    #   project 分組統計 complaint/testing/other 筆數與 total（需求 3a）；純記憶體運算，不再次
    #   呼叫 IssueSheetsClient。
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

  # Blueprint 仍輸出 type/tracker 原始欄位（Actor 輸出介面不因顯示層需求而刪減，見需求 5.2）；
  # View 只是「不顯示」這兩欄，欄位本身仍可供未來其他用途使用。
  # 「歸屬類型」與「議題編號連結」皆非 Actor 輸出欄位，而是 View 依 type/issue_id 動態計算的顯示邏輯
  # （需求 5.6、5.7、5.8），故不在此 Blueprint 中定義；View helper（IssuesHelper#attribution_label(type)
  # / #attribution_class(type)）直接複用 prototype 的 attributionLabel(type) 對應規則，「議題編號」
  # 連結由 View 直接組字串（`"https://redmine.amastek.com.tw/issues/#{issue.issue_id}"`）。
end

class ProjectBreakdownBlueprint < Blueprinter::Base
  identifier :project
  fields :complaint, :testing, :other, :total
end
```

（`DailyKpiBlueprint` 比照辦理，欄位對應需求 4。）

### 控制器／路由

```ruby
# config/routes.rb 修改：
root "home#index"                    # 原為 root "dashboard#index"（需求 10.1）
get "/dashboard", to: "dashboard#index"  # 305 頁面路由不變，仍可直接訪問
get "/issues", to: "issues#index"
namespace :api do
  get "issue_dashboard", to: "issue_dashboard#index"
end
```

```ruby
class HomeController < ApplicationController
  def index; end  # 純靜態連結頁面，不讀取任何資料來源（需求 10.3）
end
```

`app/views/home/index.html.erb` 比照 `docs/index.html` 的入口頁結構（`.entry-grid` /
`.entry-card` 兩張卡片，分別連到 `/dashboard`、`/issues`），沿用既有 `application.css` 主題變數
系統（需求 10.4）。

```ruby
class IssuesController < ApplicationController
  DEFAULT_STATUS = "新建立".freeze
  TABS = %w[stats detail].freeze
  DEFAULT_TAB = "stats".freeze
  BREAKDOWN_SORT_KEYS = %w[complaint testing other total].freeze
  BREAKDOWN_SORT_DIRS = %w[asc desc].freeze
  DEFAULT_BREAKDOWN_SORT_DIR = "desc".freeze

  def index
    result = Sheets::FetchIssueDashboard.result
    if result.success?
      build_success(result)
    else
      build_failure(result.message)
    end
  end

  private

  def build_success(result)
    # 兩個分頁籤（統計摘要／議題資料）各自獨立表單，各帶隱藏欄位 tab= 標明來源，
    # 送出後仍停留在原本的分頁籤，而非固定跳回預設分頁籤（需求 7a.4）。
    @active_tab = TABS.include?(params[:tab]) ? params[:tab] : DEFAULT_TAB

    @month_kpi = MonthKpiBlueprint.render_as_hash(result.month_kpi)
    all_daily_kpi = DailyKpiBlueprint.render_as_hash(result.daily_kpi)

    current_year_month = Date.current.strftime("%Y-%m")
    @available_months = (@month_kpi.map { |m| m[:year_month] } + [current_year_month]).uniq.sort
    @selected_month = params[:month].presence || @month_kpi.map { |m| m[:year_month] }.max
    @selected_month_record = @month_kpi.find { |m| m[:year_month] == @selected_month }
    @selected_month_pending = @selected_month_record.nil? && @selected_month == current_year_month

    all_issues = IssueBlueprint.render_as_hash(result.issues)

    # 每日趨勢與依專案分類統計皆依所選月份篩選後才渲染（需求 3a.4、4.5）；
    # Actor／API 層的 project_breakdown／daily_kpi 輸出本身仍為全量、不受此篩選影響。
    @daily_kpi = all_daily_kpi.select { |d| same_month?(d[:date], @selected_month) }
    month_issues = all_issues.select { |i| same_month?(i[:start_date], @selected_month) }

    # 排序欄位／方向皆為選填 query params；未帶或帶入非法值時維持原始（依專案分組）順序（需求 3a.5）。
    @breakdown_sort = params[:breakdown_sort] if BREAKDOWN_SORT_KEYS.include?(params[:breakdown_sort])
    @breakdown_dir =
      BREAKDOWN_SORT_DIRS.include?(params[:breakdown_dir]) ? params[:breakdown_dir] : DEFAULT_BREAKDOWN_SORT_DIR
    @project_breakdown = sort_project_breakdown(compute_project_breakdown(month_issues))

    @projects = all_issues.map { |i| i[:project] }.compact.uniq
    @statuses = all_issues.map { |i| i[:status] }.compact.uniq
    @selected_project = params[:project].presence
    # 未帶 status 參數（首次載入）時預設「新建立」；使用者主動清空（status= 空字串）則視為不篩選。
    @selected_status = params.key?(:status) ? params[:status] : DEFAULT_STATUS

    @issues = filter_issues(all_issues)
    @error = nil
  end

  def build_failure(message)
    @active_tab = DEFAULT_TAB
    @month_kpi = @daily_kpi = @project_breakdown = @available_months = @projects = @statuses = @issues = []
    @breakdown_sort = nil
    @breakdown_dir = DEFAULT_BREAKDOWN_SORT_DIR
    @selected_month = @selected_month_record = @selected_project = nil
    @selected_month_pending = false
    @selected_status = DEFAULT_STATUS
    @error = message
  end

  def filter_issues(issues)
    issues
      .select { |i| @selected_project.blank? || i[:project] == @selected_project }
      .select { |i| @selected_status.blank? || i[:status] == @selected_status }
  end

  def same_month?(date_str, year_month)
    date_str.is_a?(String) && date_str[0, 7] == year_month
  end

  # 與 Sheets::FetchIssueDashboard#compute_project_breakdown 邏輯相同，但這裡對「已依月份篩選的
  # 議題子集」運算（Actor 版本對全量議題運算，供 API 使用），兩者用途不同，故不共用（需求 3a.4）。
  def compute_project_breakdown(issues)
    grouped = issues.each_with_object({}) do |issue, acc|
      key = issue[:project].to_s.strip.empty? ? "未分類" : issue[:project]
      acc[key] ||= { project: key, complaint: 0, testing: 0, other: 0 }
      case issue[:type]
      when "Complaint" then acc[key][:complaint] += 1
      when "TestingBug" then acc[key][:testing] += 1
      else acc[key][:other] += 1
      end
    end
    grouped.values.map { |row| row.merge(total: row[:complaint] + row[:testing] + row[:other]) }
  end

  # @breakdown_sort 為 nil 時維持原始（依專案分組）順序，不排序（需求 3a.5）。
  def sort_project_breakdown(rows)
    return rows if @breakdown_sort.nil?

    sorted = rows.sort_by { |row| row[@breakdown_sort.to_sym] }
    @breakdown_dir == "desc" ? sorted.reverse : sorted
  end
end
```

（**設計變更紀錄**：`@project_breakdown` 原直接使用 `ProjectBreakdownBlueprint.render_as_hash(result.project_breakdown)`（Actor 輸出的全量統計，不受月份篩選）；使用者回饋「依專案分類統計也應依所選
月份呈現」後，改為 Controller 對月份篩選過的 `issues` 子集重新計算（`compute_project_breakdown`），
不再直接使用 `ProjectBreakdownBlueprint` 渲染 Actor 的 `project_breakdown` 輸出於 HTML 頁面；
`GET /api/issue_dashboard` JSON 端點的 `project_breakdown` 欄位維持使用 Actor 版本（全量、不受月份
篩選），行為不變，見需求 3a.4。）

- 篩選邏輯（`project`／`status`／`month` query params）在 Controller 完成，Actor 僅負責讀取＋正規化
  全量資料，與 305 的 `warroom-dashboard-ux-enhancements` 需求 10（Controller 層篩選）慣例一致。
- 錯誤處理比照既有 `DashboardController` 的 `build_success`／`build_failure` 模式：HTTP 一律 200，
  失敗時 `@error` 於頁面內顯示，不同於 JSON API 走 HTTP 狀態碼分流。
- 月份切換／議題篩選皆透過**單一** `turbo_frame_tag "issue-content"` 局部更新整個動態內容區塊，
  沿用既有 `dashboard/index.html.erb`「單一 frame + 表單按鈕送出」的模式；但**表單本身拆分為兩個**
  （見需求 7a.2），各自置於對應分頁籤內、各帶隱藏欄位 `tab=stats` / `tab=detail`，Controller 依此
  決定 `@active_tab`，View 據此決定哪個 radio 帶 `checked`，確保局部更新後仍停留在使用者原本所在
  的分頁籤（見需求 7a.4）。

### View 結構（`app/views/issues/index.html.erb`）

比照 `docs/issues.html`（見 [warroom-issue-dashboard-static-prototype/design.md](../warroom-issue-dashboard-static-prototype/design.md) 的分頁籤結構段落）以純 CSS radio+label 分頁籤呈現四個區塊，
分為「統計摘要」（月度 KPI＋每日趨勢＋依專案分類統計）與「議題資料」（僅議題明細）兩個分頁籤，差異：
- 月份選單、專案／狀態篩選改為 `<select>` + `form_with` 觸發 GET 請求（Turbo Frame 局部更新），
  取代 prototype 的純前端 JS 事件監聽；兩個分頁籤各自的表單獨立送出，互不影響對方目前的篩選值。
- 每日趨勢圖：手刻 SVG 邏輯移植自 `docs/js/issues.js` 的 `renderTrendChart`，改為伺服器端
  `IssuesHelper`（`trend_chart_points`／`trend_chart_polyline`／`trend_chart_y_ticks`／
  `trend_chart_x_labels`）計算座標，ERB 迴圈輸出 `<svg>`（不引入前端框架，符合 rails-standards 的
  最簡方案原則）。含縱軸 0／中間值／最大值三條格線與數字標籤；橫軸為每一個資料點顯示日期標籤
  （不省略、不限制數量），並以 `transform="rotate(-45 x y)"` + `text-anchor="end"` 旋轉呈現，避免
  密集資料點時標籤重疊——與 `docs/js/issues.js` 的座標與旋轉邏輯完全一致（需求 4.6）。
  （**設計變更紀錄**：`trend_chart_x_labels` 原本在資料點數量超過 `TREND_MAX_X_LABELS`（6 個）時
  等距挑選含首尾的標籤索引；使用者回饋希望每個資料點都能看到日期，故改為回傳全部標籤並以旋轉方式
  避免重疊，`TREND_MAX_X_LABELS` 常數與 `trend_chart_label_indices` 已移除，`TREND_HEIGHT`
  220→250、`TREND_PADDING_BOTTOM` 28→55 以容納旋轉後的斜向文字。）
  傳入 `@daily_kpi` 為 Controller 已依所選月份篩選過的子集（見需求 4.5）；WHEN 篩選後為空陣列，
  顯示「所選月份無每日趨勢資料」。
- 依專案分類統計：以 `<table>` 渲染 `@project_breakdown`，取代 prototype 已移除的 Top3 排行；
  `@project_breakdown` 為 Controller 依所選月份篩選過的議題子集重新計算的結果（見上方 Controller
  程式碼區塊的設計變更紀錄與需求 3a.4），隨月份切換更新；WHEN 篩選後為空陣列，顯示
  「所選月份無議題資料」。
  - 客訴／測試／其他／總計四個欄位標題以 `IssuesHelper#breakdown_sort_link(key, label)` 渲染為
    `link_to`（`class="sort-button"`），對齊 prototype 的 `.sort-button`／`sortable: true` 機制
    （需求 3a.5）：連結網址帶 `breakdown_sort`／`breakdown_dir` query params，並保留目前所選
    `month`、固定 `tab: "stats"`；同一欄位再次點擊時 `next_dir` 反轉（`desc`↔`asc`），切換不同
    欄位時 `next_dir` 固定為 `desc`；目前排序中的欄位標題附加 ▲（`asc`）／▼（`desc`）指示；專案
    欄位不提供排序連結，維持純文字 `<th>`。
  - `tracker=測試` 的議題已在 Actor 層 `parse_issues` 排除（需求 5a），`compute_project_breakdown`
    運算的議題子集本身已不含這些議題，Controller／View 不需重複過濾。
- 議題明細表格欄位依序為：議題編號、專案、主旨、歸屬類型、狀態、負責人、開始日期、到期日期、工作
  天數（不顯示 type／tracker，見需求 5.7）。
- 「歸屬類型」欄位：View helper（`IssuesHelper#attribution_label(type)` / `#attribution_class(type)`）
  依 `type` 回傳徽章文字與 CSS class，邏輯與 prototype 的 `attributionLabel`／`attributionClass` 一致，
  渲染為 `<span class="attribution-badge ...">`。
- 「議題編號」欄位：渲染為 `<a href="https://redmine.amastek.com.tw/issues/#{issue.issue_id}"
  target="_blank" rel="noopener noreferrer" class="issue-id-link">`（需求 5.8），沿用 prototype 的
  `.issue-id-link` CSS class。

---

## 資料模型

| 資料集 | 欄位 |
|---|---|
| `month_kpi` | `year_month, complaint, testing, total_bug, block_rate, completed, unresolved, avg_days, sla_rate` |
| `daily_kpi` | `date, complaint, testing, other, total` |
| `issues` | `issue_id, subject, type, tracker, status, assigned_to, start_date, due_date, work_days, project` |
| `project_breakdown` | `project, complaint, testing, other, total`（由 `issues` 衍生計算，非直接讀取自試算表） |

與 prototype 的模擬資料常數（`MONTH_KPI`／`DAILY_KPI`／`ISSUES`，
見 [warroom-issue-dashboard-static-prototype/design.md](../warroom-issue-dashboard-static-prototype/design.md)）
欄位一一對應（`MONTH_KPI` 已移除 `top3`），確保畫面呈現邏輯可直接沿用。工程師負載表／專案清單表
不在本 spec 範圍內，無對應資料集。

---

## 錯誤處理

沿用 [rails-standards.md](../../steering/rails-standards.md) 統一錯誤格式與 `failure_code` 對應表。
三個讀取類別（`project_breakdown` 為衍生計算，不另外呼叫 API，故不計入）中任一讀取失敗即整體失敗
（需求 6.2），`IssuesController` 於失敗時渲染錯誤訊息（比照既有 `DashboardController` 的頁面層級
錯誤顯示）。

---

## 測試策略

- **單元測試**（RSpec，比照既有 `spec/clients/`、`spec/actors/` 慣例）：
  - `IssueSheetsClient`：stub `Google::Apis::SheetsV4::SheetsService`，驗證分頁名稱／range 正確、
    UTF-8 重標記、合併邏輯（`raw_2023`〜`raw_2027`）僅保留第一個分頁標題列；`raw_2027` 為空分頁的
    邊界情況（僅標題列、無資料列）需涵蓋。
  - `Sheets::FetchIssueDashboard`：驗證三類資料解析正確（含 `project_breakdown` 分組統計、日期正規化、空列跳過、
    整數轉換失敗容錯）、錯誤對應（404/403/其他）。
- **Request specs**：`GET /api/issue_dashboard` 回傳結構符合需求 7.3；`GET /issues` 帶
  `project`／`status`／`month` query params 時回傳正確篩選結果。
- **頁面功能與端對端驗證（Playwright E2E，取代原規劃的瀏覽器手動檢查）**：本機開發環境已於
  `config/credentials/development.yml.enc` 設定真實 Service Account 憑證，`rails server` 可直接
  以真實試算表資料運作，故 Task 11／13 改以 Playwright 驅動實際運行中的 `rails server`（而非僅
  RSpec 的純 HTTP 字串比對）進行驗證，取代原規劃的人工瀏覽器操作：
  - 驗證斷言 SHALL 針對真實資料的**結構性質**（例如「清空狀態篩選後議題筆數增加」「切換月份後
    KPI 卡片數值與 `GET /api/issue_dashboard` 回傳值一致」），不得寫死特定筆數或特定專案名稱等
    隨真實資料變動的具體數值，避免測試隨試算表內容變動而失準。
  - 涵蓋範圍：Turbo Frame 局部更新（監聽 `framenavigated` 事件確認主畫面未整頁重載）、月份／
    專案／狀態篩選正確套用、空結果狀態訊息、Redmine 連結屬性、響應式表格版面（Rails 版為橫向
    捲動，非 prototype 的堆疊卡片版面，兩者為刻意不同的響應式設計選擇）、`GET /api/issue_dashboard`
    JSON 與 `GET /issues` HTML 呈現的資料一致性、`tracker=測試` 議題確實從真實資料中被排除。
  - 測試腳本為一次性驗證腳本，不納入 CI 常態測試套件（不同於 RSpec，不需要固定憑證），比照
    `docs/` prototype 既有的 Playwright 驗證慣例（`scratchpad` 目錄下的腳本）。
