require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  let(:header_row) { ["專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延誤"] }
  let(:valid_rows) do
    [
      header_row,
      ["Project Alpha", "Task Alpha 1", "已完成", "Alice", "2026/1/5", "2026/1/6", "1"],
      ["Project Beta", "Task Beta 1", "進行中", "Bob", "2026/2/10", "", ""]
    ]
  end

  before { allow(SheetsApiClient).to receive(:fetch_rows).and_return(valid_rows) }

  describe "GET /dashboard" do
    before { get "/dashboard" }

    it "returns HTTP 200" do
      expect(response).to have_http_status(200)
    end

    it "renders the project dropdown with all project names" do
      expect(response.body).to include("全部專案")
      expect(response.body).to include("Project Alpha")
      expect(response.body).to include("Project Beta")
    end

    it "renders every project's task blocks" do
      expect(response.body).to include("Task Alpha 1")
      expect(response.body).to include("Task Beta 1")
    end
  end

  describe "GET /dashboard?project=XXX" do
    let(:selected_project) { "Project Alpha" }

    before { get "/dashboard", params: { project: selected_project } }

    it "returns HTTP 200" do
      expect(response).to have_http_status(200)
    end

    it "renders only the selected project's task blocks" do
      expect(response.body).to include("Task Alpha 1")
      expect(response.body).not_to include("Task Beta 1")
    end

    it "keeps the selected project pre-selected in the dropdown" do
      expect(response.body).to match(/<option [^>]*selected="selected"[^>]*value="#{Regexp.escape(selected_project)}"/)
    end
  end

  describe "GET /dashboard when SheetsApiClient raises an error" do
    before do
      error = Google::Apis::ClientError.new("Not Found")
      allow(error).to receive(:status_code).and_return(404)
      allow(SheetsApiClient).to receive(:fetch_rows).and_raise(error)
      get "/dashboard"
    end

    it "returns HTTP 200 and shows the error message instead of raising" do
      expect(response).to have_http_status(200)
      expect(response.body).to include("錯誤")
    end
  end
end
