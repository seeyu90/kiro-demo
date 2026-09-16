# frozen_string_literal: true

require "rails_helper"

# 測試日期固定在 2026/09/18（星期五，PM 實際寫週報的那天）：
#   本週 = 2026/09/14（一）～ 2026/09/20（日）
#   下週 = 2026/09/21（一）～ 2026/09/27（日）
# 依既有慣例 stub Client 層（回傳原始列），讓整條 Actor 鏈真的跑一遍，而不是 stub Actor。
RSpec.describe Summary::BuildPmWeeklyReport do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Date.new(2026, 9, 18)) { example.run } }

  let(:progress_header) { [ "專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延誤", "類型" ] }
  let(:progress_rows) do
    [
      progress_header,
      [ "AG 亞炬", "很久以前就該完成", "未完成", "王贊勛", "2026/08/01", "", "48", "功能" ],
      [ "AG 亞炬", "本週一到期還沒完成", "未完成", "王贊勛", "2026/09/14", "", "4", "功能" ],
      [ "AG 亞炬", "本週日到期", "未完成", "王贊勛", "2026/09/20", "", "", "功能" ],
      [ "Virtuous HRM", "本週三完成的", "完成", "黃靖益", "2026/09/16", "2026/09/16", "0", "功能" ],
      [ "Virtuous HRM", "上週完成的", "完成", "黃靖益", "2026/09/10", "2026/09/10", "0", "功能" ],
      [ "Virtuous HRM", "下週二到期", "未完成", "黃靖益", "2026/09/22", "", "", "PR" ],
      [ "Virtuous HRM", "還沒排期", "未完成", "黃靖益", "", "", "", "功能" ],
      [ "Virtuous HRM", "下個月才到期", "未完成", "黃靖益", "2026/10/15", "", "", "功能" ]
    ]
  end

  let(:issue_header) do
    %w[issue_id subject type tracker status assigned_to start_date due_date work_days sheet_name project total_hours]
  end
  let(:issue_rows) do
    [
      issue_header,
      [ "101", "登入失敗", "Complaint", "Bug", "新建立", "王贊勛", "2026/08/20", "2026/09/01", "2", "", "AG 亞炬", "1" ],
      [ "102", "報表匯出錯誤", "Complaint", "Bug", "處理中", "黃靖益", "2026/09/16", "2026/09/18", "1", "", "Virtuous HRM", "2" ],
      [ "103", "下週要處理", "Other", "Bug", "新建立", "黃靖益", "2026/09/15", "2026/09/22", "1", "", "Virtuous HRM", "0" ],
      [ "104", "已經解決了", "Complaint", "Bug", "已解決", "王贊勛", "2026/08/01", "2026/08/05", "1", "", "AG 亞炬", "3" ],
      [ "105", "沒填到期日的客訴", "Complaint", "Bug", "新建立", "王贊勛", "2026/09/17", "", "1", "", "AG 亞炬", "1" ],
      [ "106", "沒到期日也沒 SLA", "Other", "Bug", "新建立", "王贊勛", "2026/09/01", "", "1", "", "AG 亞炬", "1" ]
    ]
  end

  let(:month_kpi_rows) { [ %w[year_month 客訴 測試 總Bug 攔截率 完成數 未結案 平均天數 SLA達標率 Top3] ] }
  let(:daily_kpi_rows) { [ %w[日期 客訴 測試 其他 總計] ] }

  def phase_row(project:, issue_id:, stage:, planned:, status:, issue_name: "", reason: "")
    [ project, issue_id, issue_name, stage, planned, nil, status, reason,
      "#{project}|#{issue_id}|#{stage}", planned.to_s[0, 4] ]
  end

  let(:phase_rows) do
    [
      phase_row(project: "HRM", issue_id: "9001", issue_name: "報表模組", stage: "開發",
                planned: "2026-09-01", status: "延誤未完成", reason: "等客戶回覆"),
      phase_row(project: "HRM", issue_id: "9002", issue_name: "請假模組", stage: "測試",
                planned: "2026-09-23", status: "未完成"),
      phase_row(project: "JZNPMS", issue_id: "9003", issue_name: "已發布", stage: "發布",
                planned: "2026-09-16", status: "完成")
    ]
  end
  let(:profile_rows) do
    [
      %w[Github/Notion Redmine專案 303專案 客戶 PM 狀態],
      [ "HRM", "Virtuous HRM", "HRM", "AMAS", "楊欣翰", "維護" ],
      [ "JZNPMS", "立翔 PMS", "JZNPMS", "立翔", "呂俐禎", "維護" ]
    ]
  end

  before do
    allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return(progress_rows)
    allow(ProjectProgressSheetsClient).to receive(:fetched_at).and_return(Time.zone.parse("2026-09-18 09:00"))
    allow(IssueSheetsClient).to receive(:fetch_month_kpi_rows).and_return(month_kpi_rows)
    allow(IssueSheetsClient).to receive(:fetch_daily_kpi_rows).and_return(daily_kpi_rows)
    allow(IssueSheetsClient).to receive(:fetch_issue_rows).and_return(issue_rows)
    allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_return(phase_rows)
    allow(ProjectProfilesSheetsClient).to receive(:fetch_rows).and_return(profile_rows)
  end

  let(:result) { described_class.result }

  def task_names(grouped)
    grouped.values.flatten.map { |t| t[:task_name] }
  end

  def issue_ids(grouped)
    grouped.values.flatten.map { |i| i[:issue_id] }
  end

  describe "週區間" do
    it "reports Monday-to-Sunday ranges for this week and next week" do
      expect(result.week_range).to eq(Date.new(2026, 9, 14)..Date.new(2026, 9, 20))
      expect(result.next_week_range).to eq(Date.new(2026, 9, 21)..Date.new(2026, 9, 27))
    end
  end

  describe "頁面表頭與篩選狀態" do
    it "passes through the 305 fetch time for the freshness label" do
      expect(result.fetched_at).to eq(Time.zone.parse("2026-09-18 09:00"))
    end

    it "echoes the selected project back so the dropdown can stay selected" do
      expect(result.selected_project).to be_nil
      expect(described_class.result(project: "AG 亞炬").selected_project).to eq("AG 亞炬")
    end
  end

  describe "305 任務的週別歸屬" do
    it "puts every incomplete task past its planned date into 逾期, however old" do
      expect(task_names(result.overdue_tasks)).to contain_exactly("很久以前就該完成", "本週一到期還沒完成")
    end

    it "keeps a task that was due earlier this week out of 本週待完成 (逾期 wins, no double-listing)" do
      expect(task_names(result.this_week_due_tasks)).to contain_exactly("本週日到期")
      expect(task_names(result.this_week_due_tasks)).not_to include("本週一到期還沒完成")
    end

    it "lists tasks completed within this week, by actual completion date" do
      expect(task_names(result.this_week_completed_tasks)).to contain_exactly("本週三完成的")
    end

    it "excludes tasks completed before this week" do
      expect(task_names(result.this_week_completed_tasks)).not_to include("上週完成的")
    end

    it "lists next week's tasks, and excludes anything due later than next week" do
      expect(task_names(result.next_week_tasks)).to contain_exactly("下週二到期")
      expect(task_names(result.next_week_tasks)).not_to include("下個月才到期")
    end

    it "collects incomplete tasks with no planned date into 未定完成日 rather than dropping them" do
      expect(task_names(result.undated_tasks)).to contain_exactly("還沒排期")
    end

    it "sorts 逾期 by planned date ascending (most overdue first)" do
      expect(task_names(result.overdue_tasks)).to eq([ "很久以前就該完成", "本週一到期還沒完成" ])
    end

    it "groups tasks by project name" do
      expect(result.overdue_tasks.keys).to eq([ "AG 亞炬" ])
      expect(result.next_week_tasks.keys).to eq([ "Virtuous HRM" ])
    end

    it "lists each task in at most one bucket" do
      all = [ result.overdue_tasks, result.this_week_due_tasks, result.this_week_completed_tasks,
              result.next_week_tasks, result.undated_tasks ].flat_map { |g| task_names(g) }

      expect(all).to eq(all.uniq)
    end
  end

  describe "組內排序" do
    let(:progress_rows) do
      [
        progress_header,
        # 同一天到期的兩筆刻意讓「後出現的」排序在前，確認排序鍵包含任務名稱而不是依原始列順序
        [ "AG 亞炬", "B 同一天到期", "未完成", "王贊勛", "2026/09/20", "", "", "功能" ],
        [ "AG 亞炬", "A 同一天到期", "未完成", "王贊勛", "2026/09/20", "", "", "功能" ],
        [ "AG 亞炬", "更早到期", "未完成", "王贊勛", "2026/09/18", "", "", "功能" ],
        # 這兩筆的預計完成日順序與實際完成日相反，用來分辨「本週已完成」排的是哪一個日期
        [ "AG 亞炬", "週一做完", "完成", "王贊勛", "2026/09/30", "2026/09/14", "", "功能" ],
        [ "AG 亞炬", "週四做完", "完成", "王贊勛", "2026/09/01", "2026/09/17", "", "功能" ]
      ]
    end

    it "sorts by planned completion date ascending, then by task name" do
      expect(task_names(result.this_week_due_tasks))
        .to eq([ "更早到期", "A 同一天到期", "B 同一天到期" ])
    end

    it "sorts 本週已完成 by ACTUAL completion date — the PM reports what got done on which day" do
      expect(task_names(result.this_week_completed_tasks)).to eq([ "週一做完", "週四做完" ])
    end
  end

  describe "306 議題的週別歸屬" do
    it "puts unresolved issues past their due date into 逾期" do
      expect(issue_ids(result.overdue_issues)).to contain_exactly("101")
    end

    it "treats an issue due today as this week, not overdue" do
      expect(issue_ids(result.this_week_issues)).to include("102")
      expect(issue_ids(result.overdue_issues)).not_to include("102")
    end

    it "includes SLA-derived due dates and flags them as estimated" do
      sla_issue = result.this_week_issues.values.flatten.find { |i| i[:issue_id] == "105" }

      expect(sla_issue[:effective_due_date]).to eq(Date.new(2026, 9, 19))
      expect(sla_issue[:due_date_estimated]).to be(true)
    end

    it "does not flag sheet-provided due dates as estimated" do
      issue = result.this_week_issues.values.flatten.find { |i| i[:issue_id] == "102" }

      expect(issue[:due_date_estimated]).to be(false)
    end

    it "lists next week's issues" do
      expect(issue_ids(result.next_week_issues)).to contain_exactly("103")
    end

    it "excludes resolved issues from every bucket (no reliable close date to report on)" do
      all = [ result.overdue_issues, result.this_week_issues, result.next_week_issues ]
              .flat_map { |g| issue_ids(g) }

      expect(all).not_to include("104")
    end

    it "counts issues with neither a due date nor an applicable SLA instead of listing them" do
      expect(result.undated_issue_count).to eq(1)
    end
  end

  describe "306 到期日超過下週" do
    let(:issue_rows) do
      [
        issue_header,
        [ "201", "下下週才到期", "Complaint", "Bug", "新建立", "王贊勛", "2026/09/25", "2026/10/05", "1", "", "AG 亞炬", "0" ]
      ]
    end

    it "leaves it out of every bucket without counting it as 未定到期日" do
      listed = issue_ids(result.overdue_issues) + issue_ids(result.this_week_issues) +
               issue_ids(result.next_week_issues)

      expect(listed).to be_empty
      expect(result.undated_issue_count).to eq(0)
    end
  end

  describe "階段追蹤" do
    it "includes unfinished stages that are overdue or fall in this/next week, tagged by bucket" do
      expect(result.phase_items.map { |i| [ i[:issue_id], i[:bucket] ] })
        .to eq([ [ "9001", :overdue ], [ "9002", :next_week ] ])
    end

    it "carries the stage reason so the PM can explain the delay" do
      expect(result.phase_items.first[:reason]).to eq("等客戶回覆")
    end

    it "excludes finished stages" do
      expect(result.phase_items.map { |i| i[:issue_id] }).not_to include("9003")
    end
  end

  describe "專案篩選" do
    let(:result) { described_class.result(project: "AG 亞炬") }

    it "limits 305 tasks to the selected project" do
      expect(result.overdue_tasks.keys).to eq([ "AG 亞炬" ])
      expect(result.this_week_completed_tasks).to be_empty
    end

    it "limits 306 issues to the selected project" do
      expect(issue_ids(result.overdue_issues)).to contain_exactly("101")
      expect(issue_ids(result.this_week_issues)).to contain_exactly("105")
    end

    it "leaves phase tracking untouched — its project codes cannot be matched to 305 names" do
      expect(result.phase_items.map { |i| i[:issue_id] }).to eq(%w[9001 9002])
    end

    it "still reports the full project list for the filter dropdown" do
      expect(result.project_names).to eq([ "AG 亞炬", "Virtuous HRM" ])
    end
  end

  describe "專案篩選的雙向包含比對" do
    # 306 的專案欄位與 305 的專案名稱不保證同一套寫法，故採雙向包含；兩邊完全對不起來的
    # 議題寧可不顯示，也不要把別的專案的客訴算進這個專案的週報。
    let(:issue_rows) do
      [
        issue_header,
        [ "301", "306 只寫簡稱", "Complaint", "Bug", "新建立", "王贊勛", "2026/08/20", "2026/09/01", "2", "", "亞炬", "1" ],
        [ "302", "完全對不上的專案", "Complaint", "Bug", "新建立", "王贊勛", "2026/08/20", "2026/09/01", "2", "", "別家公司", "1" ]
      ]
    end
    let(:result) { described_class.result(project: "AG 亞炬") }

    it "matches a 306 project name contained in the selected 305 name, and drops the unmatchable one" do
      expect(issue_ids(result.overdue_issues)).to contain_exactly("301")
    end
  end

  describe "資料來源降級" do
    it "fails the whole request when 305 fails (no tasks means no weekly report)" do
      error = Google::Apis::ClientError.new("Forbidden")
      allow(error).to receive(:status_code).and_return(403)
      allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_raise(error)

      expect(result).not_to be_success
      expect(result.failure_code).to eq(:access_denied)
    end

    it "still renders 305 and phase tracking when 306 fails" do
      allow(IssueSheetsClient).to receive(:fetch_issue_rows)
        .and_raise(Google::Apis::RateLimitError.new("Rate limit exceeded"))

      expect(result).to be_success
      expect(result.issues_unavailable).to be(true)
      expect(result.overdue_issues).to be_empty
      expect(task_names(result.overdue_tasks)).to include("很久以前就該完成")
      expect(result.phase_items).not_to be_empty
    end

    it "still renders 305 and 306 when phase tracking fails" do
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows)
        .and_raise(Google::Apis::RateLimitError.new("Rate limit exceeded"))

      expect(result).to be_success
      expect(result.phase_tracking_unavailable).to be(true)
      expect(result.phase_items).to be_empty
      expect(issue_ids(result.overdue_issues)).to contain_exactly("101")
    end
  end
end
