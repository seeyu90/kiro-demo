require "rails_helper"

RSpec.describe "Api::IssueDashboard", type: :request do
  let(:month_kpi_rows) do
    [
      %w[year_month 客訴 測試 總Bug 攔截率 完成數 未結案 平均天數 SLA達標率 Top3],
      ["2026-08", "15", "9", "24", "37.5", "6", "3", "3.1", "25", "王贊勛:8"]
    ]
  end

  let(:daily_kpi_rows) do
    [
      %w[日期 客訴 測試 其他 總計],
      ["2026-08-13", "0", "1", "0", "1"]
    ]
  end

  let(:issue_rows) do
    [
      %w[issue_id subject type tracker status assigned_to start_date due_date work_days sheet_name project],
      ["4547", "未匯入行事曆", "Complaint", "臭蟲", "已結束", "黃靖益",
       "2026/1/2", "2026/1/6", "3", "raw_2026", "Virtuous HRM"],
      ["5165", "白名單申請時間錯誤", "TestingBug", "臭蟲", "新建立", "蔡秉逸",
       "2026/8/12", "", "", "raw_2026", "Virtuous HRM"]
    ]
  end

  def stub_valid_client
    allow(IssueSheetsClient).to receive(:fetch_month_kpi_rows).and_return(month_kpi_rows)
    allow(IssueSheetsClient).to receive(:fetch_daily_kpi_rows).and_return(daily_kpi_rows)
    allow(IssueSheetsClient).to receive(:fetch_issue_rows).and_return(issue_rows)
  end

  describe "GET /api/issue_dashboard" do
    before do
      stub_valid_client
      get "/api/issue_dashboard"
    end

    it "returns HTTP 200" do
      expect(response).to have_http_status(200)
    end

    it "returns JSON with the four expected top-level keys" do
      json = JSON.parse(response.body)

      expect(json.keys).to match_array(%w[month_kpi daily_kpi issues project_breakdown])
    end

    it "serializes month_kpi via MonthKpiBlueprint" do
      json = JSON.parse(response.body)

      expect(json["month_kpi"]).to eq([
        {
          "year_month" => "2026-08", "complaint" => 15, "testing" => 9, "total_bug" => 24,
          "block_rate" => 37.5, "completed" => 6, "unresolved" => 3, "avg_days" => 3.1, "sla_rate" => 25.0
        }
      ])
    end

    it "serializes daily_kpi via DailyKpiBlueprint" do
      json = JSON.parse(response.body)

      expect(json["daily_kpi"]).to eq([
        { "date" => "2026-08-13", "complaint" => 0, "testing" => 1, "other" => 0, "total" => 1 }
      ])
    end

    it "serializes issues via IssueBlueprint, without attribution or sheet_name" do
      json = JSON.parse(response.body)

      expect(json["issues"].map { |i| i["issue_id"] }).to eq(["4547", "5165"])
      json["issues"].each do |issue|
        expect(issue.keys).to match_array(
          %w[issue_id subject type tracker status assigned_to start_date due_date work_days project]
        )
      end
    end

    it "serializes project_breakdown via ProjectBreakdownBlueprint" do
      json = JSON.parse(response.body)

      expect(json["project_breakdown"]).to eq([
        { "project" => "Virtuous HRM", "complaint" => 1, "testing" => 1, "other" => 0, "total" => 2 }
      ])
    end
  end

  describe "GET /api/issue_dashboard when IssueSheetsClient raises ClientError (404)" do
    before do
      stub_valid_client
      error = Google::Apis::ClientError.new("Not Found")
      allow(error).to receive(:status_code).and_return(404)
      allow(IssueSheetsClient).to receive(:fetch_month_kpi_rows).and_raise(error)
      get "/api/issue_dashboard"
    end

    it "returns HTTP 404 with the unified error format" do
      expect(response).to have_http_status(404)

      json = JSON.parse(response.body)
      expect(json["error"]["code"]).to eq("sheet_not_found")
      expect(json["error"]).to have_key("message")
    end
  end

  describe "GET /api/issue_dashboard when IssueSheetsClient raises ClientError (403)" do
    before do
      stub_valid_client
      error = Google::Apis::ClientError.new("Forbidden")
      allow(error).to receive(:status_code).and_return(403)
      allow(IssueSheetsClient).to receive(:fetch_daily_kpi_rows).and_raise(error)
      get "/api/issue_dashboard"
    end

    it "returns HTTP 403 with the unified error format" do
      expect(response).to have_http_status(403)

      json = JSON.parse(response.body)
      expect(json["error"]["code"]).to eq("access_denied")
    end
  end

  describe "GET /api/issue_dashboard when IssueSheetsClient raises StandardError" do
    before do
      stub_valid_client
      allow(IssueSheetsClient).to receive(:fetch_issue_rows).and_raise(StandardError.new("憑證載入失敗"))
      get "/api/issue_dashboard"
    end

    it "returns HTTP 500 with the unified error format" do
      expect(response).to have_http_status(500)

      json = JSON.parse(response.body)
      expect(json["error"]["code"]).to eq("internal_error")
      expect(json["error"]).to have_key("message")
    end
  end
end
