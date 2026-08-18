# 設計文件

## 概述

比照 305/306/307 的四層架構（Controller → Actor → Client → Blueprint），新增第四條平行資料流讀取
`300_員工專案`「專案工程師對照表」分頁，並新增一個彙總型 Actor（`Sheets::FetchProjectHistory`）整合
305/306/307
既有 Actor 的輸出，供單一 `ProjectHistoryController#index` 依 `project` 參數呈現橫向總覽或縱向歷程。
不修改 305/306/307 任何既有檔案；燃盡圖直接重用既有 `_burndown_chart.html.erb` partial 與
`BurndownHelper`，其餘圖表（甘特圖、花費工時趨勢、測試問題趨勢）新增獨立的 partial／Helper。

---

## 元件與介面

### ProjectRosterSheetsClient（`app/clients/project_roster_sheets_client.rb`）

- `SPREADSHEET_ID = "101fF0GlW2iwjC6TNQnNgKjUrxJg-3Ia5nCYox6haTNM"`
- `SHEET_NAME = ENV.fetch("PROJECT_ROSTER_SHEET_NAME", "專案工程師對照表")`：已用真實 Service
  Account 憑證對真實試算表確認過的分頁名稱（規劃階段原本猜測是「專案清單」，實測後修正）。
- 固定讀取 `"#{SHEET_NAME}!A1:J200"`（欄數固定，200 列遠大於目前已知的專案數量，不需要 307
  client 那種動態欄寬探測）。
- 沿用 `GoogleSheetsCredentials` module 與既有的 UTF-8 重標記慣例，唯讀 scope。

### Sheets::FetchProjectRoster（`app/actors/sheets/fetch_project_roster.rb`）

`output :roster`（`Array<Hash>`，欄位 `project_name, abbreviation, status, customer, pm,
burndown_names_raw`）。

列解析：A=專案、B=專案縮寫、C=狀態、H=客戶、I=PM、J=307對應專案（D/E/F/G 為比例／生效月份／失效
月份／負責RD，與本頁面呈現無關，不解析）。J 欄是真實串接後人工新增的對照欄（見下方
`Sheets::FetchProjectHistory` 說明），原樣保留整段文字（不拆解成清單，見 requirements.md 需求
1.2a）。`專案`（A 欄）為空白的列（試算表以空白列分隔不同客戶群組）整列跳過。錯誤處理比照既有三個
Actor 的三段式 `rescue Google::Apis::ClientError` + `rescue => e`。

### Sheets::FetchProjectHistory（`app/actors/sheets/fetch_project_history.rb`）

```ruby
input :project, default: nil
output :overview_rows       # 一律計算：Array<Hash>（詳情頁的專案下拉選單也需要）
output :detail               # project 有值時額外計算：Hash 或 nil
output :roster_unavailable   # Roster 讀取失敗時 true，見下方「錯誤處理」
output :failure_code
output :message
```

`call` 依序呼叫 Roster 與既有 305/306/307 三個 Actor 的 `.result`：
- `Sheets::FetchProjectRoster.result`：失敗時**不**整體失敗，改為 `roster = []`、
  `self.roster_unavailable = true`（見下方「錯誤處理」，真實串接後才發現的設計變更）。
- `Sheets::FetchProjectProgress.result(scope: "all", incomplete_only: false)`（取得
  `grouped_data`——這是該 Actor **未受**任何篩選條件影響的全量任務資料，`scope`／`incomplete_only`
  這兩個 input 只影響 `summary`／`display_data` 兩個衍生輸出，不影響 `grouped_data` 本身，故這裡的
  input 值其實不影響本 Actor 的結果，明確傳入僅為避免依賴該 Actor 的預設值語意）。
- `Sheets::FetchIssueDashboard.result`（取全量 `issues`，不使用該 Actor 預設按月份／狀態篩選過的
  `filtered_issues`）。
- `Sheets::FetchProjectBurndown.result(status: "all")`——**不帶 `project` 篩選**：307 的專案命名與
  305/306/Roster 是獨立體系，該 Actor 自己的 `project` 篩選是精確字串比對，用 305 傳入的字串篩選
  307 資料只會篩出空結果，故一律抓全量，篩選邏輯自己在 `build_detail` 依 Roster 的
  `burndown_names_raw` 判斷（見下方）。

以上三者（305/306/307）任一失敗即整體失敗（`fail!`），不做部分成功回傳，錯誤碼直接沿用先失敗的
那個 Actor 的 `failure_code`。

#### 橫向總覽（一律計算）

```ruby
def resolve_roster_row(roster, project_name)
  roster.find { |r| r[:project_name] == project_name } ||
    roster.find { |r| r[:abbreviation].present? && r[:abbreviation] == project_name } ||
    {}
end

def build_overview_rows(roster, progress_grouped)
  progress_grouped.map do |project_name, tasks|
    row = resolve_roster_row(roster, project_name)
    planned = tasks.filter_map { |t| t[:planned_completion_date] }.max
    ongoing = tasks.any? { |t| t[:actual_completion_date].blank? }
    actual = ongoing ? nil : tasks.filter_map { |t| t[:actual_completion_date] }.max
    {
      project_name: project_name, customer: row[:customer], pm: row[:pm], status: row[:status],
      planned_completion_date: planned, actual_completion_date: actual, tasks: tasks
    }
  end
end
```

以 305 的專案名稱為主（`progress_grouped.keys`）而非 Roster 的專案清單，因為橫向總覽的資料主體是
「有進度可看的專案」。`resolve_roster_row` 依序嘗試 Roster 的「專案」全名、「專案縮寫」兩欄——**真實
串接後才發現** 305 的專案名稱有時用其中一欄、有時用另一欄，沒有固定規則（規劃階段原本假設「字串
完全比對」就夠，實測 8 個專案只對到 2 個，加上兩欄查找後才 9/9 全部對上）；兩欄都找不到時
`customer`/`pm`/`status` 為 `nil`，View 顯示 `—`（需求 2.2）。篩選（狀態／客戶／PM）與甘特圖資料由
Controller／Helper 對 `overview_rows` 直接處理，不在 Actor 內做。

#### 縱向歷程（`project` 有值）

```ruby
def build_detail(project, roster_row, burndown_issues, all_issues)
  canonical_name = roster_row[:project_name].presence || project
  project_issues = all_issues.select { |i| i[:project] == canonical_name }

  burndown_names_raw = roster_row[:burndown_names_raw].presence
  matched_burndown_issues =
    if burndown_names_raw
      burndown_issues.select { |i| burndown_names_raw.include?(i[:project].to_s) }
    else
      burndown_issues.select { |i| i[:project] == project }
    end

  {
    work_hours_series: aggregate_work_hours(matched_burndown_issues),
    ideal_series: aggregate_ideal_series(matched_burndown_issues),
    actual_series: aggregate_actual_series(matched_burndown_issues),
    testing_trend: weekly_testing_counts(project_issues),
    complaint_summary: complaint_status(project_issues)
  }
end
```

**真實串接後發現的三套獨立命名系統**（規劃階段的簡化假設與實際狀況不符）：
- **306** 固定用 Roster「專案」全名（如 `"AG 亞炬"`），故用 `resolve_roster_row` 解析出的
  `canonical_name` 比對，不是直接拿使用者選的 305 縮寫式名稱去比對（兩者對不上）。
- **307** 的顆粒度比 305/Roster 細，一個 305/Roster 專案常對應多個 307 項目（例如「AG 亞炬」對應
  307 的「亞炬 PMS」「亞炬 Else」「亞炬 Flow」「亞炬 Wms」四項），且沒有任何自動規則可推得對應
  關係——連「客戶名稱前綴」都試過，仍不可靠（例如客戶「立翔機電」對應的 307/305 前綴其實是
  「立翔」，不是「立翔機電」；「AMAS」客戶底下同時有 4 個專案，前綴規則會抓錯）。最終改為讀取
  `300_員工專案` 人工新增的「307對應專案」欄（`burndown_names_raw`）：307 議題的 `project` 名稱
  只要整串是這欄文字的子字串就算屬於本專案。子字串比對而非拆解成清單（`split(",")` 之類）的原因：
  該欄實務上有時用逗號、有時用空白、甚至用換行分隔，且部分 307 名稱本身含空白（如「亞炬 PMS」），
  沒有可靠的分隔符可以拆；子字串比對不需要拆解，任何分隔符都能正確判斷。
  Roster 查不到該專案、或 `burndown_names_raw` 為空時，退回直接以 305 傳入的 `project` 字串精確
  比對（原本的行為）。

**花費工時彙總**（需求 4.2）：

```ruby
def issue_weekly_spent(issue)
  prev = issue[:estimated_hours].to_f
  issue[:actual_series].map do |point|
    spent = (prev - point[:hours].to_f).round(2)
    prev = point[:hours].to_f
    { date: point[:date], hours: spent }
  end
end

def aggregate_work_hours(issues)
  sum_series_by_date(issues.map { |i| issue_weekly_spent(i) })
end
```

**實際剩餘人時彙總**（需求 4.3）：直接依日期加總各議題的 `actual_series`
（`sum_series_by_date(issues.map { |i| i[:actual_series] })`）。**已知簡化**：不同議題的
`actual_series` 涵蓋週別範圍可能不同（`Sheets::FetchProjectBurndown#merge_rows` 會依各議題自己的
開案日期裁切週範圍），加總只涵蓋各議題各自有資料的週別，未涵蓋的週別視為 0（見 requirements.md
「已知簡化」段落，與靜態原型既有簡化一致）。

**理想剩餘人時彙總**（需求 4.3，避免靜態原型階段發現過的加總凹陷 bug）：

```ruby
# 不可直接加總每個議題「已含起訖錨點」的 ideal_series（Sheets::FetchProjectBurndown#compute_
# ideal_series 的輸出）——不同議題的錨點日期不同，加總後會在只有少數議題有資料的日期出現不該有的
# 凹陷（同 warroom-project-history-static-prototype 的 project-history-detail.js 已修正過的 bug，
# 見該檔案 computeProjectBurndown 的附註）。改為在彙總的每一個共同日期上，逐議題以起訖日期比例公式
# 即時算出當天的理想剩餘人時再加總，缺少合法起訖日期的議題當天回傳 nil，直接排除不計入。
def ideal_hours_at(issue, date)
  start_d = parse_date(issue[:start_date])
  due_d = parse_date(issue[:due_date])
  return nil if start_d.nil? || due_d.nil? || due_d <= start_d

  ratio = ((date - start_d).to_f / (due_d - start_d).to_f).clamp(0.0, 1.0)
  (issue[:estimated_hours].to_f * (1 - ratio)).round(2)
end

def aggregate_ideal_series(issues)
  dates = issues.flat_map { |i| i[:actual_series].map { |p| Date.parse(p[:date]) } }.uniq.sort
  dates.filter_map do |date|
    values = issues.filter_map { |i| ideal_hours_at(i, date) }
    next if values.empty?
    { date: date.iso8601, hours: values.sum.round(2) }
  end
end
```

**測試問題趨勢／客訴議題狀態**（需求 5）：邏輯與 `docs/js/project-history-detail.js` 的
`weekStart`／`renderTestingTrend`／`computeComplaintStatus` 一致，改寫為 Ruby（`Date#beginning_of_
week(:monday)` 取代手刻的 `weekStart`），各自獨立實作。

### ProjectHistoryController（`app/controllers/project_history_controller.rb`）

```ruby
def index
  result = Sheets::FetchProjectHistory.result(project: params[:project].presence)
  return build_failure(result.message) unless result.success?

  if params[:project].present?
    build_detail_success(result)
  else
    build_overview_success(result)
  end
end
```

橫向總覽篩選（狀態／客戶／PM）與檢視模式（`view=list`／`view=gantt`）在 `build_overview_success` 內
以 `params` 直接對 `result.overview_rows` 做記憶體篩選，比照 `IssuesController` 的篩選寫法。

### Blueprint

`ProjectHistoryRowBlueprint`（`app/blueprints/project_history_row_blueprint.rb`）：
`identifier :project_name`；`fields :customer, :pm, :status, :planned_completion_date,
:actual_completion_date`。只用於橫向總覽的專案列（記錄型資料）；縱向歷程的彙總序列（work_hours_
series／ideal_series／actual_series／testing_trend／complaint_summary）是單一結構化 Hash 而非
記錄清單，比照 `BurndownController` 的 `@projects`／`@assignees`（非記錄型資料不經 Blueprint）直接
以 Actor 輸出設定 instance variable，不另建 Blueprint。

### View（`app/views/project_history/`）

- `index.html.erb`：依 `@mode`（`:overview` / `:detail`）分派渲染，比照 `burndown/index.html.erb`
  的 `turbo_frame_tag` + 表單送出模式；篩選表單（總覽）／專案選單（詳情）皆送到同一個 `/project_
  history` 路徑。
- `_overview_list.html.erb` / `_overview_gantt.html.erb`：橫向總覽的清單／甘特圖兩種局部樣板。
- `_work_hours_trend.html.erb`：花費工時趨勢，重用 `IssuesHelper` 的 `trend_chart_*` 系列方法（這些
  方法只依賴 record 的 `:date`／`:total` 鍵，本頁面把 `work_hours_series` 的 `:hours` 對應到
  `:total` 傳入即可直接沿用，不需重寫座標計算）。
- 燃盡圖：直接 `render partial: "burndown/burndown_chart", locals: { title: ..., actual_series:
  @actual_series, ideal_series: @ideal_series }`（重用 307 既有 partial，不重寫）。
- `_testing_trend.html.erb`：測試問題趨勢，同樣重用 `IssuesHelper` 的 `trend_chart_*` 方法。
- `_complaint_summary.html.erb`：統計數字＋未解決客訴清單，議題編號連結重用 306 既有的 Redmine URL
  規則（`https://redmine.amastek.com.tw/issues/{issue_id}`）。

### ProjectHistoryHelper（`app/helpers/project_history_helper.rb`）

僅新增甘特圖需要的座標計算（`gantt_task_x`／`gantt_row_y` 等），邏輯與 `docs/js/project-history-
overview.js` 的 `renderGanttChart` 一致，各自獨立實作。

### Route

`config/routes.rb` 新增 `get "/project_history", to: "project_history#index"`。

---

## 資料模型

| 輸出 | 欄位 |
|---|---|
| `Sheets::FetchProjectRoster#roster` | `project_name, abbreviation, status, customer, pm, burndown_names_raw` |
| `Sheets::FetchProjectHistory#overview_rows` | `project_name, customer, pm, status, planned_completion_date, actual_completion_date, tasks` |
| `Sheets::FetchProjectHistory#detail` | `work_hours_series, ideal_series, actual_series, testing_trend, complaint_summary`（皆為 `Array<Hash>` 或彙總 Hash，見上方「元件與介面」） |

---

## 錯誤處理

- 305/306/307 三個子 Actor 任一失敗，`Sheets::FetchProjectHistory` 立即 `fail!`，不做部分成功回傳
  （同 306 `FetchIssueDashboard` 的既有慣例）。
- **Roster 失敗時降級顯示，不算整頁錯誤**（真實串接後才改的設計，見 requirements.md 需求 6.2 的
  設計變更紀錄）：`roster = []`、`roster_unavailable = true`，`overview_rows` 正常依 305 資料計算，
  只是每個專案的 `customer`/`pm`/`status` 都是 `nil`；Controller 把 `roster_unavailable` 傳給 View，
  可選擇顯示提示文字告知客戶／PM 資料目前無法讀取（非必要，本 spec 未強制要求呈現此提示）。
- Roster 查得到但找不到對應專案：跟 Roster 整體失敗呈現效果相同，都是客戶/PM/狀態顯示 `—`（需求
  2.2），對畫面而言是同一種狀態。
- 花費工時／燃盡彙總、測試趨勢、客訴統計於資料為空時皆顯示對應提示文字，不留白、不拋例外。

---

## 測試策略

- `spec/clients/project_roster_sheets_client_spec.rb`：stub `Google::Apis::SheetsV4::SheetsService`，
  驗證讀取範圍字串正確、UTF-8 重標記正確。
- `spec/actors/sheets/fetch_project_roster_spec.rb`：欄位對應正確（含 `burndown_names_raw` 原樣保留
  不拆解）、空白「專案」列跳過、三種 failure_code。
- `spec/actors/sheets/fetch_project_history_spec.rb`：直接測試 `.send` 私有方法
  `aggregate_ideal_series`／`aggregate_work_hours`／`complaint_status`／`build_overview_rows`／
  `build_detail` 等（比照 `fetch_project_burndown_spec.rb` 既有慣例）；**必須**包含「兩個議題起訖
  錨點日期不同時，理想線彙總無凹陷」的迴歸測試（對照 `warroom-project-history-static-prototype`
  發現過的 bug），以及「307 燃盡議題依 `burndown_names_raw` 子字串比對、不管分隔符為何都正確判斷」
  的測試；`#call` 需涵蓋「Roster 失敗時降級顯示（`roster_unavailable: true` 但整體仍成功）」與
  「305/306/307 任一失敗時整體失敗」兩種情境。
- `spec/requests/project_history_spec.rb`：stub 四個 Sheets Client 的 `.fetch_*`，驗證總覽篩選、
  甘特圖切換、縱向歷程各區塊渲染、305/306/307 任一失敗時的錯誤頁面、Roster 單獨失敗時的降級顯示。

## 已用真實資料驗證（非僅 RSpec stub）

本 sandbox 取得真實 Google Service Account 憑證後，曾直接對真實試算表執行過
`Sheets::FetchProjectHistory.result` 與各子 Actor，確認：305（558 筆任務）、306（412 筆議題）、307
（88 筆燃盡議題）、Roster（29 筆專案）皆可正常讀取；9 個目前在 305 有進度資料的專案，客戶/PM 皆
9/9 對應成功，縱向歷程四個區塊（花費工時／燃盡圖／測試趨勢／客訴狀態）皆有非空資料。這是本 spec
規劃階段完全沒有的驗證管道（規劃時 sandbox 尚無真實憑證），也是發現「三套獨立命名系統」「Roster
共用權限獨立於 305/306/307」等問題的方式。
