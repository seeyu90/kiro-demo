require "rails_helper"

RSpec.describe "Burndown", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    travel_to(Date.new(2026, 8, 14)) { example.run }
  end

  def issue_series_section(body)
    body[%r{<h2>議題燃盡圖</h2>.*?</section>}m]
  end

  let(:fixed_header) { %w[剩餘人時 專案 議題 人員 議題ID 開案日期 完成日期 預估人時] }
  let(:header) { fixed_header + [ "08/10", "08/03" ] }

  let(:burndown_rows) do
    [
      header,
      [ "2", "AG 亞炬", "議題A", "王贊勛", "1001", "2026/08/01", "2026/08/15", "10", "3", "2" ],
      [ "1", "AG 亞炬", "議題B", "蔡秉逸", "1002", "2026/08/01", "2026/08/20", "8", "1", "1" ],
      [ "0", "Virtuous HRM", "議題C", "王贊勛", "1003", "2026/08/01", "2026/08/10", "5", "2", "3" ]
    ]
  end

  before { allow(BurndownSheetsClient).to receive(:fetch_rows).and_return(burndown_rows) }

  describe "GET /burndown with no filters" do
    before { get "/burndown" }

    it "returns HTTP 200" do
      expect(response).to have_http_status(200)
    end

    it "shows a burndown chart for every issue" do
      expect(response.body).to include("議題A").and include("議題B").and include("議題C")
    end

    it "lists both projects and both assignees in the filter dropdowns" do
      expect(response.body).to include('value="AG 亞炬"').and include('value="Virtuous HRM"')
      expect(response.body).to include('value="王贊勛"').and include('value="蔡秉逸"')
    end
  end

  describe "GET /burndown?project=... (project filter only)" do
    before { get "/burndown", params: { project: "AG 亞炬" } }

    it "shows only the issues under the selected project" do
      section = issue_series_section(response.body)
      expect(section).to include("議題A")
      expect(section).to include("議題B")
      expect(section).not_to include("議題C")
    end
  end

  describe "GET /burndown?assignee=... (assignee filter only)" do
    before { get "/burndown", params: { assignee: "王贊勛" } }

    it "shows only the issues assigned to the selected person" do
      section = issue_series_section(response.body)
      expect(section).to include("議題A")
      expect(section).to include("議題C")
      expect(section).not_to include("議題B")
    end
  end

  describe "GET /burndown?project=...&assignee=... (both filters, intersection)" do
    before { get "/burndown", params: { project: "AG 亞炬", assignee: "王贊勛" } }

    it "shows only issues matching both filters (需求 4.4)" do
      section = issue_series_section(response.body)
      expect(section).to include("議題A")
      expect(section).not_to include("議題B")
      expect(section).not_to include("議題C")
    end
  end

  describe "GET /burndown when the sheet has no data rows" do
    before do
      allow(BurndownSheetsClient).to receive(:fetch_rows).and_return([ header ])
      get "/burndown"
    end

    it "shows the empty state for the issue section" do
      expect(issue_series_section(response.body)).to include("目前無符合條件的議題")
    end
  end

  describe "GET /burndown when BurndownSheetsClient raises an error" do
    before do
      error = Google::Apis::ClientError.new("Forbidden")
      allow(error).to receive(:status_code).and_return(403)
      allow(BurndownSheetsClient).to receive(:fetch_rows).and_raise(error)
      get "/burndown"
    end

    it "returns HTTP 200 and shows the error message instead of raising" do
      expect(response).to have_http_status(200)
      expect(response.body).to include("錯誤")
      expect(response.body).to include("資料來源存取權限不足")
    end

    it "does not render any filter dropdown options or charts" do
      expect(response.body).not_to include("議題燃盡圖")
    end
  end
end
