# 設計文件

## 架構

```
PmWeeklyReportController#index
  └── Summary::BuildPmWeeklyReport          （新增，app/actors/summary/）
        ├── Sheets::FetchProjectProgress    （既有，scope: "all", incomplete_only: false）→ 核心，失敗即整頁失敗
        ├── Sheets::FetchIssueDashboard     （既有，status: ""）→ 次要，失敗降級
        └── Sheets::FetchPhaseTracking      （既有）→ 次要，失敗降級
  └── View: app/views/pm_weekly_report/（index + 4 個 partial）+ PmWeeklyReportHelper
```

沿用 `Summary::BuildExecutiveSummary` 已建立的模式：新 Actor 只負責「彙總 + 週別歸屬」，三個資料
源各自的讀取、解析、正規化完全交給既有 Actor，不直接碰任何 Client。

### 為什麼是新 Actor，不是擴充 `Summary::BuildExecutiveSummary`

兩者受眾與輸出形狀不同（例外管理 vs 工作明細），既有 Actor 已 316 行且輸出 12 個欄位；把兩套
規則塞進同一個 Actor 會讓「健康度」與「週別歸屬」兩組互不相干的邏輯糾纏。判斷邏輯不重複實作
——而是重用既有的 class method（見下節「前置變更」）。

## Components and Interfaces

| 元件 | 路徑 | 職責 |
|---|---|---|
| `PmWeeklyReportController` | `app/controllers/pm_weekly_report_controller.rb` | 呼叫 Actor，成功時把輸出指派給 ivar，失敗時依 `failure_code` 對應 HTTP 狀態（沿用既有對應表） |
| `Summary::BuildPmWeeklyReport` | `app/actors/summary/build_pm_weekly_report.rb` | 週別歸屬、分組排序、降級旗標 |
| `PmWeeklyIssueBlueprint` | `app/blueprints/pm_weekly_issue_blueprint.rb` | 306 議題在本頁的輸出欄位（含兩個衍生欄位） |
| `PmWeeklyReportHelper` | `app/helpers/pm_weekly_report_helper.rb` | 週區間文字、逾期天數與對應 CSS class、推算到期日標記 |
| View | `app/views/pm_weekly_report/` | `index` + `_task_section` + `_issue_section` + `_phase_section` + `_project_group` |

### Actor 輸出

```ruby
output :week_range, :next_week_range, :fetched_at
output :overdue_tasks, :this_week_due_tasks, :this_week_completed_tasks,
       :next_week_tasks, :undated_tasks
output :overdue_issues, :this_week_issues, :next_week_issues, :undated_issue_count
output :phase_items
output :project_names, :selected_project
output :issues_unavailable, :phase_tracking_unavailable
output :failure_code, :message
```

305 的五個任務清單皆為 `{ project_name => [task, ...] }` 的分組結構（需求 5.1）；306 的三個清單
同樣依 `project` 分組。

### Blueprint 取捨

- **305 任務重用既有 `ProjectTaskBlueprint`**：欄位需求完全相同（需求 2.8）。逾期天數
  **不**加進 Blueprint——該 Blueprint 同時是 `/api/project_progress` 的欄位契約（見其註解與
  `spec/requests/api/project_progress_spec.rb`），且既有慣例已把「是否逾期」這種畫面衍生值
  放在 `Sheets::FetchProjectProgress.overdue?` 由呼叫端計算。逾期天數比照辦理，由 Helper 計算。
- **306 議題新增 `PmWeeklyIssueBlueprint`**：需要 `effective_due_date`（含 SLA 推算結果）與
  `due_date_estimated`（布林，需求 3.5 要標示推算值）兩個 PM 週報專屬欄位，不可污染
  `IssueBlueprint`（306 頁面與 JSON API 的欄位契約）。
- **階段追蹤不新增 Blueprint**：直接使用 `Sheets::FetchPhaseTracking` 輸出的 card hash，
  沿用 `Summary::BuildExecutiveSummary#phase_exceptions` 既有做法（同樣沒有 Blueprint）。

## 前置變更：把 306 的完成／逾期／到期日判斷提為 class method

需求 3.4 要求重用既有判斷，但 `Sheets::FetchIssueDashboard` 的 `issue_done?`、`issue_overdue?`、
`sla_overdue?` 目前都是 private instance method。比照 `Sheets::FetchProjectProgress.overdue?`
已建立的前例（該方法就是為了讓 Blueprint／Controller 共用而公開），做三件事：

1. 新增 `Sheets::FetchIssueDashboard.effective_due_date(issue)` → 回傳
   `[Date|nil, :sheet|:sla|nil]`：試算表有填到期日就用它（`:sheet`）；沒填但 type 有 SLA
   （`ISSUE_SLA_DAYS`）就以 `start_date + sla_days` 推算（`:sla`）；兩者皆無回傳 `[nil, nil]`。
2. `Sheets::FetchIssueDashboard.done?(issue)` 與 `.overdue?(issue)` 公開；`overdue?` 改以
   `effective_due_date` 實作，讓「到期日」只有一處定義。
3. 既有的 private `issue_done?`／`issue_overdue?`／`sla_overdue?` 直接刪除（唯一呼叫點是
   `compute_issue_kpis`，改為直接呼叫 class method，不留一層只做委派的薄包裝）。**306 頁面與
   KPI 的行為不變**，既有 `spec/actors/sheets/fetch_issue_dashboard_spec.rb` 必須維持全綠——
   這是本次改動的迴歸防線。

## 週別歸屬（權威定義）

```ruby
this_week = Sheets::FetchProjectProgress.week_range(Date.current)       # 週一..週日
next_week = Sheets::FetchProjectProgress.week_range(Date.current + 7)
```

### 305 任務（依序判斷，先命中先歸屬，互斥；需求 2.6）

| 順序 | 條件 | 歸屬 |
|---|---|---|
| 1 | 已完成 且 `actual_completion_date` ∈ 本週 | `this_week_completed_tasks` |
| 2 | 已完成（其餘） | 不列入任何區塊 |
| 3 | 未完成 且 `planned_completion_date` < 今天 | `overdue_tasks` |
| 4 | 未完成 且 `planned_completion_date` ∈ 本週 | `this_week_due_tasks` |
| 5 | 未完成 且 `planned_completion_date` ∈ 下週 | `next_week_tasks` |
| 6 | 未完成 且 `planned_completion_date` 空白／無法解析 | `undated_tasks` |
| 7 | 未完成 且 預計完成日在下週之後 | 不列入（不是本次週報的範圍） |

需求 2.6 寫的順序（1 → 3 → 2 → 4 → 5）與此表一致：已完成的先分流，未完成的才依逾期 → 本週
→ 下週 → 未定判斷。逾期優先於本週，所以「本週一到期、今天週五還沒完成」只會出現在逾期區塊。

### 306 議題

未結案（`.done?` 為 false）者，取 `effective_due_date`：
`nil` → 只計入 `undated_issue_count`；`< 今天` → `overdue_issues`；∈ 本週 → `this_week_issues`；
∈ 下週 → `next_week_issues`；更晚 → 不列入。已結案議題一律不列入（需求 3.7）。

### 階段追蹤

對每張 card 取 `status` ∈ {延誤未完成, 未完成, 暫緩} 者，取「目前階段」（`stages` 由後往前第一個
有 `primary` 的階段，與 `FetchPhaseTracking#current_issue_status` 同一個定義）的 `planned_date`：
< 今天 → 逾期；∈ 本週／下週 → 對應區塊；其餘不列入（需求 4.2）。

## 逾期天數

`(Date.current - planned_completion_date).to_i`，由 `PmWeeklyReportHelper#overdue_days` 計算。
**不採用試算表的「延遲天數」欄位**：該欄位是人工填寫／公式產生的靜態值，對未完成任務不會隨
今天的日期前進而更新，週五看到的數字會是過期的（需求 2.9）。已完成任務仍照既有頁面慣例顯示
試算表的 `delay_days`（那是「當初延遲了幾天」的事實紀錄，語意不同）。

## 排序

- 逾期區塊：逾期天數由多到少（最痛的排最前），同天數依專案名稱、任務名稱。
- 其餘區塊：預計完成日由近到遠，同日期依任務／議題名稱。
- 「本週已完成」例外，依**實際完成日**由早到晚排序：PM 寫週報是照「這週哪天做完了什麼」
  交代的，用預計完成日排序沒有意義。
- 專案分組：依專案名稱排序；`undated_tasks` 與 `undated_issue_count` 放在該區塊最後。

## 篩選

`?project=<專案名稱>` 只作用於 305／306（需求 5.2）。實作在 Actor 內（分組前先過濾），
Controller 只負責把 `params[:project]` 傳進去。306 的 `project` 欄位與 305 的專案名稱不保證
同一套寫法，比對方式為**雙向包含**（相等、或任一方包含另一方）——這是本 spec 自訂的比對，
不是既有慣例（`Summary::BuildExecutiveSummary` 是靠 Roster 的專案縮寫做完全相同比對，
本頁不讀 Roster）。兩邊完全對不起來的 306 議題在套用篩選時不顯示：寧可少顯示，也不要把
別的專案的客訴算進來。階段追蹤不受篩選影響（需求 5.3）。

## View 與樣式

不新增顏色系統，重用既有 class：`.dashboard-header`／`.breadcrumb`／`.summary-bar`／`.stat-item`
（各區塊筆數）／`.project-block`／`.project-tasks`／`.row-overdue`／`.overdue-tag`／`.delay-days`／
`.status-badge`／`.empty-state`／`.section-note`。四個區塊各用一個 `<section>` + `<h2>`，
語意化標記（需求 1.2、1.4）。`app/views/home/index.html.erb` 新增 `.entry-card` 連結（第一張，
排在 CEO 週報之後）。

## 錯誤與降級

| 情境 | 行為 |
|---|---|
| 305 失敗 | `fail!(failure_code:, message:)` 原樣往上傳，Controller 依既有對應表回應（404/403/422/500），View 只渲染 `.error-message` |
| 306 失敗 | `issues_unavailable = true`，306 三個清單為空陣列，頁面照常渲染 305 與階段追蹤，頂部顯示「部分資料來源目前無法讀取：306 臭蟲議題」 |
| 階段追蹤失敗 | `phase_tracking_unavailable = true`，同上 |

## 已知限制

1. **305 無開始日欄位**：只能以預計完成日歸屬週別，抓不到「下週開工、月底到期」的任務。
2. **306 無結案日期欄位**：無法呈現「本週結案了哪些議題」，本週已完成只涵蓋 305 任務。
3. **階段追蹤命名系統獨立**：`ProjectProfilesSheetsClient`「專案」分頁用 Notion/Github 專案代碼
   （HRM、JZNPMS），與 305／306 的專案名稱無可靠對照欄位，故獨立區塊且不受專案篩選影響
   （沿用 `warroom-executive-weekly-summary` design.md 同一個取捨，非本 spec 新引入）。
4. **快取延遲**：三個資料源皆有 5 分鐘 client 層快取，頁面顯示的 `fetched_at` 為 305 的抓取時間；
   本頁不提供 `?refresh=`（只有 305 client 支援 force，306／階段追蹤沒有，做半套反而誤導）。
