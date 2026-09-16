# 任務清單

## 依賴波次

```
Wave 1   1. FetchIssueDashboard 判斷邏輯提為 class method（前置變更）
             │
Wave 2   2. Summary::BuildPmWeeklyReport ──┐        3. PmWeeklyIssueBlueprint（可並行）
             │                             │
Wave 3   4. Controller + 路由              5. PmWeeklyReportHelper（可並行）
             │                             │
Wave 4   6. View（index + 4 partial）      7. 入口頁連結（可並行）
             │
Wave 5   8. RSpec（Actor / Request / Helper）
             │
         9. 檢查點：rspec + rubocop 全綠
```

---

- [x] 1. 把 `Sheets::FetchIssueDashboard` 的完成／逾期／到期日判斷提為 class method
  - 新增 `.effective_due_date(issue)` → `[Date|nil, :sheet|:sla|nil]`（試算表到期日優先，
    次之依 `ISSUE_SLA_DAYS` 自 `start_date` 推算）
  - 公開 `.done?(issue)`、`.overdue?(issue)`；`.overdue?` 改以 `.effective_due_date` 實作
  - 既有 private `issue_done?`／`issue_overdue?`／`sla_overdue?` 刪除，唯一呼叫點
    `compute_issue_kpis` 改呼叫 class method
  - **驗收**：`bundle exec rspec spec/actors/sheets/fetch_issue_dashboard_spec.rb` 全綠
    （既有測試即迴歸防線，行為必須完全不變）；新增三個 class method 的 spec，涵蓋
    有填到期日／`Complaint` 推算／`TestingBug` 推算／`Other` 無 SLA 回傳 `[nil, nil]`
  - _需求：3.4、3.5、3.6_

- [x] 2. 新增 `Summary::BuildPmWeeklyReport`
  - 呼叫 305（核心，失敗即 `fail!`）／306／階段追蹤（次要，失敗設 `*_unavailable` 旗標）
  - 依 design.md「週別歸屬（權威定義）」表實作 305／306／階段追蹤三套歸屬，互斥
  - 依專案分組 + 排序（逾期依天數、其餘依日期）
  - `project` 篩選只作用於 305／306
  - **驗收**：以 `travel_to` 固定在某個星期五，餵入涵蓋每一列歸屬條件的假資料，
    每筆只出現在一個清單；305 失敗回傳原 `failure_code`；306／階段追蹤失敗時旗標為 true
    且其餘清單照常產出
  - _需求：1.1、2.1–2.7、3.1–3.3、3.7、4.2、4.4、5.1、5.2、6.1、6.2_

- [x] 3. 新增 `PmWeeklyIssueBlueprint`
  - 欄位：`issue_id, subject, type, status, assigned_to, project, effective_due_date,
    due_date_estimated`
  - 不改動既有 `IssueBlueprint`（306 頁面與 JSON API 欄位契約）
  - **驗收**：blueprint spec 確認渲染出上述 8 個欄位、且 `due_date_estimated` 為布林
  - _需求：3.5_

- [x] 4. 新增 `PmWeeklyReportController` + 路由 `get "/pm_weekly_report"`
  - 成功時指派 ivar；失敗時仍回 200 並渲染錯誤訊息（既有 HTML 頁面慣例，
    `failure_code` → HTTP 狀態對應表只適用 JSON API）
  - 只負責傳遞 `params[:project]`，不做任何資料處理
  - **驗收**：`bin/rails routes | grep pm_weekly_report` 有該路由；controller 無任何
    日期運算或資料轉換程式碼
  - _需求：1.1、5.4、6.1_

- [x] 5. 新增 `PmWeeklyReportHelper`
  - `pm_weekly_range_label(range)` → `YYYY/MM/DD ~ YYYY/MM/DD`
  - `pm_weekly_date_label(value)` → `YYYY/MM/DD`；無法解析的原始字串照原樣顯示
  - `pm_weekly_overdue_days(task)` → `(Date.current - 預計完成日).to_i`
  - `pm_weekly_due_date_label(issue)` → 推算值標示為「（推算）」
  - `pm_weekly_freshness_label(fetched_at)` → 相對時間（未設 time_zone，絕對時間會差 8 小時）
  - 方法一律加 `pm_weekly_` 前綴，避免與其他 helper 同名覆蓋
  - **驗收**：helper spec 以 `travel_to` 驗證三個方法的輸出字串
  - _需求：1.1、2.9、3.5_

- [x] 6. 新增 View：`index` + `_task_section` + `_issue_section` + `_phase_section` + `_project_group`
  - 四個區塊（逾期未完成／本週工作／下週工作／階段追蹤），各顯示筆數
  - 空區塊顯示空狀態文字，不隱藏區塊
  - 專案下拉篩選（`?project=`），維持選取狀態
  - 306／階段追蹤失敗時頂部顯示降級提示並列出資料源名稱
  - 重用既有 CSS class，不新增顏色系統
  - **驗收**：`/pm_weekly_report` 回 200 且四個區塊標題皆出現；`?project=<名稱>` 後
    只剩該專案的 305／306 項目、階段追蹤區塊筆數不變
  - _需求：1.1–1.4、2.8、3.5、4.1、4.3、5.1–5.4、6.2_

- [x] 7. `app/views/home/index.html.erb` 新增 PM 週報 `.entry-card` 連結
  - **驗收**：入口頁出現該連結且可點進 `/pm_weekly_report`
  - _需求：1.1_

- [x] 8. RSpec：Actor spec（週別歸屬各分支、篩選、降級）、Request spec（頁面渲染、
      305 失敗、306／階段追蹤失敗、專案篩選）、Helper spec
  - 所有涉及「今天」的測試一律 `travel_to` 固定日期（既有 spec 曾因未固定日期而 flaky，
    見 `warroom-executive-weekly-summary/tasks.md` 備註）
  - **驗收**：`bundle exec rspec` 全綠
  - _需求：全部_

- [x] 9. 檢查點：`bundle exec rspec`、`bin/rubocop` 全部通過
  - CI 不跑 rspec，推送前必須本機跑過（見 CLAUDE.md）
  - **驗收**：兩個指令皆 0 失敗
