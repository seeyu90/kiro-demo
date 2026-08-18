# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sheets::FetchProjectHistory do
  let(:actor) { described_class.new(ServiceActor::Result.to_result({})) }

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

  describe "#call" do
    let(:roster_result) { double("Result", success?: true, roster: []) }
    let(:progress_result) { double("Result", success?: true, grouped_data: {}) }
    let(:burndown_result) { double("Result", success?: true, issues: []) }

    before do
      allow(Sheets::FetchProjectRoster).to receive(:result).and_return(roster_result)
      allow(Sheets::FetchProjectProgress).to receive(:result).and_return(progress_result)
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

    # 需求 1.3／5.1：307 失敗不擋總覽頁，甘特圖降級為全部專案皆無色塊（不硬套 305 檢查點畫出
    # 語意不對的假時程），gantt_duration_unavailable 設為 true 供畫面顯示提示。
    it "degrades gracefully when 307 fails: overview still succeeds with empty gantt tasks" do
      allow(Sheets::FetchProjectBurndown).to receive(:result)
        .and_return(double("Result", success?: false, failure_code: :access_denied, message: "no access"))
      allow(Sheets::FetchProjectProgress).to receive(:result)
        .and_return(double("Result", success?: true, grouped_data: { "AG 亞炬" => [
          { planned_completion_date: "2026-07-01", actual_completion_date: "2026-07-02", status: "完成" }
        ] }))

      result = described_class.result

      expect(result).to be_success
      expect(result.gantt_duration_unavailable).to be true
      expect(result.overview_rows.first[:tasks]).to eq([])
    end

    it "computes overview_rows and the overview_years dropdown source" do
      allow(Sheets::FetchProjectBurndown).to receive(:result)
        .and_return(double("Result", success?: true, issues: [ { start_date: "2026-03-01" }, { start_date: "2025-01-01" } ]))

      result = described_class.result

      expect(result).to be_success
      expect(result.overview_rows).to eq([])
      expect(result.overview_years).to eq(%w[2026 2025])
    end
  end
end
