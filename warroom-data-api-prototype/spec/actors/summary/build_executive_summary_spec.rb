# frozen_string_literal: true

require "rails_helper"

RSpec.describe Summary::BuildExecutiveSummary do
  include ActiveSupport::Testing::TimeHelpers

  let(:actor) { described_class.new(ServiceActor::Result.to_result({})) }

  describe "#health_for" do
    it "is critical when there is at least one overdue task, regardless of burndown/due-this-week" do
      expect(actor.send(:health_for, 1, nil, 0)).to eq(:critical)
    end

    it "is critical when burndown is over, even with zero overdue tasks" do
      expect(actor.send(:health_for, 0, :over, 0)).to eq(:critical)
    end

    it "is at_risk when nothing is overdue/over but something is due this week" do
      expect(actor.send(:health_for, 0, nil, 1)).to eq(:at_risk)
    end

    it "is at_risk when burndown is at_risk, even with nothing due this week" do
      expect(actor.send(:health_for, 0, :at_risk, 0)).to eq(:at_risk)
    end

    it "is on_track when there is no overdue, no due-this-week, and no burndown risk" do
      expect(actor.send(:health_for, 0, nil, 0)).to eq(:on_track)
    end

    it "is on_track when burndown status is merely unknown (not a risk signal)" do
      expect(actor.send(:health_for, 0, :unknown, 0)).to eq(:on_track)
    end
  end

  describe "#build_phase_exceptions" do
    let(:cards) do
      [
        { project: "HRM", issue_id: "1", issue_name: "請假模組", customer: "AMAS", pm: "楊欣翰", status: "延誤未完成",
          stages: [ { stage: "開發", primary: { status: "延誤未完成", planned_date: "2026-08-01" }, history: [] } ] },
        { project: "HRM", issue_id: "2", issue_name: "報表模組", customer: "AMAS", pm: "楊欣翰", status: "暫緩",
          stages: [ { stage: "開案", primary: { status: "暫緩", planned_date: "2026-08-01" }, history: [] } ] },
        { project: "HRM", issue_id: "3", issue_name: "已完成模組", customer: "AMAS", pm: "楊欣翰", status: "完成",
          stages: [ { stage: "發布", primary: { status: "完成", planned_date: "2026-08-01" }, history: [] } ] },
        { project: "HRM", issue_id: "4", issue_name: "曾延誤但已完成", customer: "AMAS", pm: "楊欣翰", status: "延誤已完成",
          stages: [ { stage: "發布", primary: { status: "延誤已完成", planned_date: "2026-08-01" }, history: [] } ] },
        { project: "HRM", issue_id: "5", issue_name: "很久以前的未完成項目", customer: "AMAS", pm: "楊欣翰", status: "未完成",
          stages: [ { stage: "開發", primary: { status: "未完成", planned_date: "2020-01-01" }, history: [] } ] },
        { project: "HRM", issue_id: "6", issue_name: "沒有日期的未完成項目", customer: "AMAS", pm: "楊欣翰", status: "未完成",
          stages: [ { stage: "開發", primary: { status: "未完成", planned_date: nil }, history: [] } ] }
      ]
    end

    it "includes only cards whose current status needs attention (延誤未完成／未完成) within the last 6 months" do
      travel_to Date.new(2026, 9, 1) do
        exceptions = actor.send(:build_phase_exceptions, cards)

        expect(exceptions.map { |e| e[:issue_label] }).to contain_exactly("請假模組")
      end
    end

    it "excludes completed and 延誤已完成 cards — already done, not a live risk" do
      travel_to Date.new(2026, 9, 1) do
        exceptions = actor.send(:build_phase_exceptions, cards)

        expect(exceptions.map { |e| e[:issue_label] }).not_to include("已完成模組", "曾延誤但已完成")
      end
    end

    it "excludes 暫緩 cards — deliberately paused, not something the CEO needs to see" do
      travel_to Date.new(2026, 9, 1) do
        exceptions = actor.send(:build_phase_exceptions, cards)

        expect(exceptions.map { |e| e[:issue_label] }).not_to include("報表模組")
      end
    end

    it "excludes a needs-attention card whose current-stage planned_date is older than 6 months" do
      travel_to Date.new(2026, 9, 1) do
        exceptions = actor.send(:build_phase_exceptions, cards)

        expect(exceptions.map { |e| e[:issue_label] }).not_to include("很久以前的未完成項目")
      end
    end

    it "excludes a needs-attention card with no planned_date to judge recency by (conservative: hide, not show)" do
      travel_to Date.new(2026, 9, 1) do
        exceptions = actor.send(:build_phase_exceptions, cards)

        expect(exceptions.map { |e| e[:issue_label] }).not_to include("沒有日期的未完成項目")
      end
    end
  end

  describe "#build_projects" do
    let(:roster) { [ { project_name: "AG 亞炬", abbreviation: "亞炬 Platform", customer: "亞炬", pm: "呂俐禎", burndown_names_raw: "亞炬 PMS" } ] }

    it "joins roster customer/pm onto the 305 project name, same matching rule as project_history" do
      progress_grouped = { "AG 亞炬" => [ { task_name: "A", status: "未完成", planned_completion_date: nil, owner: "王贊勛" } ] }

      rows = actor.send(:build_projects, roster, progress_grouped, [], nil)
      ag = rows.find { |r| r[:project_name] == "AG 亞炬" }

      expect(ag[:customer]).to eq("亞炬")
      expect(ag[:pm]).to eq("呂俐禎")
    end

    it "leaves customer/pm nil (not critical/an error) when there is no roster match" do
      progress_grouped = { "未知專案" => [ { task_name: "A", status: "未完成", planned_completion_date: nil, owner: "王贊勛" } ] }

      rows = actor.send(:build_projects, roster, progress_grouped, [], nil)
      unknown = rows.find { |r| r[:project_name] == "未知專案" }

      expect(unknown[:customer]).to be_nil
      expect(unknown[:pm]).to be_nil
    end

    it "counts overdue 305 tasks and marks the project critical" do
      travel_to Date.new(2026, 9, 1) do
        progress_grouped = {
          "AG 亞炬" => [
            { task_name: "逾期任務", status: "未完成", planned_completion_date: "2026-08-01", owner: "王贊勛", delay_days: 31 },
            { task_name: "已完成任務", status: "完成", planned_completion_date: "2026-08-01", owner: "王贊勛" }
          ]
        }

        rows = actor.send(:build_projects, roster, progress_grouped, [], nil)
        ag = rows.first

        expect(ag[:health]).to eq(:critical)
        expect(ag[:overdue_task_count]).to eq(1)
        expect(ag[:overdue_tasks]).to eq([ { task_name: "逾期任務", owner: "王贊勛", delay_days: 31 } ])
        expect(ag[:task_completion_percent]).to eq(50)
      end
    end

    it "matches 307 burndown issues via roster's burndown_names_raw and reflects burndown risk in health" do
      progress_grouped = { "AG 亞炬" => [ { task_name: "A", status: "未完成", planned_completion_date: nil, owner: "王贊勛" } ] }
      burndown_issues = [
        { project: "亞炬 PMS", issue_title: "超支議題", status: "in_progress", assignees: [ "王贊勛" ],
          estimated_hours: 10, actual_series: [ { date: "2026-08-01", hours: -5 } ],
          ideal_series: [ { date: "2026-08-01", hours: 0 } ] }
      ]

      rows = actor.send(:build_projects, roster, progress_grouped, burndown_issues, nil)
      ag = rows.first

      expect(ag[:burndown_flag]).to eq(:over)
      expect(ag[:health]).to eq(:critical)
      expect(ag[:at_risk_burndown_issues].first[:issue_title]).to eq("超支議題")
    end

    it "ignores done burndown issues when computing the project's live burndown_flag" do
      progress_grouped = { "AG 亞炬" => [ { task_name: "A", status: "完成", planned_completion_date: nil, owner: "王贊勛" } ] }
      burndown_issues = [
        { project: "亞炬 PMS", issue_title: "已完成議題", status: "done",
          estimated_hours: 10, actual_series: [ { date: "2026-08-01", hours: -5 } ], ideal_series: [] }
      ]

      rows = actor.send(:build_projects, roster, progress_grouped, burndown_issues, nil)

      expect(rows.first[:burndown_flag]).to be_nil
      expect(rows.first[:health]).to eq(:on_track)
    end

    it "sorts critical projects first, then at_risk, then on_track" do
      travel_to Date.new(2026, 9, 1) do
        progress_grouped = {
          "綠燈專案" => [ { task_name: "A", status: "完成", planned_completion_date: "2026-08-01", owner: "x" } ],
          "紅燈專案" => [ { task_name: "B", status: "未完成", planned_completion_date: "2026-08-01", owner: "x" } ],
          "黃燈專案" => [ { task_name: "C", status: "未完成", planned_completion_date: (Date.new(2026, 9, 1) + 2).to_s, owner: "x" } ]
        }

        rows = actor.send(:build_projects, [], progress_grouped, [], nil)

        expect(rows.map { |r| r[:project_name] }).to eq(%w[紅燈專案 黃燈專案 綠燈專案])
      end
    end
  end

  describe "#group_phase_exceptions_by_customer" do
    let(:exceptions) do
      [
        { customer: "AMAS" },
        { customer: "AMAS" },
        { customer: nil },
        { customer: "舊振南" }
      ]
    end

    it "groups by customer with a count, sorted by count descending" do
      groups = actor.send(:group_phase_exceptions_by_customer, exceptions)

      expect(groups.first).to include(customer: "AMAS", count: 2)
      expect(groups.map { |g| g[:customer] }).to include("未知客戶", "舊振南")
    end

    it "buckets a blank customer under 未知客戶 instead of dropping it" do
      groups = actor.send(:group_phase_exceptions_by_customer, exceptions)

      unknown = groups.find { |g| g[:customer] == "未知客戶" }
      expect(unknown[:count]).to eq(1)
    end
  end

  describe "#build_last_week_summary" do
    it "counts a 305 task as completed last week only when its actual_completion_date falls in last week's Mon-Sun range" do
      travel_to Date.new(2026, 9, 8) do # 本週一為 09/07，上週為 08/31～09/06
        progress_grouped = {
          "AG 亞炬" => [
            { task_name: "上週完成", status: "完成", actual_completion_date: "2026-09-03", owner: "王贊勛" },
            { task_name: "更早完成", status: "完成", actual_completion_date: "2026-08-20", owner: "王贊勛" },
            { task_name: "還沒完成", status: "未完成", actual_completion_date: nil, owner: "王贊勛" }
          ]
        }

        summary = actor.send(:build_last_week_summary, progress_grouped, [], nil)

        expect(summary[:completed_task_count]).to eq(1)
        expect(summary[:completed_tasks].first[:task_name]).to eq("上週完成")
      end
    end

    it "counts a phase-tracking stage as completed last week only when its actual_date falls in last week's range" do
      travel_to Date.new(2026, 9, 8) do
        phase_cards = [
          { project: "HRM", issue_id: "1", issue_name: "報表模組", customer: "AMAS",
            stages: [ { stage: "開發", primary: { actual_date: "2026-09-02" } },
                      { stage: "測試", primary: { actual_date: "2026-08-10" } } ] }
        ]

        summary = actor.send(:build_last_week_summary, {}, phase_cards, nil)

        expect(summary[:completed_stage_count]).to eq(1)
        expect(summary[:completed_stages].first[:stage]).to eq("開發")
      end
    end

    it "returns zero counts (not an error) when nothing completed last week" do
      travel_to Date.new(2026, 9, 8) do
        summary = actor.send(:build_last_week_summary, {}, [], nil)

        expect(summary[:completed_task_count]).to eq(0)
        expect(summary[:completed_stage_count]).to eq(0)
      end
    end

    it "sums 306 daily_kpi complaint counts whose date falls in last week's range" do
      travel_to Date.new(2026, 9, 8) do
        issue_dashboard_result = double("Result", daily_kpi: [
          { date: "2026-09-03", complaint: 2 },
          { date: "2026-09-05", complaint: 1 },
          { date: "2026-08-20", complaint: 5 }
        ])

        summary = actor.send(:build_last_week_summary, {}, [], issue_dashboard_result)

        expect(summary[:complaint_count]).to eq(3)
      end
    end

    it "reports complaint_count as nil (not 0) when 306 is unavailable — unknown, not confirmed zero" do
      travel_to Date.new(2026, 9, 8) do
        summary = actor.send(:build_last_week_summary, {}, [], nil)

        expect(summary[:complaint_count]).to be_nil
      end
    end
  end

  describe "#call" do
    let(:roster_result) { double("Result", success?: true, roster: []) }
    let(:progress_result) { double("Result", success?: true, grouped_data: {}) }
    let(:burndown_result) { double("Result", success?: true, issues: []) }
    let(:issue_dashboard_result) do
      double("Result", success?: true, project_breakdown: [], selected_month_record: nil,
                        issue_kpis: { urgent_complaints: 0 }, daily_kpi: [])
    end
    let(:phase_tracking_result) { double("Result", success?: true, cards: []) }

    before do
      allow(Sheets::FetchProjectRoster).to receive(:result).and_return(roster_result)
      allow(Sheets::FetchProjectProgress).to receive(:result).and_return(progress_result)
      allow(Sheets::FetchProjectBurndown).to receive(:result).and_return(burndown_result)
      allow(Sheets::FetchIssueDashboard).to receive(:result).and_return(issue_dashboard_result)
      allow(Sheets::FetchPhaseTracking).to receive(:result).and_return(phase_tracking_result)
    end

    it "fails the whole page when 305 (the core data source) fails" do
      failed = double("Result", success?: false, failure_code: :access_denied, message: "no access")
      allow(Sheets::FetchProjectProgress).to receive(:result).and_return(failed)

      result = described_class.result

      expect(result).not_to be_success
      expect(result.failure_code).to eq(:access_denied)
    end

    it "degrades gracefully when roster fails: page still succeeds with roster_unavailable true" do
      failed = double("Result", success?: false, failure_code: :access_denied, message: "no access")
      allow(Sheets::FetchProjectRoster).to receive(:result).and_return(failed)

      result = described_class.result

      expect(result).to be_success
      expect(result.roster_unavailable).to be true
    end

    it "degrades gracefully when 307/306/phase tracking individually fail" do
      allow(Sheets::FetchProjectBurndown).to receive(:result)
        .and_return(double("Result", success?: false, failure_code: :internal_error, message: "boom"))
      allow(Sheets::FetchIssueDashboard).to receive(:result)
        .and_return(double("Result", success?: false, failure_code: :internal_error, message: "boom"))
      allow(Sheets::FetchPhaseTracking).to receive(:result)
        .and_return(double("Result", success?: false, failure_code: :internal_error, message: "boom"))

      result = described_class.result

      expect(result).to be_success
      expect(result.burndown_unavailable).to be true
      expect(result.issues_unavailable).to be true
      expect(result.phase_tracking_unavailable).to be true
      expect(result.portfolio[:sla_rate]).to be_nil
      expect(result.portfolio[:urgent_complaint_count]).to be_nil
    end

    it "computes portfolio counts from the projects list" do
      allow(Sheets::FetchProjectProgress).to receive(:result).and_return(
        double("Result", success?: true, grouped_data: {
          "A" => [ { task_name: "t", status: "完成", planned_completion_date: nil, owner: "x" } ]
        })
      )

      result = described_class.result

      expect(result.portfolio[:project_count]).to eq(1)
      expect(result.portfolio[:green_count]).to eq(1)
      expect(result.portfolio[:red_count]).to eq(0)
    end
  end
end
