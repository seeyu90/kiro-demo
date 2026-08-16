require "rails_helper"

RSpec.describe "ProjectHistory", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    travel_to(Date.new(2026, 8, 16)) { example.run }
  end

  def overview_section(body)
    body[%r{<section class="issue-section">.*}m]
  end

  let(:roster_header) { %w[專案 專案縮寫 狀態 比例 生效月份 失效月份 負責RD 客戶 PM] }
  let(:roster_rows) do
    [
      roster_header,
      [ "AG 亞炬", "亞炬 Platform", "維護", "40%", "2026/01", "", "王贊勛", "亞炬", "呂俐禎" ],
      [ "Virtuous HRM", "HRM", "維護", "40%", "2026/01", "", "黃靖益", "AMAS", "楊欣翰" ]
    ]
  end

  let(:progress_header) { [ "專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延誤", "類型" ] }
  let(:progress_rows) do
    [
      progress_header,
      [ "AG 亞炬", "API 效能優化", "未完成", "王贊勛", "2026/08/22", "", "", "功能" ],
      [ "Virtuous HRM", "請假模組串接", "完成", "黃靖益", "2026/07/06", "2026/07/08", "2", "功能" ]
    ]
  end

  let(:month_kpi_rows) { [ %w[year_month 客訴 測試 總Bug 攔截率 完成數 未結案 平均天數 SLA達標率 Top3] ] }
  let(:daily_kpi_rows) { [ %w[日期 客訴 測試 其他 總計] ] }
  let(:issue_rows) do
    [
      %w[issue_id subject type tracker status assigned_to start_date due_date work_days sheet_name project],
      [ "5171", "廠區用電監測告警延遲", "Complaint", "臭蟲", "新建立", "黃靖益",
        "2026/08/13", "", "", "raw_2026", "AG 亞炬" ],
      [ "5188", "報表匯出欄位順序錯誤", "TestingBug", "臭蟲", "已結束", "蔡秉逸",
        "2026/07/29", "", "", "raw_2026", "AG 亞炬" ]
    ]
  end

  let(:burndown_header) { %w[剩餘人時 專案 議題 人員 議題ID 開案日期 完成日期 狀態 預估人時] }
  let(:burndown_rows) do
    [
      burndown_header + [ "08/12", "08/05" ],
      [ "8", "AG 亞炬", "API 效能優化", "王贊勛", "1001", "2026/07/08", "2026/08/22", "執行中", "40", "1", "1" ]
    ]
  end

  before do
    allow(ProjectRosterSheetsClient).to receive(:fetch_rows).and_return(roster_rows)
    allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return(progress_rows)
    allow(IssueSheetsClient).to receive(:fetch_month_kpi_rows).and_return(month_kpi_rows)
    allow(IssueSheetsClient).to receive(:fetch_daily_kpi_rows).and_return(daily_kpi_rows)
    allow(IssueSheetsClient).to receive(:fetch_issue_rows).and_return(issue_rows)
    allow(BurndownSheetsClient).to receive(:fetch_rows).and_return(burndown_rows)
  end

  describe "GET /project_history (overview)" do
    before { get "/project_history" }

    it "returns HTTP 200" do
      expect(response).to have_http_status(200)
    end

    it "lists both projects joined with roster customer/pm" do
      expect(response.body).to include("AG 亞炬").and include("亞炬").and include("呂俐禎")
      expect(response.body).to include("Virtuous HRM").and include("AMAS").and include("楊欣翰")
    end

    it "shows Virtuous HRM as completed (actual date) and AG 亞炬 as ongoing" do
      expect(response.body).to include("2026-07-08")
      expect(response.body).to include("進行中")
    end
  end

  describe "GET /project_history?customer=... (filter)" do
    it "shows only the matching project" do
      get "/project_history", params: { customer: "AMAS" }

      section = overview_section(response.body)
      expect(section).to include("Virtuous HRM")
      expect(section).not_to include("AG 亞炬")
    end

    it "shows the empty state when the filter matches nothing" do
      get "/project_history", params: { customer: "AMAS", pm: "呂俐禎" }

      expect(overview_section(response.body)).to include("目前無符合條件的專案")
    end
  end

  describe "GET /project_history?view=gantt" do
    it "renders an SVG gantt chart instead of the table" do
      get "/project_history", params: { view: "gantt" }

      expect(response.body).to include('class="gantt-svg"')
      expect(response.body).not_to include("<table")
    end
  end

  describe "GET /project_history?project=... (detail)" do
    before { get "/project_history", params: { project: "AG 亞炬" } }

    it "returns HTTP 200 and renders all four detail sections" do
      expect(response).to have_http_status(200)
      expect(response.body).to include("花費工時趨勢")
      expect(response.body).to include("每週進度達成率")
      expect(response.body).to include("測試問題趨勢")
      expect(response.body).to include("客訴議題狀態")
    end

    it "shows the unresolved complaint with a working Redmine link" do
      expect(response.body).to include("廠區用電監測告警延遲")
      expect(response.body).to include('href="https://redmine.amastek.com.tw/issues/5171"')
      expect(response.body).to include('target="_blank"')
    end
  end

  describe "GET /project_history?project=... when the project has no burndown/complaint data" do
    before { get "/project_history", params: { project: "Virtuous HRM" } }

    it "shows the empty-state text instead of blank sections" do
      expect(response.body).to include("所選專案無工時資料")
      expect(response.body).to include("所選專案無客訴議題")
    end
  end

  describe "GET /project_history when a core data source (305) fails" do
    before do
      error = Google::Apis::ClientError.new("Forbidden")
      allow(error).to receive(:status_code).and_return(403)
      allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_raise(error)
      get "/project_history"
    end

    it "returns HTTP 200 and shows the error message instead of raising" do
      expect(response).to have_http_status(200)
      expect(response.body).to include("錯誤")
      expect(response.body).to include("資料來源存取權限不足")
    end

    it "does not render the filter form or any data section" do
      frame = response.body[%r{<turbo-frame id="project-history-content">.*?</turbo-frame>}m]
      expect(frame).not_to include("apply-filters-btn")
      expect(frame).not_to include("<form")
    end
  end

  describe "GET /project_history when only the roster (300_員工專案) source fails" do
    before do
      error = Google::Apis::ClientError.new("Forbidden")
      allow(error).to receive(:status_code).and_return(403)
      allow(ProjectRosterSheetsClient).to receive(:fetch_rows).and_raise(error)
      get "/project_history"
    end

    # Roster 只是客戶/PM 的補充資料，不是本頁面的核心資料（305/306/307 才是），失敗時不應該
    # 擋住整頁——這是實測發現 300_員工專案跟 305/306/307 是不同試算表、不同擁有者、共用權限
    # 各自獨立設定後才改的設計（見 fetch_project_history.rb#call 的附註）。
    it "still renders the overview successfully (degrades gracefully) instead of showing an error page" do
      expect(response).to have_http_status(200)
      expect(response.body).not_to include("錯誤：")
      expect(response.body).to include("AG 亞炬").or include("Virtuous HRM")
    end

    it "shows customer/pm as — for every project since the roster couldn't be read" do
      expect(response.body).to include("—")
    end
  end
end
