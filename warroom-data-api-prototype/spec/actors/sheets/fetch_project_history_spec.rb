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

  describe "#weekly_testing_counts" do
    it "groups TestingBug issues by ISO week (Monday) and counts them" do
      issues = [
        { type: "TestingBug", start_date: "2026-08-11" }, # Tuesday, week of 2026-08-10
        { type: "TestingBug", start_date: "2026-08-13" }, # Thursday, same week
        { type: "TestingBug", start_date: "2026-08-19" }, # next week
        { type: "Complaint", start_date: "2026-08-11" }
      ]

      result = actor.send(:weekly_testing_counts, issues)

      expect(result).to eq([
        { date: "2026-08-10", count: 2 },
        { date: "2026-08-17", count: 1 }
      ])
    end
  end

  describe "#build_overview_rows" do
    let(:roster) { [ { project_name: "AG 亞炬", customer: "亞炬", pm: "呂俐禎", status: "維護" } ] }
    let(:progress_grouped) do
      {
        "AG 亞炬" => [
          { planned_completion_date: "2026-07-01", actual_completion_date: "2026-07-05" },
          { planned_completion_date: "2026-08-01", actual_completion_date: nil }
        ],
        "未知專案" => [
          { planned_completion_date: "2026-07-01", actual_completion_date: "2026-07-02" }
        ]
      }
    end

    it "joins roster customer/pm/status onto the 305 project name and marks a project ongoing" do
      rows = actor.send(:build_overview_rows, roster, progress_grouped)
      ag = rows.find { |r| r[:project_name] == "AG 亞炬" }

      expect(ag[:customer]).to eq("亞炬")
      expect(ag[:pm]).to eq("呂俐禎")
      expect(ag[:planned_completion_date]).to eq("2026-08-01")
      expect(ag[:actual_completion_date]).to be_nil # 仍有任務未完成，視為進行中
    end

    it "leaves customer/pm/status blank (not an error) when the 305 project has no roster match" do
      rows = actor.send(:build_overview_rows, roster, progress_grouped)
      unknown = rows.find { |r| r[:project_name] == "未知專案" }

      expect(unknown[:customer]).to be_nil
      expect(unknown[:pm]).to be_nil
      expect(unknown[:actual_completion_date]).to eq("2026-07-02")
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

    it "fails the whole request when the roster actor fails, without calling the other actors' data" do
      failed = double("Result", success?: false, failure_code: :access_denied, message: "no access")
      allow(Sheets::FetchProjectRoster).to receive(:result).and_return(failed)

      result = described_class.result

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
