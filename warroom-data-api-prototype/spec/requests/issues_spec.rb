require "rails_helper"

RSpec.describe "Issues", type: :request do
  def project_breakdown_section(body)
    # 專案下拉選單與議題明細不受月份篩選影響，會恆常包含所有專案名稱，
    # 因此驗證「依專案分類」統計時必須只擷取該表格區塊，避免誤判其他區塊的文字
    body[%r{<h2>依專案分類</h2>.*?</section>}m]
  end

  # 「議題資料」分頁也有一組 stat-value（待處理議題／緊急客訴／花費工時／逾期或未定到期日），
  # 跟「月度 KPI」的 8 張卡共用同一個 class，數字又常常重疊（0、1、2 這種小數字到處都是），
  # 驗證月度 KPI 卡片數字時必須只擷取這個區塊，避免誤判到另一組卡片。
  def month_kpi_section(body)
    body[%r{<h2>月度 KPI</h2>.*?</section>}m]
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
    # 客訴／測試／總Bug／攔截率改由 issues 即時算後，預設區間（未帶 from/to）改成「當月」
    # （需求 9.1），不再是「month_kpi 已結算的最新月份」，因此會依賴 Date.current。固定在一個
    # fixture 涵蓋得到的日期，測試才不會因為實際執行日期落在哪個月份而改變結果。
    around { |example| travel_to(Date.new(2026, 8, 19)) { example.run } }

    before { get "/issues" }

    it "returns HTTP 200" do
      expect(response).to have_http_status(200)
    end

    it "defaults the date range to the current month's bounds" do
      expect(response.body).to include(%(name="from" id="from" value="2026-08-01"))
      expect(response.body).to include(%(name="to" id="to" value="2026-08-31"))
    end

    # 8 個欄位全部即時從 issues 算：8 月只有 issue 5165（TestingBug／新建立）與 5180
    # （Complaint／已解決／work_days=1）落在範圍內（5170 tracker=測試被排除）。
    # block_rate＝1÷(1+1)×100＝50.0，跟 month_kpi_rows 寫的 37.5 不同；SLA達標率＝
    # work_days<=1 的 5180 一筆 ÷ 1 客訴×100＝100.0，跟 month_kpi_rows 寫的 25 也不同——
    # 確認兩者都真的是即時算，不是讀 sheet。
    it "computes block_rate and sla_rate live for the current month, not from month_kpi_rows" do
      section = month_kpi_section(response.body)
      expect(section).to include("50.0%")
      expect(section).not_to include("37.5%")
      expect(section).to include("100.0%")
      expect(section).not_to include("25.0%")
    end

    it "shows exactly one section-note, explaining that the issue list ignores this date range" do
      notes = response.body.scan(%r{<p class="section-note">([^<]*)</p>})
      expect(notes.size).to eq(1)
      expect(notes.first.first).to include("議題資料").and include("不受此處日期區間篩選影響")
    end

    it "does not repeat the note near the project/status filters (which do actively filter the list below)" do
      # 確認「不受此處日期區間篩選影響」字樣只出現一次（在月度 KPI 區塊），不會出現在議題明細
      # 篩選附近造成混淆
      expect(response.body.scan("不受此處日期區間篩選影響").size).to eq(1)
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

    # X 軸現在逐日補齊到「今天」（travel_to 固定 2026-08-19），不是只畫 daily_kpi_rows 裡
    # 剛好有資料的 2 天，才不會讓週末等空隙的間距在圖上跟平常的 1 天看起來一樣寬（見
    # fill_daily_kpi_gaps 的說明）。8/1～8/19 共 19 天。
    it "renders one trend point per calendar day from the 1st of the month through today" do
      expect(response.body.scan("trend-point").size).to eq(19)
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

    it "renders the 類別 badge for the visible issue" do
      expect(response.body).to match(%r{<span class="attribution-badge attribution-individual">\s*測試\s*</span>})
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

    it "shows all three 類別 categories" do
      expect(response.body).to match(%r{<span class="attribution-badge attribution-shared">\s*客訴\s*</span>})
      expect(response.body).to match(%r{<span class="attribution-badge attribution-individual">\s*測試\s*</span>})
      expect(response.body).to match(%r{<span class="attribution-badge attribution-other">\s*其他\s*</span>})
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

  # 類型篩選原本是「只看客訴」快捷 Tag（單一開關），改成跟專案／狀態一致的下拉選單，可以選
  # 客訴／測試／其他三種之一，不再只能二選一（看客訴 or 看全部）。選項文字（客訴／測試／
  # 其他）跟「類別」欄位 badge 的文字改成同一套，兩者共用 issue_type_label——不是
  # attribution_label 那套歸屬責任框架（專案共同責任／個人責任），那套只有 PM 週報還在用；
  # 原本篩選下拉跟欄位各用一套詞彙，使用者反應選了篩選卻在欄位裡看到不同的字，混淆。
  describe "GET /issues?type=... (類型篩選下拉)" do
    it "renders a 類型 dropdown whose option labels match the 類別 column's badge wording" do
      get "/issues"

      expect(response.body).to match(/<label for="type">類型：<\/label>/)
      expect(response.body).to include('<option value="">全部類型</option>')
      expect(response.body).to include('<option value="Complaint">客訴</option>')
      expect(response.body).to include('<option value="TestingBug">測試</option>')
      expect(response.body).to include('<option value="Other">其他</option>')
    end

    it "shows only Complaint-type issues when type=Complaint" do
      get "/issues", params: { type: "Complaint", status: "" }

      expect(response.body).to include("未匯入行事曆").and include("客訴：儀表板顯示異常")
      expect(response.body).not_to include("白名單申請時間錯誤")
      expect(response.body).not_to include("結案小工序DeadlockVictim")
    end

    it "matches the literal Other type value when type=Other" do
      get "/issues", params: { type: "Other", status: "" }

      expect(response.body).to include("結案小工序DeadlockVictim")
      expect(response.body).not_to include("客訴：儀表板顯示異常")
      expect(response.body).not_to include("白名單申請時間錯誤")
    end

    it "keeps the selected type pre-selected in the dropdown" do
      get "/issues", params: { type: "TestingBug", status: "" }

      expect(response.body).to match(/<option [^>]*selected="selected"[^>]*value="TestingBug"/)
    end
  end

  describe "GET /issues?from=2026-07-01&to=2026-07-31" do
    before { get "/issues", params: { from: "2026-07-01", to: "2026-07-31", status: "" } }

    # 這份 fixture 沒有任何 7 月的 Complaint／TestingBug（8 月才有），即時算出來全部歸零／
    # 沒有比率可算，確認顯示的真的是所選的 7 月，不是預設的 8 月（8 月會是 50.0%／100.0%，
    # 見「with default filters」那組測試）。
    it "computes zeroed-out KPI values for the selected month, not the default month's real numbers" do
      section = month_kpi_section(response.body)
      expect(section.scan('<span class="stat-value">0</span>').size).to eq(5) # 客訴／測試／總Bug／完成數／未結案
      expect(section.scan('<span class="stat-value">－</span>').size).to eq(3) # 攔截率／平均天數／SLA達標率
      expect(section).not_to include("50.0%")
      expect(section).not_to include("100.0%")
    end

    it "filters the project breakdown to issues started in the selected month" do
      # 2026-07 沒有任何 issue 的 start_date 落在此月份，應顯示空狀態
      section = project_breakdown_section(response.body)
      expect(section).to include("所選期間無議題資料")
      expect(section).not_to include("Virtuous HRM")
      expect(section).not_to include("AG 亞炬")
    end

    # 7 月已經過完（不受 travel_to 影響，這個 describe 沒有固定「今天」），逐日補齊後是完整
    # 31 天，不是只有 daily_kpi_rows 裡剛好有資料的那 1 天。
    it "fills every calendar day in the selected month, not just the one with a daily_kpi row" do
      expect(response.body.scan("trend-point").size).to eq(31)
    end
  end

  describe "GET /issues?from=2026-07-01&to=2026-08-31 (跨月彙總)" do
    # 客訴／測試／總Bug／攔截率即時從這個區間內的 issues 算，不再靠 month_kpi 表彙總；
    # 加 2 筆 7 月的資料，讓「跨月」這件事對即時計算也是有意義的（用共用 issue_rows 的話，
    # 裡面完全沒有 7 月的 Complaint／TestingBug，即時算出來會跟只看 8 月一樣，測不出跨月效果）。
    let(:issue_rows) do
      [
        %w[issue_id subject type tracker status assigned_to start_date due_date work_days sheet_name project],
        [ "9001", "7月客訴", "Complaint", "臭蟲", "已結束", "王贊勛", "2026/7/5", "", "", "raw_2026", "P" ],
        [ "5165", "白名單申請時間錯誤", "TestingBug", "臭蟲", "新建立", "蔡秉逸",
         "2026/8/12", "", "", "raw_2026", "Virtuous HRM" ],
        [ "5180", "客訴：儀表板顯示異常", "Complaint", "臭蟲", "已解決", "王贊勛",
         "2026/8/5", "2026/8/6", "1", "raw_2026", "JZN 舊振南智慧工廠" ]
      ]
    end

    before { get "/issues", params: { from: "2026-07-01", to: "2026-08-31", status: "" } }

    # 這個區間內（7+8 月）：Complaint 2 筆（9001 已結束、5180 已解決 work_days=1）、
    # TestingBug 1 筆（5165 新建立）。跨兩個月的區間現在只是換一批 issues 重新算一次，不是
    # 彙總兩個月各自的 month_kpi 快照列，8 個欄位都直接對整個區間重算，不再有「有些欄位能
    # 加總、有些欄位不能跨月合併」的分別。
    it "computes complaint/testing/total_bug/block_rate across the combined range" do
      section = month_kpi_section(response.body)
      expect(section).to include("<span class=\"stat-value\">2</span>")   # 客訴
      expect(section).to include("<span class=\"stat-value\">1</span>")   # 測試
      expect(section).to include("<span class=\"stat-value\">3</span>")   # 總Bug
      expect(section).to include("33.33%")
    end

    # 完成數：只有 5180（已解決）算，9001 是「已結束」不是「已解決」不算；未結案：只有 5165
    # （新建立）算；平均天數＝(0+1)÷2 客訴（9001 沒填 work_days 視為 0）；
    # SLA達標率＝work_days<=1 的 5180 一筆 ÷ 2 客訴×100。
    it "computes completed/unresolved/avg_days/sla_rate across the combined range, not from month_kpi_rows" do
      section = month_kpi_section(response.body)
      expect(section).to include("<span class=\"stat-value\">1</span>")   # 完成數／未結案皆為 1
      expect(section).to include("0.5")                                   # 平均天數
      expect(section).to include("50.0%")                                 # SLA達標率
      expect(section).not_to include("37.5%")
      expect(section).not_to include("20.0%")
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
    # 大部分測試沒帶 from/to，依專案分類統計依賴預設區間（見「GET /issues with default
    # filters」的說明）；固定「今天」讓預設區間落在這份 fixture 有資料的 2026-08。
    around { |example| travel_to(Date.new(2026, 8, 19)) { example.run } }

    def breakdown_project_order(body)
      # <td> 現在有的帶 data-label="..."（窄螢幕卡片式版面用，見 _project_breakdown.html.erb），
      # 屬性寫法不固定，用 [^>]* 涵蓋。
      project_breakdown_section(body).scan(%r{<td[^>]*>([^<]+)</td>}).flatten.each_slice(5).map(&:first)
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
    # 其中一個測試（breakdown sort links 那個）沒帶 from/to，依專案分類統計依賴預設區間；
    # 固定「今天」讓預設區間落在這份 fixture 有資料的 2026-08，其餘測試都明確帶 from/to，
    # 不受影響。
    around { |example| travel_to(Date.new(2026, 8, 19)) { example.run } }

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

  describe "GET /issues for the current in-progress month (no issues in this fixture yet)" do
    around { |example| travel_to(Time.zone.local(2026, 9, 15)) { example.run } }

    before { get "/issues" }

    it "includes the in-progress current month (2026-09) in the date input's max bound" do
      expect(response.body).to include('max="2026-09-30"')
    end

    # 需求 9.1：預設一律當月。
    it "defaults the selection to the current month (2026-09)" do
      expect(response.body).to include(%(name="from" id="from" value="2026-09-01"))
      expect(response.body).to include(%(name="to" id="to" value="2026-09-30"))
    end

    # fixture 沒有任何 2026-09 的議題：客訴／測試／總Bug／完成數／未結案（計數類欄位）即時
    # 算出來都是 0；攔截率／平均天數／SLA達標率（比率類欄位，分母是客訴筆數）沒有客訴可算，
    # 顯示「－」，不是謊報成 0。
    it "shows zero counts for the current month, with only the ratio fields dashed out" do
      section = month_kpi_section(response.body)
      expect(section.scan('<span class="stat-value">0</span>').size).to eq(5) # 客訴／測試／總Bug／完成數／未結案
      expect(section.scan('<span class="stat-value">－</span>').size).to eq(3) # 攔截率／平均天數／SLA達標率
    end

    it "shows the empty state for the project breakdown (no issues started in 2026-09)" do
      expect(response.body).to include("所選期間無議題資料")
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
