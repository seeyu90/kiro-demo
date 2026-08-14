require "rails_helper"

RSpec.describe "Issues", type: :request do
  let(:month_kpi_rows) do
    [
      %w[year_month 客訴 測試 總Bug 攔截率 完成數 未結案 平均天數 SLA達標率 Top3],
      ["2026-07", "28", "7", "35", "20", "10", "7", "2.61", "10.71", "王贊勛:20"],
      ["2026-08", "15", "9", "24", "37.5", "6", "3", "3.1", "25", "王贊勛:8"]
    ]
  end

  let(:daily_kpi_rows) do
    [
      %w[日期 客訴 測試 其他 總計],
      ["2026-08-01", "0", "1", "0", "1"],
      ["2026-08-13", "0", "0", "0", "0"]
    ]
  end

  let(:issue_rows) do
    [
      %w[issue_id subject type tracker status assigned_to start_date due_date work_days sheet_name project],
      ["4547", "未匯入行事曆", "Complaint", "臭蟲", "已結束", "黃靖益",
       "2026/1/2", "2026/1/6", "3", "raw_2026", "Virtuous HRM"],
      ["5165", "白名單申請時間錯誤", "TestingBug", "臭蟲", "新建立", "蔡秉逸",
       "2026/8/12", "", "", "raw_2026", "Virtuous HRM"],
      ["3058", "結案小工序DeadlockVictim", "Other", "臭蟲", "已暫停", "王贊勛",
       "2024/4/29", "", "", "raw_2024", "AG 亞炬"]
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

    it "defaults the month select to the latest year_month" do
      expect(response.body).to match(/<option [^>]*selected="selected"[^>]*>2026-08<\/option>/)
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
      # 確認「不受此處月份選擇影響」字樣只出現一次（在月度 KPI 區塊），不會出現在議題明細篩選附近造成混淆
      expect(response.body.scan("不受此處月份選擇影響").size).to eq(1)
    end

    it "shows the project breakdown table" do
      expect(response.body).to include("Virtuous HRM")
      expect(response.body).to include("AG 亞炬")
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

  describe "GET /issues?month=2026-07" do
    before { get "/issues", params: { month: "2026-07", status: "" } }

    it "shows KPI values for the selected month, not the latest" do
      expect(response.body).to include("20.0") # block_rate for 2026-07
    end

    it "does not change the project breakdown regardless of month (需求 3a.2)" do
      # project_breakdown 恆為全部 issues 的分組統計，不受 month 篩選影響
      expect(response.body).to include("Virtuous HRM")
      expect(response.body).to include("AG 亞炬")
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
end
