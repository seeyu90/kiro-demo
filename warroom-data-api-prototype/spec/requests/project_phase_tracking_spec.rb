require "rails_helper"

RSpec.describe "ProjectPhaseTracking", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    travel_to(Date.new(2026, 8, 25)) { example.run }
  end

  def overview_section(body)
    body[%r{<section class="issue-section">.*}m]
  end

  def record_row(project:, issue_id:, stage:, planned:, actual:, status: "完成", reason: "", issue_name: "")
    [ project, issue_id, issue_name, stage, planned, actual, status, reason,
      "#{project}|#{issue_id}|#{stage}", planned.to_s[0, 4] ]
  end

  let(:profile_header) { %w[Github/Notion Redmine\ 專案 303\ 專案 客戶 PM 狀態] }
  let(:profile_rows) do
    [
      profile_header,
      [ "HRM", "Virtuous HRM", "HRM", "AMAS", "楊欣翰", "維護" ],
      [ "JZNPMS", "舊振南", "JZNPMS", "舊振南", "呂俐禎", "維護" ]
    ]
  end

  # HRM/v2.1調整：2026 年、目前狀態未完成（測試階段有主要記錄但未完成），符合預設篩選
  # （年度＝今年、狀態＝未完成）會直接列出。
  # JZNPMS/4548（現場報工）：2026 年、目前狀態暫緩，預設篩選（狀態＝未完成）不會列出，
  # 用來驗證「暫緩」不等於「未完成」（見 requirements.md 前置條件）且能被狀態篩選挑出來。
  let(:phase_rows) do
    [
      record_row(project: "HRM", issue_id: "v2.1調整", stage: "開案", planned: "2026-06-05", actual: "2026-06-05"),
      record_row(project: "HRM", issue_id: "v2.1調整", stage: "測試", planned: "2026-07-15", actual: nil, status: "未完成"),
      record_row(project: "JZNPMS", issue_id: "4548", issue_name: "現場報工", stage: "開案",
                  planned: "2026-01-20", actual: "2026-01-20"),
      record_row(project: "JZNPMS", issue_id: "4548", issue_name: "現場報工", stage: "開發",
                  planned: "2026-02-01", actual: nil, status: "暫緩")
    ]
  end

  before do
    allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_return(phase_rows)
    allow(ProjectProfilesSheetsClient).to receive(:fetch_rows).and_return(profile_rows)
  end

  describe "GET /project_phase_tracking (overview)" do
    before { get "/project_phase_tracking" }

    it "returns HTTP 200" do
      expect(response).to have_http_status(200)
    end

    it "marks the entry-page breadcrumb link to break out of the turbo frame" do
      expect(response.body).to match(%r{<a[^>]*data-turbo-frame="_top"[^>]*>入口頁</a>})
    end

    it "lists the card as an expandable project card, joined with profile customer/pm" do
      expect(response.body).to include("HRM").and include("v2.1調整").and include("AMAS").and include("楊欣翰")
      expect(response.body).to include("project-card-summary")
    end

    it "shows the issue's own stage-derived status, not the profile sheet's 維護-style project status" do
      section = overview_section(response.body)
      expect(section).to include("未完成")
      expect(section).not_to include("維護")
    end
  end

  describe "GET /project_phase_tracking — 預設篩選（年度＝今年、狀態＝未完成）" do
    it "excludes a card whose status is 暫緩 (paused is not incomplete)" do
      get "/project_phase_tracking"

      section = overview_section(response.body)
      expect(section).to include("v2.1調整")
      expect(section).not_to include("4548")
    end

    it "shows the 暫緩 card when the status filter is explicitly cleared to 全部狀態" do
      get "/project_phase_tracking", params: { status: "" }

      section = overview_section(response.body)
      expect(section).to include("v2.1調整")
      expect(section).to include("4548")
    end

    it "excludes a card outside the default year once a stage record from a different year exists" do
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_return(
        phase_rows + [ record_row(project: "AGWMS", issue_id: "v1開發", stage: "開案",
                                    planned: "2025-11-01", actual: nil, status: "未完成") ]
      )

      get "/project_phase_tracking"

      expect(overview_section(response.body)).not_to include("AGWMS")
    end

    it "shows a card from a different year once 全部年度 is selected explicitly" do
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_return(
        phase_rows + [ record_row(project: "AGWMS", issue_id: "v1開發", stage: "開案",
                                    planned: "2025-11-01", actual: nil, status: "未完成") ]
      )

      get "/project_phase_tracking", params: { year: "" }

      expect(overview_section(response.body)).to include("AGWMS")
    end
  end

  describe "GET /project_phase_tracking?customer=...&pm=... (filter)" do
    it "shows only the matching card" do
      get "/project_phase_tracking", params: { status: "", customer: "AMAS" }

      section = overview_section(response.body)
      expect(section).to include("v2.1調整")
      expect(section).not_to include("4548")
    end

    it "shows the empty state when the filter matches nothing" do
      get "/project_phase_tracking", params: { status: "", customer: "AMAS", pm: "呂俐禎" }

      expect(overview_section(response.body)).to include("目前無符合條件的專案")
    end
  end

  describe "GET /project_phase_tracking?q=... (搜尋議題名稱／ID)" do
    it "matches by issue_name even though the query text isn't the issue_id" do
      get "/project_phase_tracking", params: { status: "", q: "現場" }

      section = overview_section(response.body)
      expect(section).to include("4548")
      expect(section).not_to include("v2.1調整")
    end

    it "matches by issue_id" do
      get "/project_phase_tracking", params: { status: "", q: "4548" }

      expect(overview_section(response.body)).to include("4548")
    end
  end

  describe "GET /project_phase_tracking — 固定依預計完成日期排序" do
    it "lists cards ordered by planned_completion_date ascending regardless of sheet row order" do
      get "/project_phase_tracking", params: { status: "" }

      section = overview_section(response.body)
      # JZNPMS/4548 預計完成（發布階段缺紀錄，退回最晚 planned_date＝2026-02-01）早於
      # HRM/v2.1調整（發布階段缺紀錄，退回最晚 planned_date＝2026-07-15）。
      expect(section.index("4548")).to be < section.index("v2.1調整")
    end
  end

  describe "GET /project_phase_tracking?view=gantt" do
    it "renders an SVG dual-track gantt chart instead of the card list" do
      get "/project_phase_tracking", params: { view: "gantt" }

      expect(response.body).to include('class="gantt-svg"')
      expect(response.body).not_to include("project-card-summary")
    end

    it "renders a legend explaining the fixed per-stage colors" do
      get "/project_phase_tracking", params: { view: "gantt" }

      expect(response.body).to include("gantt-legend")
      expect(response.body).to include("上軌").and include("下軌")
    end

    it "does not print the stage name as text on the bars, only via hover title" do
      get "/project_phase_tracking", params: { view: "gantt" }

      expect(response.body).not_to include("gantt-stage-label")
      expect(response.body).to match(%r{<rect[^>]*class="gantt-stage-block[^>]*>\s*<title>})
    end
  end

  describe "GET /project_phase_tracking when the core phase-records source fails" do
    before do
      error = Google::Apis::ClientError.new("Forbidden")
      allow(error).to receive(:status_code).and_return(403)
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_raise(error)
      get "/project_phase_tracking"
    end

    it "returns HTTP 200 and shows the error message instead of raising" do
      expect(response).to have_http_status(200)
      expect(response.body).to include("錯誤")
      expect(response.body).to include("資料來源存取權限不足")
    end

    it "does not render the filter form" do
      frame = response.body[%r{<turbo-frame id="project-phase-tracking-content">.*?</turbo-frame>}m]
      expect(frame).not_to include("apply-filters-btn")
    end
  end

  describe "GET /project_phase_tracking when only the profile (專案) source fails" do
    before do
      error = Google::Apis::ClientError.new("Forbidden")
      allow(error).to receive(:status_code).and_return(403)
      allow(ProjectProfilesSheetsClient).to receive(:fetch_rows).and_raise(error)
      get "/project_phase_tracking", params: { status: "" }
    end

    it "still renders the overview successfully (degrades gracefully) instead of showing an error page" do
      expect(response).to have_http_status(200)
      expect(response.body).not_to include("錯誤：")
      expect(response.body).to include("v2.1調整")
    end

    it "shows customer/pm as — for every card since the profile sheet couldn't be read" do
      expect(response.body).to include("客戶／PM 對照資料")
    end
  end
end
