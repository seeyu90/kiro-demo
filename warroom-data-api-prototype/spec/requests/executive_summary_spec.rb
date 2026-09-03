require "rails_helper"

RSpec.describe "ExecutiveSummary", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    travel_to(Date.new(2026, 9, 1)) { example.run }
  end

  let(:roster_header) { %w[專案 專案縮寫 狀態 比例 生效月份 失效月份 負責RD 客戶 PM 307對應專案] }
  let(:roster_rows) do
    [
      roster_header,
      [ "AG 亞炬", "亞炬 Platform", "維護", "40%", "2026/01", "", "王贊勛", "亞炬", "呂俐禎", "亞炬 PMS" ],
      [ "Virtuous HRM", "HRM", "維護", "40%", "2026/01", "", "黃靖益", "AMAS", "楊欣翰", "" ]
    ]
  end

  let(:progress_header) { [ "專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延誤", "類型" ] }
  let(:progress_rows) do
    [
      progress_header,
      # 逾期：預計完成日期早於今天（2026/09/01），狀態未完成 → 紅燈
      [ "AG 亞炬", "API 效能優化", "未完成", "王贊勛", "2026/08/01", "", "31", "功能" ],
      [ "Virtuous HRM", "請假模組串接", "完成", "黃靖益", "2026/07/06", "2026/07/08", "2", "功能" ]
    ]
  end

  let(:burndown_header) { %w[剩餘人時 專案 議題 人員 議題ID 開案日期 完成日期 狀態 預估人時] }
  let(:burndown_rows) { [ burndown_header + [ "08/25" ] ] }

  let(:month_kpi_rows) do
    [
      %w[year_month 客訴 測試 總Bug 攔截率 完成數 未結案 平均天數 SLA達標率 Top3],
      [ "2026-08", "3", "2", "5", "40", "4", "1", "2.0", "80", "" ]
    ]
  end
  let(:daily_kpi_rows) { [ %w[日期 客訴 測試 其他 總計] ] }
  let(:issue_rows) { [ %w[issue_id subject type tracker status assigned_to start_date due_date work_days sheet_name project] ] }

  let(:profile_header) { %w[Github/Notion Redmine\ 專案 303\ 專案 客戶 PM 狀態] }
  let(:profile_rows) { [ profile_header, [ "HRM", "Virtuous HRM", "HRM", "AMAS", "楊欣翰", "維護" ] ] }

  def record_row(project:, issue_id:, stage:, planned:, actual:, status: "完成", reason: "", issue_name: "")
    [ project, issue_id, issue_name, stage, planned, actual, status, reason,
      "#{project}|#{issue_id}|#{stage}", planned.to_s[0, 4] ]
  end

  let(:phase_rows) do
    [ record_row(project: "HRM", issue_id: "9001", issue_name: "報表模組", stage: "開發",
                  planned: "2026-08-01", actual: nil, status: "延誤未完成") ]
  end

  before do
    allow(ProjectRosterSheetsClient).to receive(:fetch_rows).and_return(roster_rows)
    allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return(progress_rows)
    allow(BurndownSheetsClient).to receive(:fetch_rows).and_return(burndown_rows)
    allow(IssueSheetsClient).to receive(:fetch_month_kpi_rows).and_return(month_kpi_rows)
    allow(IssueSheetsClient).to receive(:fetch_daily_kpi_rows).and_return(daily_kpi_rows)
    allow(IssueSheetsClient).to receive(:fetch_issue_rows).and_return(issue_rows)
    allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_return(phase_rows)
    allow(ProjectProfilesSheetsClient).to receive(:fetch_rows).and_return(profile_rows)
  end

  describe "GET /executive_summary" do
    before { get "/executive_summary" }

    it "returns HTTP 200" do
      expect(response).to have_http_status(200)
    end

    it "shows portfolio KPI counts (1 red, 1 green) in the summary bar" do
      expect(response.body).to include("summary-bar")
      expect(response.body).to include("🔴 需立即關注")
      expect(response.body).to include("🟢 正常")
    end

    it "shows this month's SLA rate and complaint count from 306" do
      expect(response.body).to include("80.0%")
    end

    it "lists the overdue project expanded (critical) and shows its overdue task detail" do
      expect(response.body).to include("AG 亞炬")
      expect(response.body).to include("逾期任務")
      expect(response.body).to include("API 效能優化")
    end

    it "renders the phase-tracking exceptions as a separate section, not merged into project cards" do
      expect(response.body).to include("階段追蹤例外")
      expect(response.body).to include("報表模組")
      expect(response.body).to include("延誤未完成")
    end

    it "links each project card to its raw 305 progress and project history detail pages" do
      expect(response.body).to include('href="/dashboard?project=AG+%E4%BA%9E%E7%82%AC"')
      expect(response.body).to include('href="/project_history?project_name=AG+%E4%BA%9E%E7%82%AC"')
    end

    # 這頁是彙總儀表板，點進細節頁不該弄丟目前這頁的捲動位置／已展開的卡片狀態，故所有
    # 「原始資料」連結都要另開分頁（見使用者回饋：應該要用另開分頁）。
    it "opens every raw-data link in a new tab instead of navigating away from the summary" do
      expect(response.body.scan('class="raw-data-link"').size).to be > 0
      expect(response.body.scan(/class="raw-data-link"[^>]*target="_blank"/).size)
        .to eq(response.body.scan('class="raw-data-link"').size)
      expect(response.body.scan(/class="stat-item[^"]*"[^>]*target="_blank"/).size).to be >= 5
    end

    it "links KPI tiles to the pages they summarize (overdue tasks, issues, phase tracking)" do
      expect(response.body).to include('href="/dashboard?scope=overdue"')
      expect(response.body).to include('href="/issues"')
      expect(response.body).to include('href="/project_phase_tracking"')
    end

    # 目的頁預設「當年度＋未完成」；連結不清空這兩個篩選（不加 status=/year=），避免使用者
    # 點過去看到全部歷史、所有狀態塞爆頁面（見 _kpi_strip.html.erb／_phase_exceptions.html.erb
    # 的取捨說明）。
    it "does not blank out the phase-tracking page's default year/status filters via the link (would dump its entire history)" do
      expect(response.body).not_to match(%r{href="/project_phase_tracking\?[^"]*status=(&|")})
      expect(response.body).not_to match(%r{href="/project_phase_tracking\?[^"]*year=(&|")})
    end

    it "links each phase-exception customer group to that customer's filtered phase-tracking page" do
      expect(response.body).to include('href="/project_phase_tracking?customer=AMAS')
    end
  end

  describe "GET /executive_summary — 上週總結" do
    # travel_to 固定 2026-09-01（週二），上週（週一～週日）＝ 2026-08-24～2026-08-30。
    let(:progress_rows) do
      [
        progress_header,
        [ "AG 亞炬", "API 效能優化", "未完成", "王贊勛", "2026/08/01", "", "31", "功能" ],
        [ "Virtuous HRM", "上週完成的任務", "完成", "黃靖益", "2026/08/25", "2026/08/26", "", "功能" ],
        [ "Virtuous HRM", "更早完成的任務", "完成", "黃靖益", "2026/07/06", "2026/07/08", "", "功能" ]
      ]
    end
    let(:phase_rows) do
      [
        record_row(project: "HRM", issue_id: "9001", issue_name: "報表模組", stage: "開發",
                    planned: "2026-08-01", actual: nil, status: "延誤未完成"),
        record_row(project: "HRM", issue_id: "9002", issue_name: "上週完成的階段", stage: "開案",
                    planned: "2026-08-20", actual: "2026-08-27", status: "完成")
      ]
    end
    let(:daily_kpi_rows) do
      [
        %w[日期 客訴 測試 其他 總計],
        [ "2026-08-25", "2", "0", "0", "2" ],
        [ "2026-08-15", "9", "0", "0", "9" ]
      ]
    end

    before { get "/executive_summary" }

    it "sums 306 daily complaint counts that fall inside last week's range into 客訴數" do
      section = last_week_section(response.body)
      expect(section).to match(%r{<span class="stat-value">2</span>\s*<span class="stat-label">客訴數</span>})
    end

    def last_week_section(body)
      body[%r{<h2>上週總結.*?</section>}m]
    end

    it "shows a completed-last-week task/stage count, scoped to last week's Monday-Sunday range" do
      section = last_week_section(response.body)
      expect(section).to include("已完成任務")
      expect(section).to include("已完成階段")
    end

    it "counts only the task completed inside last week's range, excluding the one completed earlier" do
      section = last_week_section(response.body)
      expect(section).to match(%r{<span class="stat-value">1</span>\s*<span class="stat-label">已完成任務</span>})
    end

    it "does not dump individual completed task/stage names — only the counts (執行摘要不需要逐筆清單)" do
      section = last_week_section(response.body)
      expect(section).not_to include("上週完成的任務")
      expect(section).not_to include("上週完成的階段")
    end

    it "does not leak internal spec numbers (305/306/307) into the user-facing copy" do
      section = last_week_section(response.body)
      expect(section).not_to match(/30[567]/)
    end
  end

  describe "GET /executive_summary — 階段追蹤例外依客戶彙總" do
    let(:phase_rows) do
      [
        record_row(project: "HRM", issue_id: "9001", issue_name: "報表模組", stage: "開發",
                    planned: "2026-08-01", actual: nil, status: "延誤未完成"),
        record_row(project: "HRM", issue_id: "9002", issue_name: "假單模組", stage: "測試",
                    planned: "2026-08-05", actual: nil, status: "未完成"),
        record_row(project: "HRM", issue_id: "9003", issue_name: "刻意擱置的模組", stage: "測試",
                    planned: "2026-08-05", actual: nil, status: "暫緩"),
        record_row(project: "HRM", issue_id: "9004", issue_name: "很久以前卡住的模組", stage: "測試",
                    planned: "2020-01-01", actual: nil, status: "未完成")
      ]
    end

    before { get "/executive_summary" }

    it "groups both recent needs-attention exceptions under the same customer (AMAS) into a single count" do
      expect(response.body).to include("延誤／未完成 2")
    end

    it "does not render 暫緩 items at all (deliberately paused, not something the CEO needs to see)" do
      expect(response.body).not_to include("刻意擱置的模組")
    end

    it "does not render a needs-attention item whose current-stage planned date is older than 6 months" do
      expect(response.body).not_to include("很久以前卡住的模組")
    end
  end

  describe "GET /executive_summary when 305 (the core data source) fails" do
    before do
      error = Google::Apis::ClientError.new("Forbidden")
      allow(error).to receive(:status_code).and_return(403)
      allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_raise(error)
      get "/executive_summary"
    end

    it "returns HTTP 200 and shows the error message instead of raising" do
      expect(response).to have_http_status(200)
      expect(response.body).to include("錯誤")
      expect(response.body).to include("資料來源存取權限不足")
    end
  end

  describe "GET /executive_summary when phase tracking fails" do
    before do
      error = Google::Apis::ClientError.new("Forbidden")
      allow(error).to receive(:status_code).and_return(403)
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_raise(error)
      get "/executive_summary"
    end

    it "still renders the page successfully with a data-source warning, not an error page" do
      expect(response).to have_http_status(200)
      expect(response.body).not_to include("<strong>錯誤：</strong>")
      expect(response.body).to include("專案階段追蹤")
      expect(response.body).to include("AG 亞炬")
    end
  end
end
