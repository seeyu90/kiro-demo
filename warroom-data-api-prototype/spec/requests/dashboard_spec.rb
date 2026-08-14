require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  let(:header_row) { ["專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延誤", "類型"] }
  let(:valid_rows) do
    [
      header_row,
      ["Project Alpha", "Task Alpha 1", "完成", "Alice", "2026/1/5", "2026/1/6", "1", "功能"],
      ["Project Beta", "Task Beta 1", "未完成", "Bob", "2026/2/10", "", "", "PR"],
      ["Project Beta", "Task Beta 2", "未完成", "Carol", "2099/1/1", "", "", "調整"]
    ]
  end

  before { allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return(valid_rows) }

  describe "GET /dashboard with filters disabled (scope=all, incomplete_only=0, all types)" do
    before do
      get "/dashboard", params: { scope: "all", incomplete_only: "0", "task_type[]" => ["功能", "PR", "調整"] }
    end

    it "returns HTTP 200" do
      expect(response).to have_http_status(200)
    end

    it "renders the project dropdown with all project names" do
      expect(response.body).to include("全部專案")
      expect(response.body).to include("Project Alpha")
      expect(response.body).to include("Project Beta")
    end

    it "renders every project's task blocks regardless of status/type/date" do
      expect(response.body).to include("Task Alpha 1")
      expect(response.body).to include("Task Beta 1")
      expect(response.body).to include("Task Beta 2")
    end
  end

  describe "GET /dashboard with default filters" do
    before { get "/dashboard" }

    it "returns HTTP 200" do
      expect(response).to have_http_status(200)
    end

    it "defaults the project filter to all projects" do
      expect(response.body).to include("Project Alpha")
      expect(response.body).to include("Project Beta")
    end

    it "hides completed tasks by default (incomplete_only defaults to true)" do
      expect(response.body).not_to include("Task Alpha 1")
    end

    it "defaults the task type filter to 功能 and PR, excluding other types" do
      expect(response.body).not_to include("Task Beta 2") # task_type "調整"
    end

    it "shows incomplete tasks matching the default type/scope (due this week, incl. overdue)" do
      expect(response.body).to include("Task Beta 1") # PR, in_progress, planned date long past → overdue → within default scope
    end
  end

  describe "GET /dashboard?project=XXX" do
    let(:selected_project) { "Project Alpha" }

    before { get "/dashboard", params: { project: selected_project, incomplete_only: "0", scope: "all" } }

    it "returns HTTP 200" do
      expect(response).to have_http_status(200)
    end

    it "renders only the selected project's task blocks" do
      expect(response.body).to include("Task Alpha 1")
      expect(response.body).not_to include("Task Beta 1")
      expect(response.body).not_to include("Task Beta 2")
    end

    it "keeps the selected project pre-selected in the dropdown" do
      expect(response.body).to match(/<option [^>]*selected="selected"[^>]*value="#{Regexp.escape(selected_project)}"/)
    end
  end

  describe "GET /dashboard when ProjectProgressSheetsClient raises an error" do
    before do
      error = Google::Apis::ClientError.new("Not Found")
      allow(error).to receive(:status_code).and_return(404)
      allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_raise(error)
      get "/dashboard"
    end

    it "returns HTTP 200 and shows the error message instead of raising" do
      expect(response).to have_http_status(200)
      expect(response.body).to include("錯誤")
    end
  end

  describe "GET /dashboard freshness label (task 4)" do
    it "shows the freshness text when ProjectProgressSheetsClient reports a fetched_at time" do
      allow(ProjectProgressSheetsClient).to receive(:fetched_at).and_return(Time.current)

      get "/dashboard"

      expect(response.body).to include("freshness-label")
    end

    it "omits the freshness text when there is no recorded fetched_at (e.g. :null_store in test env)" do
      allow(ProjectProgressSheetsClient).to receive(:fetched_at).and_return(nil)

      get "/dashboard"

      expect(response.body).not_to include("freshness-label")
    end
  end

  describe "GET /dashboard?refresh=1 (task 5)" do
    it "requests ProjectProgressSheetsClient.fetch_rows with force: true" do
      expect(ProjectProgressSheetsClient).to receive(:fetch_rows).with(force: true).and_return(valid_rows)

      get "/dashboard", params: { refresh: "1" }

      expect(response).to have_http_status(200)
    end

    it "does not force a refresh on a normal request" do
      expect(ProjectProgressSheetsClient).to receive(:fetch_rows).with(force: false).and_return(valid_rows)

      get "/dashboard"
    end

    it "renders a '重新整理資料' button in the filter form" do
      get "/dashboard"

      expect(response.body).to include("重新整理資料")
    end
  end
end
