require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  # 年度篩選預設「今年」，逾期判斷也以今天為基準，兩者都依賴 Date.current；固定在一個
  # 資料涵蓋得到的日期，測試才不會在跨年之後自己壞掉。
  around { |example| travel_to(Date.new(2026, 9, 16)) { example.run } }

  let(:header_row) { [ "專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延誤", "類型" ] }
  let(:valid_rows) do
    [
      header_row,
      [ "Project Alpha", "Task Alpha 1", "完成", "Alice", "2026/1/5", "2026/1/6", "1", "功能" ],
      [ "Project Beta", "Task Beta 1", "未完成", "Bob", "2026/2/10", "", "", "PR" ],
      [ "Project Beta", "Task Beta 2", "未完成", "Carol", "2099/1/1", "", "", "調整" ]
    ]
  end

  before { allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return(valid_rows) }

  # 305 頁面原本漏了 content_for :title，瀏覽器分頁標題會顯示不對；且 header 的返回連結
  # 改為跟 306/307/專案歷程統一的麵包屑樣式（見 application.css 的 .breadcrumb 附註）。
  describe "GET /dashboard header" do
    before { get "/dashboard" }

    it "sets the page title" do
      expect(response.body).to include("<title>戰情室 — 305 專案任務進度</title>")
    end

    it "shows a breadcrumb back to the entry page, matching 306/307/專案歷程 style" do
      expect(response.body).to include("breadcrumb")
      expect(response.body).to include(">入口頁</a>")
    end
  end

  describe "GET /dashboard with filters disabled (scope=all, all types)" do
    before do
      get "/dashboard", params: { scope: "all", "task_type[]" => [ "功能", "PR", "調整" ] }
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

    it "limits the default view to this week's scope (scope defaults to 本週到期)" do
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

    before { get "/dashboard", params: { project: selected_project, scope: "all" } }

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

  # 資料時效標籤已移除：「重新整理資料」收斂為入口頁唯一入口後，各頁再顯示「資料更新於 X
  # 分鐘前」既無對應動作可做，也佔掉篩選列與資料之間的視線。
  describe "GET /dashboard 資料時效標籤" do
    it "no longer renders the freshness label" do
      allow(ProjectProgressSheetsClient).to receive(:fetched_at).and_return(Time.current)

      get "/dashboard"

      expect(response.body).not_to include("freshness-label")
    end
  end

  # 「重新整理資料」已收斂為全站唯一入口，改放在入口頁（POST /refresh，見 home_spec.rb），
  # 各頁不再各自帶 refresh 參數強制重抓自己那一份試算表。
  describe "GET /dashboard (資料快取)" do
    it "does not force a refresh" do
      expect(ProjectProgressSheetsClient).to receive(:fetch_rows).with(force: false).and_return(valid_rows)

      get "/dashboard"
    end

    it "no longer renders a per-page 重新整理資料 button" do
      get "/dashboard"

      expect(response.body).not_to include("重新整理資料")
    end
  end

  # 「只看未完成」是這一頁最常見的意圖之一；獨立的狀態篩選移除後，改由範圍的這個檢視提供。
  describe "GET /dashboard?scope=incomplete" do
    it "lists unfinished tasks regardless of their planned date" do
      get "/dashboard", params: { scope: "incomplete", "task_type[]" => [ "功能", "PR", "調整" ] }

      expect(response.body).to include("Task Beta 1")   # 未完成、逾期
      expect(response.body).to include("Task Beta 2")   # 未完成、2099 才到期
      expect(response.body).not_to include("Task Alpha 1") # 已完成
    end

    it "renders 未完成 as a scope option" do
      get "/dashboard"

      expect(response.body).to include('value="incomplete"')
    end
  end

  # 年度篩選已移除：305 的資料源鎖在單一年度分頁，下拉永遠只有「全部年度」與當年兩個選項；
  # 日期區間表達力涵蓋年度（整年＝1/1～12/31），兩者擇一保留日期區間。
  describe "GET /dashboard 年度篩選已移除" do
    it "no longer renders a year select, and applies no implicit year restriction" do
      get "/dashboard", params: { scope: "all", "task_type[]" => [ "功能", "PR", "調整" ] }

      expect(response.body).not_to include('name="year"')
      expect(response.body).to include("Task Beta 1")
      expect(response.body).to include("Task Beta 2") # 2099 到期，不再被預設的今年擋掉
    end

    it "keeps tasks that have no date at all" do
      allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return(
        [ header_row, [ "Project Gamma", "No Date Task", "未完成", "Dave", "", "", "", "功能" ] ]
      )

      get "/dashboard", params: { scope: "all" }

      expect(response.body).to include("No Date Task")
    end
  end

  describe "GET /dashboard with from/to date range filter" do
    it "does not restrict tasks when from/to are absent (default, backward compatible)" do
      get "/dashboard", params: { scope: "all", "task_type[]" => [ "功能", "PR", "調整" ] }

      expect(response.body).to include("Task Alpha 1")
      expect(response.body).to include("Task Beta 1")
      expect(response.body).to include("Task Beta 2")
    end

    it "keeps only tasks whose planned_completion_date falls within [from, to]" do
      get "/dashboard", params: {
        scope: "all", "task_type[]" => [ "功能", "PR", "調整" ],
        from: "2026-02-01", to: "2026-02-28"
      }

      expect(response.body).to include("Task Beta 1")
      expect(response.body).not_to include("Task Alpha 1")
      expect(response.body).not_to include("Task Beta 2")
    end

    it "renders the selected from/to values back into the date inputs" do
      get "/dashboard", params: { from: "2026-02-01", to: "2026-02-28" }

      expect(response.body).to include(%(value="2026-02-01"))
      expect(response.body).to include(%(value="2026-02-28"))
    end

    it "ignores an unparsable date and falls back to no restriction on that bound" do
      get "/dashboard", params: {
        scope: "all", "task_type[]" => [ "功能", "PR", "調整" ], from: "not-a-date"
      }

      expect(response).to have_http_status(200)
      expect(response.body).to include("Task Alpha 1")
    end
  end
end
