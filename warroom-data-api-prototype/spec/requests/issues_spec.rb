require "rails_helper"

RSpec.describe "Issues", type: :request do
  def project_breakdown_section(body)
    # 專案下拉選單與議題明細不受月份篩選影響，會恆常包含所有專案名稱，
    # 因此驗證「依專案分類」統計時必須只擷取該表格區塊，避免誤判其他區塊的文字
    body[%r{<h2>依專案分類</h2>.*?</section>}m]
  end

  let(:month_kpi_rows) do
    [
      %w[year_month 客訴 測試 總Bug 攔截率 完成數 未結案 平均天數 SLA達標率 Top3],
      [ "2026-07", "28", "7", "35", "20", "10", "7", "2.61", "10.71", "王贊勛:20" ],
      [ "2026-08", "15", "9", "24", "37.5", "6", "3", "3.1", "25", "王贊勛:8" ]
    ]
  end

  let(:daily_kpi_rows) do
    [
      %w[日期 客訴 測試 其他 總計],
      [ "2026-07-15", "1", "0", "0", "1" ],
      [ "2026-08-01", "0", "1", "0", "1" ],
      [ "2026-08-13", "0", "0", "0", "0" ]
    ]
  end

  let(:issue_rows) do
    [
      %w[issue_id subject type tracker status assigned_to start_date due_date work_days sheet_name project],
      [ "4547", "未匯入行事曆", "Complaint", "臭蟲", "已結束", "黃靖益",
       "2026/1/2", "2026/1/6", "3", "raw_2026", "Virtuous HRM" ],
      [ "5165", "白名單申請時間錯誤", "TestingBug", "臭蟲", "新建立", "蔡秉逸",
       "2026/8/12", "", "", "raw_2026", "Virtuous HRM" ],
      [ "3058", "結案小工序DeadlockVictim", "Other", "臭蟲", "已暫停", "王贊勛",
       "2024/4/29", "", "", "raw_2024", "AG 亞炬" ],
      [ "5170", "測試環境資料回填驗證", "TestingBug", "測試", "新建立", "蔡秉逸",
       "2026/8/13", "", "", "raw_2026", "Virtuous HRM" ],
      [ "5180", "客訴：儀表板顯示異常", "Complaint", "臭蟲", "已解決", "王贊勛",
       "2026/8/5", "2026/8/6", "1", "raw_2026", "JZN 舊振南智慧工廠" ]
    ]
  end

  before do
    allow(IssueSheetsClient).to receive(:fetch_month_kpi_rows).and_return(month_kpi_rows)
    allow(IssueSheetsClient).to receive(:fetch_daily_kpi_rows).and_return(daily_kpi_rows)
    allow(IssueSheetsClient).to receive(:fetch_issue_rows).and_return(issue_rows)
  end

  describe "GET /issues with default filters" do
    before { get "/issues" }

    it "returns HTTP 200" do
      expect(response).to have_http_status(200)
    end

    it "defaults the date range to the latest settled month's bounds" do
      expect(response.body).to include(%(name="from" id="from" value="2026-08-01"))
      expect(response.body).to include(%(name="to" id="to" value="2026-08-31"))
    end

    it "shows KPI values for the latest month" do
      expect(response.body).to include("37.5")
      expect(response.body).to include("25.0")
    end

    it "shows exactly one section-note, explaining the settlement/live-data distinction near the KPI heading" do
      notes = response.body.scan(%r{<p class="section-note">([^<]*)</p>})
      expect(notes.size).to eq(1)
      expect(notes.first.first).to include("月結").and include("即時")
    end

    it "does not repeat the note near the project/status filters (which do actively filter the list below)" do
      # 確認「不受期間篩選影響」字樣只出現一次（在月度 KPI 區塊），不會出現在議題明細篩選附近造成混淆
      expect(response.body.scan("不受期間篩選影響").size).to eq(1)
    end

    it "shows the project breakdown table filtered to issues started in the selected month" do
      # 預設月份為 2026-08，issue 5165／5180 的 start_date 落在此月份，issue 3058（2024/4/29）不應出現
      section = project_breakdown_section(response.body)
      expect(section).to include("Virtuous HRM")
      expect(section).to include("JZN 舊振南智慧工廠")
      expect(section).not_to include("AG 亞炬")
    end

    it "renders sortable column headers for 客訴／測試／其他／總計 without a sort applied by default" do
      section = project_breakdown_section(response.body)
      %w[客訴 測試 其他 總計].each { |label| expect(section).to include(">#{label}<") }
      expect(section).not_to include("▲")
      expect(section).not_to include("▼")
    end

    it "renders the trend chart SVG with one point per daily_kpi row" do
      expect(response.body.scan("trend-point").size).to eq(2)
    end

    it "defaults the status filter to 新建立, showing only the matching issue" do
      expect(response.body).to include("白名單申請時間錯誤")
      expect(response.body).not_to include("未匯入行事曆")
      expect(response.body).not_to include("結案小工序DeadlockVictim")
    end

    it "renders the issue_id as a link to Redmine" do
      expect(response.body).to include('href="https://redmine.amastek.com.tw/issues/5165"')
      expect(response.body).to include('target="_blank"')
      expect(response.body).to include('rel="noopener noreferrer"')
    end

    it "renders the attribution badge for the visible issue" do
      expect(response.body).to include("個人責任") # TestingBug
    end
  end

  describe "GET /issues?status= (cleared status filter)" do
    before { get "/issues", params: { status: "" } }

    it "shows all issues regardless of status" do
      expect(response.body).to include("未匯入行事曆")
      expect(response.body).to include("白名單申請時間錯誤")
      expect(response.body).to include("結案小工序DeadlockVictim")
    end

    it "excludes issues whose tracker is 測試 (test-only issue, not a real quality defect) even with no status filter" do
      expect(response.body).not_to include("測試環境資料回填驗證")
    end

    it "shows all three attribution categories" do
      expect(response.body).to include("專案共同責任") # Complaint
      expect(response.body).to include("個人責任") # TestingBug
      expect(response.body).to include("其他") # Other
    end
  end

  describe "GET /issues?project=XXX&status=" do
    before { get "/issues", params: { project: "AG 亞炬", status: "" } }

    it "shows only the selected project's issues" do
      expect(response.body).to include("結案小工序DeadlockVictim")
      expect(response.body).not_to include("未匯入行事曆")
      expect(response.body).not_to include("白名單申請時間錯誤")
    end

    it "keeps the selected project pre-selected in the dropdown" do
      expect(response.body).to match(/<option [^>]*selected="selected"[^>]*value="AG 亞炬"/)
    end
  end

  describe "GET /issues?from=2026-07-01&to=2026-07-31" do
    before { get "/issues", params: { from: "2026-07-01", to: "2026-07-31", status: "" } }

    it "shows KPI values for the selected month, not the latest" do
      expect(response.body).to include("20.0") # block_rate for 2026-07
    end

    it "filters the project breakdown to issues started in the selected month" do
      # 2026-07 沒有任何 issue 的 start_date 落在此月份，應顯示空狀態
      section = project_breakdown_section(response.body)
      expect(section).to include("所選期間無議題資料")
      expect(section).not_to include("Virtuous HRM")
      expect(section).not_to include("AG 亞炬")
    end

    it "filters the trend chart to daily_kpi rows in the selected month" do
      expect(response.body.scan("trend-point").size).to eq(1)
    end
  end

  describe "GET /issues?from=2026-07-01&to=2026-08-31 (跨月彙總)" do
    before { get "/issues", params: { from: "2026-07-01", to: "2026-08-31", status: "" } }

    it "sums the count fields across matched months" do
      expect(response.body).to include(">43<") # complaint 28+15
      expect(response.body).to include(">16<") # testing 7+9, unresolved 7+3
      expect(response.body).to include(">59<") # total_bug 35+24
    end

    it "shows a dash instead of a blended rate for block_rate/avg_days/sla_rate" do
      expect(response.body.scan("－").size).to be >= 3
      expect(response.body).not_to include("37.5%")
      expect(response.body).not_to include("20.0%")
    end

    it "notes how many months were aggregated" do
      expect(response.body).to include("彙總 2 個月")
    end
  end

  describe "GET /issues?from=2026-01-01&to=2026-01-31" do
    before { get "/issues", params: { from: "2026-01-01", to: "2026-01-31", status: "" } }

    it "shows the project breakdown filtered to issues started in January (需求 3a.2 已改為依日期區間篩選)" do
      # issue 4547 的 start_date 為 2026/1/2，屬於此月份
      section = project_breakdown_section(response.body)
      expect(section).to include("Virtuous HRM")
      expect(section).not_to include("AG 亞炬")
    end
  end

  describe "GET /issues?breakdown_sort=... (依專案分類排序)" do
    def breakdown_project_order(body)
      project_breakdown_section(body).scan(%r{<td>([^<]+)</td>}).flatten.each_slice(5).map(&:first)
    end

    it "defaults to descending when a sort key is first applied" do
      get "/issues", params: { breakdown_sort: "complaint" }

      # 2026-08：JZN 舊振南智慧工廠 complaint=1（issue 5180），Virtuous HRM complaint=0（issue 5165 為 TestingBug）
      expect(breakdown_project_order(response.body)).to eq([ "JZN 舊振南智慧工廠", "Virtuous HRM" ])
    end

    it "toggles to ascending when the same key is applied with breakdown_dir=asc" do
      get "/issues", params: { breakdown_sort: "complaint", breakdown_dir: "asc" }

      expect(breakdown_project_order(response.body)).to eq([ "Virtuous HRM", "JZN 舊振南智慧工廠" ])
    end

    it "shows a ▼ indicator on the active descending column and none on the others" do
      get "/issues", params: { breakdown_sort: "testing" }

      section = project_breakdown_section(response.body)
      expect(section).to include("測試 ▼")
      expect(section).not_to include("客訴 ▼")
      expect(section).not_to include("客訴 ▲")
    end

    it "ignores an invalid breakdown_sort value and falls back to unsorted order" do
      get "/issues", params: { breakdown_sort: "not-a-real-column" }

      section = project_breakdown_section(response.body)
      expect(section).not_to include("▲")
      expect(section).not_to include("▼")
    end

    it "keeps the selected date range while sorting (sort links preserve the from/to params)" do
      get "/issues", params: { from: "2026-01-01", to: "2026-01-31", breakdown_sort: "complaint" }

      section = project_breakdown_section(response.body)
      expect(section).to include("from=2026-01-01")
      expect(section).to include("to=2026-01-31")
      expect(section).to include("breakdown_sort=complaint")
    end

    it "sorts ties deterministically by project name (tie-breaker, avoids Ruby's non-stable sort_by)" do
      # 2026-08：JZN 舊振南智慧工廠（complaint=1）、Virtuous HRM（complaint=0）不會平手，故換一個
      # 兩專案同分的欄位（total 各為 1）驗證平手時的順序固定為 project 字典序
      get "/issues", params: { breakdown_sort: "total" }

      expect(breakdown_project_order(response.body)).to eq([ "JZN 舊振南智慧工廠", "Virtuous HRM" ].sort.reverse)
    end
  end

  describe "GET /issues 兩個分頁籤的表單各自送出時，不得覆蓋另一個分頁籤目前的篩選狀態" do
    it "keeps the 議題資料 tab's project/status filters when submitting the 統計摘要 tab's date range form" do
      get "/issues", params: { tab: "detail", project: "AG 亞炬", status: "" }
      get "/issues", params: { tab: "stats", from: "2026-07-01", to: "2026-07-31", project: "AG 亞炬", status: "" }

      expect(response.body).to match(/<option [^>]*selected="selected"[^>]*value="AG 亞炬"/)
      expect(response.body).to match(/<option [^>]*selected="selected"[^>]*value=""[^>]*>全部狀態<\/option>/)
    end

    it "keeps the 統計摘要 tab's date range/sort selections when submitting the 議題資料 tab's filter form" do
      get "/issues", params: { tab: "stats", from: "2026-08-01", to: "2026-08-31",
                                breakdown_sort: "complaint", breakdown_dir: "asc" }
      get "/issues", params: { tab: "detail", project: "", status: "", from: "2026-08-01", to: "2026-08-31",
                                breakdown_sort: "complaint", breakdown_dir: "asc" }

      expect(response.body).to include(%(name="from" id="from" value="2026-08-01"))
      expect(response.body).to include(%(name="to" id="to" value="2026-08-31"))
      section = project_breakdown_section(response.body)
      expect(section).to include("breakdown_sort=complaint")
      expect(section).to include("breakdown_dir=desc") # 反轉方向的連結會顯示 desc（因目前是 asc）
    end

    it "the 統計摘要 tab's form includes hidden project/status fields carrying the current filter" do
      get "/issues", params: { project: "AG 亞炬", status: "已暫停" }

      stats_panel = response.body[/<div class="tab-panel" id="tab-panel-stats">.*?(?=<div class="tab-panel" id="tab-panel-detail">)/m]
      expect(stats_panel).to include('<input type="hidden" name="project" id="project" value="AG 亞炬"')
      expect(stats_panel).to include('<input type="hidden" name="status" id="status" value="已暫停"')
    end

    it "the 議題資料 tab's form includes hidden from/to/breakdown_sort/breakdown_dir fields carrying the current state" do
      get "/issues", params: { from: "2026-01-01", to: "2026-01-31", breakdown_sort: "testing", breakdown_dir: "asc" }

      detail_panel = response.body[/<div class="tab-panel" id="tab-panel-detail">.*/m]
      expect(detail_panel).to include('<input type="hidden" name="from" id="from" value="2026-01-01"')
      expect(detail_panel).to include('<input type="hidden" name="to" id="to" value="2026-01-31"')
      expect(detail_panel).to include('<input type="hidden" name="breakdown_sort" id="breakdown_sort" value="testing"')
      expect(detail_panel).to include('<input type="hidden" name="breakdown_dir" id="breakdown_dir" value="asc"')
    end

    it "the breakdown sort links preserve the 議題資料 tab's current project/status filters" do
      get "/issues", params: { project: "AG 亞炬", status: "已暫停" }

      section = project_breakdown_section(response.body)
      expect(section).to include("project=AG")
      expect(section).to include("status=%E5%B7%B2%E6%9A%AB%E5%81%9C")
    end
  end

  describe "GET /issues?project=DoesNotExist&status=" do
    before { get "/issues", params: { project: "DoesNotExist", status: "" } }

    it "shows the empty state message instead of a table" do
      expect(response.body).to include("目前無符合條件的議題")
    end
  end

  describe "GET /issues when IssueSheetsClient raises Google::Apis::ClientError (404)" do
    before do
      error = Google::Apis::ClientError.new("Not Found")
      allow(error).to receive(:status_code).and_return(404)
      allow(IssueSheetsClient).to receive(:fetch_month_kpi_rows).and_raise(error)
      get "/issues"
    end

    it "returns HTTP 200 and shows the error message instead of raising" do
      expect(response).to have_http_status(200)
      expect(response.body).to include("錯誤")
    end
  end

  describe "GET /issues when the current month has no month_kpi row yet (not settled)" do
    include ActiveSupport::Testing::TimeHelpers

    around do |example|
      travel_to(Time.zone.local(2026, 9, 15)) { example.run }
    end

    before { get "/issues" }

    it "includes the in-progress current month (2026-09) in the date input's max bound" do
      expect(response.body).to include('max="2026-09-30"')
    end

    it "still defaults the selection to the latest settled month (2026-08), not 2026-09" do
      expect(response.body).to include(%(name="from" id="from" value="2026-08-01"))
      expect(response.body).to include(%(name="to" id="to" value="2026-08-31"))
    end

    it "shows real KPI numbers by default (the settled month)" do
      expect(response.body).to include("37.5")
    end

    context "when the user explicitly selects the in-progress month" do
      before { get "/issues", params: { from: "2026-09-01", to: "2026-09-30" } }

      it "shows a 尚未結算 placeholder instead of numbers" do
        expect(response.body).to include("尚未結算")
      end

      it "shows the empty state for the project breakdown (no issues started in 2026-09)" do
        expect(response.body).to include("所選期間無議題資料")
      end
    end
  end

  describe "tabs: 統計摘要 (stats) vs 議題資料 (detail)" do
    def tab_checked?(body, tab_id)
      match = body.match(%r{<input type="radio" name="issue-tab" id="#{tab_id}" class="tab-radio"\s*(checked)?\s*>})
      match[1].present?
    end

    it "defaults to the 統計摘要 (stats) tab on first load" do
      get "/issues"

      expect(tab_checked?(response.body, "tab-stats")).to be true
      expect(tab_checked?(response.body, "tab-detail")).to be false
    end

    it "puts 月度 KPI／每日趨勢／依專案分類 inside the stats tab panel, and only 議題明細 inside the detail tab panel" do
      get "/issues"

      stats_panel = response.body[/<div class="tab-panel" id="tab-panel-stats">.*?(?=<div class="tab-panel" id="tab-panel-detail">)/m]
      detail_panel = response.body[/<div class="tab-panel" id="tab-panel-detail">.*/m]

      expect(stats_panel).to include("<h2>月度 KPI</h2>").and include("<h2>每日趨勢</h2>")
      expect(stats_panel).to include("<h2>依專案分類</h2>")
      expect(stats_panel).not_to include("<h2>議題明細</h2>")

      expect(detail_panel).to include("<h2>議題明細</h2>")
      expect(detail_panel).not_to include("<h2>月度 KPI</h2>")
      expect(detail_panel).not_to include("<h2>每日趨勢</h2>")
      expect(detail_panel).not_to include("<h2>依專案分類</h2>")
    end

    it "stays on the stats tab after submitting the date range filter (hidden tab=stats field)" do
      get "/issues", params: { from: "2026-07-01", to: "2026-07-31", tab: "stats" }

      expect(tab_checked?(response.body, "tab-stats")).to be true
      expect(tab_checked?(response.body, "tab-detail")).to be false
    end

    it "switches to and stays on the detail tab after submitting the project/status filter (hidden tab=detail field)" do
      get "/issues", params: { project: "Virtuous HRM", status: "", tab: "detail" }

      expect(tab_checked?(response.body, "tab-detail")).to be true
      expect(tab_checked?(response.body, "tab-stats")).to be false
    end

    it "ignores an invalid tab param and falls back to the stats tab" do
      get "/issues", params: { tab: "not-a-real-tab" }

      expect(tab_checked?(response.body, "tab-stats")).to be true
    end
  end

  describe "GET /issues pagination (Pagy)" do
    # 這次改動的核心問題之一：params[:page] 若被送成陣列（例如 ?page[]=1&page[]=2），舊版手刻
    # 的 params[:page].to_i 會讓 Array#to_i 直接噴 NoMethodError（500）。Pagy 內部改用
    # page.to_s.to_i，各種輸入型別都不會炸，這裡直接驗證這個曾經的崩潰路徑現在回 200。
    it "does not 500 when page is submitted as an array" do
      get "/issues", params: { tab: "detail", status: "", page: [ "1", "2" ] }

      # 不能用 include("錯誤") 判斷有沒有錯誤訊息：這份 fixture 裡剛好有一筆議題主旨是
      # 「白名單申請時間錯誤」，字面上就含有「錯誤」兩個字，會跟真正的錯誤橫幅字樣混在一起
      # 誤判。改成比對實際的錯誤橫幅 markup（見 app/views/issues/index.html.erb 的
      # <div class="error-message">）。
      expect(response).to have_http_status(200)
      expect(response.body).not_to include('class="error-message"')
    end

    it "does not 500 for a non-numeric page value, and falls back to page 1" do
      get "/issues", params: { tab: "detail", status: "", page: "not-a-number" }

      expect(response).to have_http_status(200)
      expect(response.body).to include("顯示 1–")
    end

    context "with more issues than fit on one page" do
      let(:issue_rows) do
        header = %w[issue_id subject type tracker status assigned_to start_date due_date work_days sheet_name project]
        rows = (1..20).map do |n|
          [ "60#{n.to_s.rjust(2, '0')}", "議題 #{n}", "Other", "臭蟲", "新建立", "王贊勛",
            "2026/8/1", "2026/8/10", "1", "raw_2026", "P" ]
        end
        [ header ] + rows
      end

      it "renders 20 issues across 2 pages with a working Pagy nav" do
        get "/issues", params: { tab: "detail", status: "" }

        expect(response).to have_http_status(200)
        expect(response.body).to include("顯示 1–15 筆，共 20 筆")
        expect(response.body).to include('class="pagy series-nav"')
        # 用 issue-id-link 數量算實際渲染的議題列數，不用 <tr>——同一頁還有依專案分類的表格
        # 等其他 <table>，直接數 <tr> 會把那些表格的列也算進去。
        expect(response.body.scan('class="issue-id-link"').size).to eq(15)
      end

      it "shows the remaining issues on page 2" do
        get "/issues", params: { tab: "detail", status: "", page: 2 }

        expect(response).to have_http_status(200)
        expect(response.body).to include("顯示 16–20 筆，共 20 筆")
        expect(response.body.scan('class="issue-id-link"').size).to eq(5)
      end
    end
  end
end
