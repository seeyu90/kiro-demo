require "rails_helper"

RSpec.describe "Burndown", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    travel_to(Date.new(2026, 8, 14)) { example.run }
  end

  def issue_series_section(body)
    body[%r{<h2>議題燃盡狀態</h2>.*?</section>}m]
  end

  let(:fixed_header) { %w[剩餘人時 專案 議題 人員 議題ID 開案日期 完成日期 狀態 預估人時] }
  let(:header) { fixed_header + [ "08/10", "08/03" ] }

  # travel_to 固定為 2026-08-14；狀態欄位（H 欄）皆留白，故以下 fallback 到 due_date 判斷：
  # 議題A（due 08-15）／議題B（due 08-20）晚於今天視為進行中，議題C（due 08-10）早於今天視為已完成。
  let(:burndown_rows) do
    [
      header,
      [ "2", "AG 亞炬", "議題A", "王贊勛", "1001", "2026/08/01", "2026/08/15", "", "10", "3", "2" ],
      [ "1", "AG 亞炬", "議題B", "蔡秉逸", "1002", "2026/08/01", "2026/08/20", "", "8", "1", "1" ],
      [ "0", "Virtuous HRM", "議題C", "王贊勛", "1003", "2026/08/01", "2026/08/10", "", "5", "2", "3" ]
    ]
  end

  before { allow(BurndownSheetsClient).to receive(:fetch_rows).and_return(burndown_rows) }

  describe "GET /burndown with no filters" do
    before { get "/burndown" }

    it "returns HTTP 200" do
      expect(response).to have_http_status(200)
    end

    it "defaults to showing only in-progress issues (due_date after today)" do
      section = issue_series_section(response.body)
      expect(section).to include("議題A")
      expect(section).to include("議題B")
      expect(section).not_to include("議題C")
    end

    it "lists both projects and both assignees in the filter dropdowns" do
      expect(response.body).to include('value="AG 亞炬"').and include('value="Virtuous HRM"')
      expect(response.body).to include('value="王贊勛"').and include('value="蔡秉逸"')
    end
  end

  describe "GET /burndown?status=... (status filter)" do
    it "status=done shows only issues whose due_date is on or before today" do
      get "/burndown", params: { status: "done" }
      section = issue_series_section(response.body)
      expect(section).not_to include("議題A")
      expect(section).not_to include("議題B")
      expect(section).to include("議題C")
    end

    it "status=all shows issues regardless of due_date" do
      get "/burndown", params: { status: "all" }
      section = issue_series_section(response.body)
      expect(section).to include("議題A")
      expect(section).to include("議題B")
      expect(section).to include("議題C")
    end
  end

  describe "GET /burndown?status=... when the sheet's 狀態 column has valid values" do
    # 議題D 的 due_date（08-20）晚於今天，若靠 due_date fallback 會判斷為進行中，
    # 但狀態欄位填「已完成」，應以狀態欄位為準；議題E 反過來驗證同一件事。
    let(:burndown_rows) do
      [
        header,
        [ "0", "AG 亞炬", "議題D", "王贊勛", "2001", "2026/08/01", "2026/08/20", "已完成", "10", "3", "2" ],
        [ "5", "AG 亞炬", "議題E", "蔡秉逸", "2002", "2026/08/01", "2026/08/05", "執行中", "8", "1", "1" ]
      ]
    end

    it "defaults to showing only issues whose 狀態 column says 未開始／執行中, honoring the sheet over due_date" do
      get "/burndown"
      section = issue_series_section(response.body)
      expect(section).not_to include("議題D")
      expect(section).to include("議題E")
    end

    it "status=done shows only the issue marked 已完成 in the sheet" do
      get "/burndown", params: { status: "done" }
      section = issue_series_section(response.body)
      expect(section).to include("議題D")
      expect(section).not_to include("議題E")
    end
  end

  describe "GET /burndown?project=... (project filter only)" do
    before { get "/burndown", params: { project: "AG 亞炬", status: "all" } }

    it "shows only the issues under the selected project" do
      section = issue_series_section(response.body)
      expect(section).to include("議題A")
      expect(section).to include("議題B")
      expect(section).not_to include("議題C")
    end
  end

  describe "GET /burndown?assignee=... (assignee filter only)" do
    before { get "/burndown", params: { assignee: "王贊勛", status: "all" } }

    it "shows only the issues assigned to the selected person" do
      section = issue_series_section(response.body)
      expect(section).to include("議題A")
      expect(section).to include("議題C")
      expect(section).not_to include("議題B")
    end
  end

  describe "GET /burndown?project=...&assignee=... (both filters, intersection)" do
    before { get "/burndown", params: { project: "AG 亞炬", assignee: "王贊勛", status: "all" } }

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

  describe "GET /burndown with from/to date range filter" do
    it "renders the selected from/to values back into the date inputs" do
      get "/burndown", params: { from: "2026-08-05", to: "2026-08-12" }

      expect(response.body).to include(%(name="from" id="from" value="2026-08-05"))
      expect(response.body).to include(%(name="to" id="to" value="2026-08-12"))
    end

    it "does not restrict weeks when from/to are absent (default, backward compatible)" do
      get "/burndown", params: { status: "all" }

      # 議題A：08/10 週人時 3、08/03 週人時 2，兩週都應計入累積消耗（10 - 3 - 2 = 5 剩餘）。
      section = issue_series_section(response.body)
      expect(section).to include("5") # 議題A 剩餘人時
    end

    it "narrows the displayed weeks to [from, to], changing the computed remaining hours" do
      get "/burndown", params: { status: "all", from: "2026-08-08", to: "2026-08-31" }

      # 只剩 08/10 這一週人時 3 計入（08/03 被篩掉），議題A 剩餘 = 10 - 3 = 7。
      section = issue_series_section(response.body)
      expect(section).to include("7")
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
      expect(response.body).not_to include("議題燃盡狀態")
    end
  end
end
