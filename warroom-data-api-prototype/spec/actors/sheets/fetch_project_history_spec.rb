# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sheets::FetchProjectHistory do
  let(:actor) { described_class.new(ServiceActor::Result.to_result({})) }

  describe "#aggregate_ideal_series" do
    # 迴歸測試：對照 warroom-project-history-static-prototype 曾發現過的 bug——直接加總各議題
    # 「已含起訖錨點」的 ideal_series 時，不同議題的錨點日期不同，會在只有少數議題有資料的日期
    # 出現不該有的凹陷。這裡兩個議題的 due_date 刻意錯開（08/01 vs 08/22），驗證彙總後的序列
    # 單調不遞增（人時只會減少或持平，不會中途反彈）。
    let(:issues) do
      [
        {
          estimated_hours: 30, start_date: "2026-07-08", due_date: "2026-08-01",
          actual_series: [
            { date: "2026-07-08", hours: 22 }, { date: "2026-07-15", hours: 15 },
            { date: "2026-07-22", hours: 9 }, { date: "2026-07-29", hours: 4 },
            { date: "2026-08-05", hours: 0 }, { date: "2026-08-12", hours: 0 }
          ]
        },
        {
          estimated_hours: 40, start_date: "2026-07-08", due_date: "2026-08-22",
          actual_series: [
            { date: "2026-07-08", hours: 38 }, { date: "2026-07-15", hours: 35 },
            { date: "2026-07-22", hours: 33 }, { date: "2026-07-29", hours: 32 },
            { date: "2026-08-05", hours: 30 }, { date: "2026-08-12", hours: 29 }
          ]
        }
      ]
    end

    it "produces a monotonically non-increasing series with no dip at either issue's own anchor date" do
      series = actor.send(:aggregate_ideal_series, issues)
      hours = series.map { |p| p[:hours] }

      expect(hours).to eq(hours.sort.reverse)
    end

    it "excludes an issue with no legal start/due range from the sum instead of contributing 0" do
      issues_with_invalid = issues + [
        { estimated_hours: 999, start_date: nil, due_date: nil, actual_series: [ { date: "2026-07-08", hours: 5 } ] }
      ]

      series = actor.send(:aggregate_ideal_series, issues_with_invalid)
      first_point = series.find { |p| p[:date] == "2026-07-08" }

      # 999 沒有被計入（否則會遠大於兩個合法議題算出的理想值總和）
      expect(first_point[:hours]).to be < 100
    end
  end

  describe "#aggregate_work_hours" do
    it "derives weekly spent hours from consecutive deltas in actual_series (remaining decreases by the amount spent)" do
      issues = [
        {
          estimated_hours: 10,
          actual_series: [ { date: "2026-07-08", hours: 7 }, { date: "2026-07-15", hours: 3 }, { date: "2026-07-22", hours: 3 } ]
        }
      ]

      series = actor.send(:aggregate_work_hours, issues)

      expect(series).to eq([
        { date: "2026-07-08", hours: 3.0 },
        { date: "2026-07-15", hours: 4.0 },
        { date: "2026-07-22", hours: 0.0 }
      ])
    end

    it "sums spent hours across multiple issues on overlapping dates" do
      issues = [
        { estimated_hours: 10, actual_series: [ { date: "2026-07-08", hours: 7 } ] },
        { estimated_hours: 5, actual_series: [ { date: "2026-07-08", hours: 2 } ] }
      ]

      series = actor.send(:aggregate_work_hours, issues)

      expect(series).to eq([ { date: "2026-07-08", hours: 6.0 } ])
    end
  end

  describe "#complaint_status" do
    it "splits complaints into resolved/unresolved by the issue's own status, ignoring non-complaint issues" do
      issues = [
        { type: "Complaint", status: "已結束" },
        { type: "Complaint", status: "已解決" },
        { type: "Complaint", status: "新建立" },
        { type: "TestingBug", status: "新建立" }
      ]

      result = actor.send(:complaint_status, issues)

      expect(result[:resolved_count]).to eq(2)
      expect(result[:unresolved_count]).to eq(1)
      expect(result[:unresolved_list].size).to eq(1)
    end
  end

  describe "#monthly_testing_counts" do
    it "groups TestingBug issues by month (first day of month) and counts them" do
      issues = [
        { type: "TestingBug", start_date: "2026-08-11" },
        { type: "TestingBug", start_date: "2026-08-13" }, # same month
        { type: "TestingBug", start_date: "2026-09-02" }, # next month
        { type: "Complaint", start_date: "2026-08-11" }
      ]

      result = actor.send(:monthly_testing_counts, issues)

      expect(result).to eq([
        { date: "2026-08-01", count: 2 },
        { date: "2026-09-01", count: 1 }
      ])
    end
  end

  describe "#build_overview_rows" do
    let(:roster) { [ { project_name: "AG 亞炬", customer: "亞炬", pm: "呂俐禎", status: "維護" } ] }
    let(:progress_grouped) do
      {
        "AG 亞炬" => [
          { planned_completion_date: "2026-07-01", actual_completion_date: "2026-07-05", status: "完成" },
          { planned_completion_date: "2026-08-01", actual_completion_date: nil, status: "未完成" }
        ],
        "未知專案" => [
          { planned_completion_date: "2026-07-01", actual_completion_date: "2026-07-02", status: "完成" }
        ]
      }
    end

    # 沒有 year 篩選（nil）時不套用「該年度無對應議題就不列出」的排除規則，這裡先測基本的
    # roster join，不牽涉年度／307 可用性。
    it "joins roster customer/pm/status onto the 305 project name" do
      rows = actor.send(:build_overview_rows, roster, progress_grouped, [], nil, true)
      ag = rows.find { |r| r[:project_name] == "AG 亞炬" }

      expect(ag[:customer]).to eq("亞炬")
      expect(ag[:pm]).to eq("呂俐禎")
    end

    it "leaves customer/pm/status blank (not an error) when the 305 project has no roster match" do
      rows = actor.send(:build_overview_rows, roster, progress_grouped, [], nil, true)
      unknown = rows.find { |r| r[:project_name] == "未知專案" }

      expect(unknown[:customer]).to be_nil
      expect(unknown[:pm]).to be_nil
    end

    # 實測發現真實資料中 305 有時用 Roster 的「專案」全名、有時用「專案縮寫」，兩種都要能對上
    # （見 fetch_project_history.rb 的附註）。
    it "also joins when 305 uses the roster's abbreviation column instead of its full project name" do
      roster_with_abbreviation = [
        { project_name: "AG 亞炬", abbreviation: "亞炬 Platform", customer: "亞炬", pm: "呂俐禎", status: "維護" }
      ]
      grouped = { "亞炬 Platform" => [ { planned_completion_date: "2026-07-01", actual_completion_date: "2026-07-02", status: "完成" } ] }

      rows = actor.send(:build_overview_rows, roster_with_abbreviation, grouped, [], nil, true)

      expect(rows.first[:customer]).to eq("亞炬")
      expect(rows.first[:pm]).to eq("呂俐禎")
    end

    # 需求 1／1a：307 有對應議題時，甘特圖任務畫成真正的開發區間（start_date～due_date），
    # 並額外帶 assignees／progress_percent／overdue 供清單頁展開後的議題明細表格使用。
    it "builds gantt tasks from matched 307 burndown issues" do
      roster_with_burndown = [
        { project_name: "AG 亞炬", customer: "亞炬", pm: "呂俐禎", status: "維護", burndown_names_raw: "亞炬 PMS" }
      ]
      grouped = { "AG 亞炬" => [ { planned_completion_date: "2026-07-01", actual_completion_date: nil, status: "未完成" } ] }
      burndown_issues = [
        { project: "亞炬 PMS", issue_title: "API 效能優化", status: "in_progress", assignees: [ "王贊勛" ],
          start_date: "2026-07-08", due_date: "2026-08-22", estimated_hours: 40,
          actual_series: [ { date: "2026-07-08", hours: 30 } ] }
      ]

      rows = actor.send(:build_overview_rows, roster_with_burndown, grouped, burndown_issues, nil, true)
      ag = rows.first

      expect(ag[:tasks]).to eq([
        { task_name: "API 效能優化", assignees: [ "王贊勛" ], status: "in_progress",
          start_date: "2026-07-08", due_date: "2026-08-22", done: false,
          estimated_hours: 40, consumed_hours: 10.0, progress_percent: 25, overdue: false }
      ])
      expect(ag[:hours_estimated]).to eq(40.0)
      expect(ag[:hours_consumed]).to eq(10.0)
      expect(ag[:progress_percent]).to eq(25)
    end

    # 需求 1：307 無對應議題時，甘特圖那一列不畫任何色塊（不硬套 305 的單一完成日期畫出語意
    # 不對的假時程，見 design.md）——但沒有指定年度篩選時，專案本身仍會列出（只是 tasks 是空的）。
    it "returns an empty task list when no burndown issues match the project (no fake duration bars)" do
      rows = actor.send(:build_overview_rows, roster, progress_grouped, [], nil, true)
      ag = rows.find { |r| r[:project_name] == "AG 亞炬" }

      expect(ag[:tasks]).to eq([])
      expect(ag[:hours_estimated]).to be_nil
      expect(ag[:hours_consumed]).to be_nil
      expect(ag[:progress_percent]).to be_nil
      expect(ag[:has_overdue]).to be false
    end

    # 使用者要求：選定年度後，該年度沒有任何對應議題的專案直接不列出，而不是列出一個空白展開
    # 內容的卡片。
    it "excludes the project entirely when a year is selected and it has no matching issues that year" do
      roster_with_burndown = [ { project_name: "AG 亞炬", burndown_names_raw: "亞炬 PMS" } ]
      burndown_issues = [
        { project: "亞炬 PMS", issue_title: "去年的任務", status: "done",
          start_date: "2025-05-01", due_date: "2025-06-01", estimated_hours: 10, actual_series: [] }
      ]

      rows = actor.send(:build_overview_rows, roster_with_burndown, progress_grouped, burndown_issues, "2026", true)

      expect(rows.map { |r| r[:project_name] }).not_to include("AG 亞炬")
    end

    # 307 讀取失敗（duration_data_available: false）時不套用排除規則，維持既有降級慣例——
    # 全部專案照常列出，只是議題清單是空的，不讓一個非核心資料源的問題清空整個專案清單。
    it "does not exclude any project when duration data is unavailable, even with a year filter selected" do
      rows = actor.send(:build_overview_rows, roster, progress_grouped, [], "2026", false)

      expect(rows.map { |r| r[:project_name] }).to include("AG 亞炬", "未知專案")
      expect(rows.find { |r| r[:project_name] == "AG 亞炬" }[:tasks]).to eq([])
    end

    # 需求：年度篩選也套用在議題清單本身，只保留該年度開案的議題。
    it "filters the task list itself down to issues that started in the selected year" do
      roster_with_burndown = [ { project_name: "AG 亞炬", burndown_names_raw: "亞炬 PMS" } ]
      burndown_issues = [
        { project: "亞炬 PMS", issue_title: "去年的任務", status: "done",
          start_date: "2025-05-01", due_date: "2025-06-01", estimated_hours: 10, actual_series: [] },
        { project: "亞炬 PMS", issue_title: "今年的任務", status: "in_progress",
          start_date: "2026-05-01", due_date: "2026-06-01", estimated_hours: 10, actual_series: [] }
      ]

      rows = actor.send(:build_overview_rows, roster_with_burndown, progress_grouped, burndown_issues, "2026", true)
      ag = rows.find { |r| r[:project_name] == "AG 亞炬" }

      expect(ag[:tasks].map { |t| t[:task_name] }).to eq([ "今年的任務" ])
    end

    # 需求 2.2／3.1：沒有 actual_series 資料點的議題不計入工時 KPI 的分子分母，不得顯示成 0%。
    it "excludes duration tasks with no actual_series data from the hours KPI instead of counting them as 0" do
      roster_with_burndown = [
        { project_name: "AG 亞炬", burndown_names_raw: "亞炬 PMS" }
      ]
      burndown_issues = [
        { project: "亞炬 PMS", issue_title: "剛開案的任務", status: "in_progress",
          start_date: "2026-08-01", due_date: "2026-09-01", estimated_hours: 20, actual_series: [] }
      ]

      rows = actor.send(:build_overview_rows, roster_with_burndown, progress_grouped, burndown_issues, nil, true)
      ag = rows.first

      expect(ag[:tasks].first[:consumed_hours]).to be_nil
      expect(ag[:tasks].first[:progress_percent]).to be_nil
      expect(ag[:hours_estimated]).to be_nil
      expect(ag[:hours_consumed]).to be_nil
      expect(ag[:progress_percent]).to be_nil
    end

    # 需求 4.3／4.4：含逾期未完成任務的專案，has_overdue 為 true。
    it "marks has_overdue true for a project with an overdue duration task past its due_date" do
      travel_to Date.new(2026, 9, 1) do
        roster_with_burndown = [ { project_name: "AG 亞炬", burndown_names_raw: "亞炬 PMS" } ]
        burndown_issues = [
          { project: "亞炬 PMS", issue_title: "逾期任務", status: "in_progress",
            start_date: "2026-07-08", due_date: "2026-08-01", estimated_hours: 10, actual_series: [] }
        ]

        rows = actor.send(:build_overview_rows, roster_with_burndown, progress_grouped, burndown_issues, nil, true)

        expect(rows.first[:has_overdue]).to be true
        expect(rows.first[:tasks].first[:overdue]).to be true
      end
    end
  end

  describe "#build_detail" do
    let(:burndown_issues) do
      [
        { project: "亞炬 PMS", estimated_hours: 10, start_date: "2026-07-08", due_date: "2026-08-01",
          actual_series: [ { date: "2026-07-08", hours: 5 } ] },
        { project: "亞炬 Wms", estimated_hours: 8, start_date: "2026-07-08", due_date: "2026-08-01",
          actual_series: [ { date: "2026-07-08", hours: 4 } ] },
        { project: "AMAS Cloud", estimated_hours: 20, start_date: "2026-07-08", due_date: "2026-08-01",
          actual_series: [ { date: "2026-07-08", hours: 15 } ] }
      ]
    end

    # 307 的一個專案在人工維護的 Roster「307對應專案」欄裡，實務資料證實有時用空白分隔、有時
    # 用逗號、甚至換行分隔，且每個 307 名稱本身也含空白（如「亞炬 PMS」）無法用分隔符可靠拆開，
    # 故比對邏輯改用「307 真實名稱是否為這欄文字的子字串」，不管分隔符是什麼都能正確判斷。
    it "matches burndown issues whose project name appears anywhere in the roster's burndown_names_raw text, regardless of delimiter" do
      roster_row = { project_name: "AG 亞炬", customer: "亞炬", burndown_names_raw: "亞炬 PMS\n亞炬 Wms" }

      detail = actor.send(:build_detail, "亞炬 Platform", roster_row, burndown_issues, [], nil)

      expect(detail[:work_hours_series]).not_to be_empty
      total_hours = detail[:actual_series].sum { |p| p[:hours] }
      expect(total_hours).to eq(9.0) # 只有亞炬 PMS(5) + 亞炬 Wms(4)，AMAS Cloud 不該被算進來
    end

    it "falls back to exact project match when the roster row has no burndown_names_raw" do
      roster_row = { project_name: "AG 亞炬", customer: "亞炬", burndown_names_raw: "" }

      detail = actor.send(:build_detail, "亞炬 PMS", roster_row, burndown_issues, [], nil)

      expect(detail[:actual_series].sum { |p| p[:hours] }).to eq(5.0) # 只精確比對到「亞炬 PMS」這一項
    end

    it "filters the three time-series charts by year but leaves complaint_summary unaffected" do
      roster_row = { project_name: "AG 亞炬", customer: "亞炬", burndown_names_raw: "" }
      issues = [
        { project: "AG 亞炬", type: "Complaint", status: "新建立", start_date: "2025-01-01" }
      ]

      detail = actor.send(:build_detail, "亞炬 PMS", roster_row, burndown_issues, issues, "2026")

      expect(detail[:selected_year]).to eq("2026")
      expect(detail[:actual_series]).not_to be_empty # 2026-07-08 屬於 2026
      expect(detail[:complaint_summary][:unresolved_count]).to eq(1) # 不受年度篩選影響
    end

    it "excludes points outside the selected year" do
      roster_row = { project_name: "AG 亞炬", customer: "亞炬", burndown_names_raw: "" }

      detail = actor.send(:build_detail, "亞炬 PMS", roster_row, burndown_issues, [], "2025")

      expect(detail[:actual_series]).to be_empty # 資料都在 2026，2025 篩選後應該是空的
    end
  end

  describe "#call" do
    let(:roster_result) { double("Result", success?: true, roster: []) }
    let(:progress_result) { double("Result", success?: true, grouped_data: {}) }
    let(:issue_result) { double("Result", success?: true, issues: []) }
    let(:burndown_result) { double("Result", success?: true, issues: []) }

    before do
      allow(Sheets::FetchProjectRoster).to receive(:result).and_return(roster_result)
      allow(Sheets::FetchProjectProgress).to receive(:result).and_return(progress_result)
      allow(Sheets::FetchIssueDashboard).to receive(:result).and_return(issue_result)
      allow(Sheets::FetchProjectBurndown).to receive(:result).and_return(burndown_result)
    end

    it "degrades gracefully when only the roster actor fails: page still succeeds, customer/pm blank" do
      failed = double("Result", success?: false, failure_code: :access_denied, message: "no access")
      allow(Sheets::FetchProjectRoster).to receive(:result).and_return(failed)
      allow(Sheets::FetchProjectProgress).to receive(:result)
        .and_return(double("Result", success?: true, grouped_data: { "AG 亞炬" => [
          { planned_completion_date: "2026-07-01", actual_completion_date: "2026-07-02" }
        ] }))

      result = described_class.result

      expect(result).to be_success
      expect(result.roster_unavailable).to be true
      expect(result.overview_rows.first[:customer]).to be_nil
    end

    it "still fails the whole request when 305 fails" do
      failed = double("Result", success?: false, failure_code: :access_denied, message: "no access")
      allow(Sheets::FetchProjectProgress).to receive(:result).and_return(failed)

      result = described_class.result

      expect(result).not_to be_success
      expect(result.failure_code).to eq(:access_denied)
    end

    # 306（議題明細）只有縱向歷程（帶 project 參數）才用得到，一個跟總覽無關的資料源出問題，
    # 不該連總覽都看不到。307 現在橫向總覽的甘特圖也需要（需求 1），故即使沒有選定 project 也
    # 會呼叫（見下方另一組測試），跟 306 的行為不同。
    it "does not call 306 at all when no project is given (overview only needs 305 + 307)" do
      described_class.result(project: nil)

      expect(Sheets::FetchIssueDashboard).not_to have_received(:result)
    end

    it "overview still succeeds even when 306 would fail, as long as no project is selected" do
      allow(Sheets::FetchIssueDashboard).to receive(:result)
        .and_return(double("Result", success?: false, failure_code: :access_denied, message: "no access"))

      result = described_class.result(project: nil)

      expect(result).to be_success
    end

    # 需求 1.3／5.1：307 失敗不擋總覽頁，甘特圖降級為全部專案皆無色塊（不硬套 305 檢查點畫出
    # 語意不對的假時程），gantt_duration_unavailable 設為 true 供畫面顯示提示。
    it "degrades gracefully when 307 fails and no project is selected: overview still succeeds with empty gantt tasks" do
      allow(Sheets::FetchProjectBurndown).to receive(:result)
        .and_return(double("Result", success?: false, failure_code: :access_denied, message: "no access"))
      allow(Sheets::FetchProjectProgress).to receive(:result)
        .and_return(double("Result", success?: true, grouped_data: { "AG 亞炬" => [
          { planned_completion_date: "2026-07-01", actual_completion_date: "2026-07-02", status: "完成" }
        ] }))

      result = described_class.result(project: nil)

      expect(result).to be_success
      expect(result.gantt_duration_unavailable).to be true
      expect(result.overview_rows.first[:tasks]).to eq([])
    end

    # 需求 1.3a：已選定 project 時（縱向歷程本來就依賴 307），307 失敗仍讓整體請求失敗，
    # 跟換源前的既有行為一致，不新增例外。
    it "still fails the whole request when 307 fails and a project is selected" do
      allow(Sheets::FetchProjectBurndown).to receive(:result)
        .and_return(double("Result", success?: false, failure_code: :access_denied, message: "no access"))

      result = described_class.result(project: "AG 亞炬")

      expect(result).not_to be_success
      expect(result.failure_code).to eq(:access_denied)
    end

    it "fails the detail request when 306 fails (306/307 are required once a project is selected)" do
      allow(Sheets::FetchIssueDashboard).to receive(:result)
        .and_return(double("Result", success?: false, failure_code: :access_denied, message: "no access"))

      result = described_class.result(project: "AG 亞炬")

      expect(result).not_to be_success
      expect(result.failure_code).to eq(:access_denied)
    end

    it "computes overview_rows only (no detail) when no project is given" do
      result = described_class.result(project: nil)

      expect(result).to be_success
      expect(result.overview_rows).to eq([])
      expect(result.detail).to be_nil
    end

    it "computes both overview_rows and detail when a project is given" do
      result = described_class.result(project: "AG 亞炬")

      expect(result).to be_success
      expect(result.overview_rows).to eq([])
      expect(result.detail).to include(:work_hours_series, :ideal_series, :actual_series, :testing_trend, :complaint_summary)
    end
  end
end
