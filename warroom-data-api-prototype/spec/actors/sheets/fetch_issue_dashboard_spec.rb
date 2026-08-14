# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sheets::FetchIssueDashboard do
  let(:actor) { described_class.new(ServiceActor::Result.to_result({})) }

  describe "#parse_month_kpi" do
    let(:header) { %w[year_month 客訴 測試 總Bug 攔截率 完成數 未結案 平均天數 SLA達標率 Top3] }

    it "maps columns to the expected keys, ignoring the Top3 column" do
      rows = [
        header,
        ["2026-08", "15", "9", "24", "37.5", "6", "3", "3.1", "25", "王贊勛:8 | 黃靖益:5"]
      ]

      result = actor.send(:parse_month_kpi, rows)

      expect(result).to eq([
        {
          year_month: "2026-08",
          complaint: 15,
          testing: 9,
          total_bug: 24,
          block_rate: 37.5,
          completed: 6,
          unresolved: 3,
          avg_days: 3.1,
          sla_rate: 25.0
        }
      ])
    end

    it "does not include a :top3 key in the output" do
      rows = [header, ["2026-08", "15", "9", "24", "37.5", "6", "3", "3.1", "25", "王贊勛:8"]]

      result = actor.send(:parse_month_kpi, rows)

      expect(result.first.keys).not_to include(:top3)
    end

    it "skips blank rows" do
      rows = [
        header,
        ["2026-08", "15", "9", "24", "37.5", "6", "3", "3.1", "25", "王贊勛:8"],
        [],
        [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil],
        ["", "", "", "", "", "", "", "", "", ""]
      ]

      result = actor.send(:parse_month_kpi, rows)

      expect(result.size).to eq(1)
    end

    it "skips a row whose year_month is blank" do
      rows = [header, ["", "15", "9", "24", "37.5", "6", "3", "3.1", "25", ""]]

      expect(actor.send(:parse_month_kpi, rows)).to eq([])
    end

    it "keeps a non-numeric value as-is instead of raising" do
      rows = [header, ["2026-08", "TBD", "9", "24", "37.5", "6", "3", "3.1", "25", ""]]

      result = actor.send(:parse_month_kpi, rows)

      expect(result.first[:complaint]).to eq("TBD")
    end

    it "returns an empty array for nil or header-only input" do
      expect(actor.send(:parse_month_kpi, nil)).to eq([])
      expect(actor.send(:parse_month_kpi, [header])).to eq([])
    end
  end

  describe "#parse_daily_kpi" do
    let(:header) { %w[日期 客訴 測試 其他 總計] }

    it "maps columns to the expected keys" do
      rows = [header, ["2026-08-13", "0", "1", "0", "1"]]

      result = actor.send(:parse_daily_kpi, rows)

      expect(result).to eq([
        { date: "2026-08-13", complaint: 0, testing: 1, other: 0, total: 1 }
      ])
    end

    it "treats an empty total as 0 instead of nil" do
      rows = [header, ["2026-08-13", "0", "0", "0", ""]]

      result = actor.send(:parse_daily_kpi, rows)

      expect(result.first[:total]).to eq(0)
    end

    it "sorts records by date ascending regardless of source order" do
      rows = [
        header,
        ["2026-08-13", "0", "0", "0", "0"],
        ["2026-08-01", "1", "0", "0", "1"],
        ["2026-08-06", "0", "2", "0", "2"]
      ]

      result = actor.send(:parse_daily_kpi, rows)

      expect(result.map { |r| r[:date] }).to eq(["2026-08-01", "2026-08-06", "2026-08-13"])
    end

    it "skips blank rows" do
      rows = [header, ["2026-08-13", "0", "0", "0", "0"], [], [nil, nil, nil, nil, nil]]

      result = actor.send(:parse_daily_kpi, rows)

      expect(result.size).to eq(1)
    end

    it "skips a row whose date is blank" do
      rows = [header, ["", "0", "0", "0", "0"]]

      expect(actor.send(:parse_daily_kpi, rows)).to eq([])
    end

    it "returns an empty array for nil or header-only input" do
      expect(actor.send(:parse_daily_kpi, nil)).to eq([])
      expect(actor.send(:parse_daily_kpi, [header])).to eq([])
    end
  end

  describe "#parse_issues" do
    let(:header) do
      %w[issue_id subject type tracker status assigned_to start_date due_date work_days sheet_name project]
    end

    it "maps columns to the expected keys, dropping sheet_name" do
      rows = [
        header,
        ["4547", "未匯入行事曆", "Complaint", "臭蟲", "已結束", "黃靖益",
         "2026/1/2", "2026/1/6", "3", "raw_2026", "Virtuous HRM"]
      ]

      result = actor.send(:parse_issues, rows)

      expect(result).to eq([
        {
          issue_id: "4547", subject: "未匯入行事曆", type: "Complaint", tracker: "臭蟲",
          status: "已結束", assigned_to: "黃靖益", start_date: "2026-01-02", due_date: "2026-01-06",
          work_days: 3, project: "Virtuous HRM"
        }
      ])
      expect(result.first.keys).not_to include(:sheet_name)
    end

    it "normalizes start_date and due_date to ISO 8601" do
      rows = [header, ["1", "s", "Complaint", "臭蟲", "已結束", "x", "2026/8/1", "2026-08-02", "", "raw_2026", "P"]]

      result = actor.send(:parse_issues, rows)

      expect(result.first[:start_date]).to eq("2026-08-01")
      expect(result.first[:due_date]).to eq("2026-08-02")
    end

    it "leaves start_date/due_date nil when the source cell is empty" do
      rows = [header, ["1", "s", "Complaint", "臭蟲", "已結束", "x", "", nil, "", "raw_2026", "P"]]

      result = actor.send(:parse_issues, rows)

      expect(result.first[:start_date]).to be_nil
      expect(result.first[:due_date]).to be_nil
    end

    it "converts a valid work_days string to Integer" do
      rows = [header, ["1", "s", "Complaint", "臭蟲", "已結束", "x", "", "", "108", "raw_2026", "P"]]

      expect(actor.send(:parse_issues, rows).first[:work_days]).to eq(108)
    end

    it "keeps a non-numeric work_days value as-is instead of raising" do
      rows = [header, ["1", "s", "Complaint", "臭蟲", "已結束", "x", "", "", "TBD", "raw_2026", "P"]]

      expect(actor.send(:parse_issues, rows).first[:work_days]).to eq("TBD")
    end

    it "leaves work_days nil when the source cell is empty" do
      rows = [header, ["1", "s", "Complaint", "臭蟲", "已結束", "x", "", "", "", "raw_2026", "P"]]

      expect(actor.send(:parse_issues, rows).first[:work_days]).to be_nil
    end

    it "skips a row when issue_id is blank" do
      rows = [header, ["", "s", "Complaint", "臭蟲", "已結束", "x", "", "", "", "raw_2026", "P"]]

      expect(actor.send(:parse_issues, rows)).to eq([])
    end

    it "skips a row when subject is blank" do
      rows = [header, ["1", "", "Complaint", "臭蟲", "已結束", "x", "", "", "", "raw_2026", "P"]]

      expect(actor.send(:parse_issues, rows)).to eq([])
    end

    it "skips a row when status is blank, keeping other valid rows" do
      rows = [
        header,
        ["1", "s", "Complaint", "臭蟲", "", "x", "", "", "", "raw_2026", "P"],
        ["2", "s2", "TestingBug", "臭蟲", "新建立", "y", "", "", "", "raw_2026", "P"]
      ]

      result = actor.send(:parse_issues, rows)

      expect(result.map { |r| r[:issue_id] }).to eq(["2"])
    end

    it "skips blank rows" do
      rows = [
        header,
        ["1", "s", "Complaint", "臭蟲", "已結束", "x", "", "", "", "raw_2026", "P"],
        [],
        Array.new(11)
      ]

      expect(actor.send(:parse_issues, rows).size).to eq(1)
    end

    it "returns an empty array for nil or header-only input" do
      expect(actor.send(:parse_issues, nil)).to eq([])
      expect(actor.send(:parse_issues, [header])).to eq([])
    end
  end

  describe "#compute_project_breakdown" do
    it "groups by project and counts complaint/testing/other, with total as their sum" do
      issues = [
        { project: "A", type: "Complaint" },
        { project: "A", type: "Complaint" },
        { project: "A", type: "TestingBug" },
        { project: "B", type: "Other" },
        { project: "B", type: "SomethingElse" }
      ]

      result = actor.send(:compute_project_breakdown, issues)

      expect(result).to contain_exactly(
        { project: "A", complaint: 2, testing: 1, other: 0, total: 3 },
        { project: "B", complaint: 0, testing: 0, other: 2, total: 2 }
      )
    end

    it "groups issues with a blank project under 未分類" do
      issues = [{ project: "", type: "Complaint" }, { project: nil, type: "TestingBug" }]

      result = actor.send(:compute_project_breakdown, issues)

      expect(result).to eq([{ project: "未分類", complaint: 1, testing: 1, other: 0, total: 2 }])
    end

    it "returns an empty array for an empty issues list" do
      expect(actor.send(:compute_project_breakdown, [])).to eq([])
    end
  end

  describe "#call" do
    subject(:result) { described_class.result }

    let(:month_kpi_rows) do
      [
        %w[year_month 客訴 測試 總Bug 攔截率 完成數 未結案 平均天數 SLA達標率 Top3],
        ["2026-08", "15", "9", "24", "37.5", "6", "3", "3.1", "25", "王贊勛:8"]
      ]
    end

    let(:daily_kpi_rows) do
      [
        %w[日期 客訴 測試 其他 總計],
        ["2026-08-13", "0", "1", "0", "1"]
      ]
    end

    let(:issue_rows) do
      [
        %w[issue_id subject type tracker status assigned_to start_date due_date work_days sheet_name project],
        ["4547", "未匯入行事曆", "Complaint", "臭蟲", "已結束", "黃靖益",
         "2026/1/2", "2026/1/6", "3", "raw_2026", "Virtuous HRM"],
        ["5165", "白名單申請時間錯誤", "TestingBug", "臭蟲", "新建立", "蔡秉逸",
         "2026/8/12", "", "", "raw_2026", "Virtuous HRM"]
      ]
    end

    before do
      allow(IssueSheetsClient).to receive(:fetch_month_kpi_rows).and_return(month_kpi_rows)
      allow(IssueSheetsClient).to receive(:fetch_daily_kpi_rows).and_return(daily_kpi_rows)
      allow(IssueSheetsClient).to receive(:fetch_issue_rows).and_return(issue_rows)
    end

    it "populates month_kpi and daily_kpi outputs from the client's rows" do
      expect(result.month_kpi).to eq([
        {
          year_month: "2026-08", complaint: 15, testing: 9, total_bug: 24, block_rate: 37.5,
          completed: 6, unresolved: 3, avg_days: 3.1, sla_rate: 25.0
        }
      ])
      expect(result.daily_kpi).to eq([
        { date: "2026-08-13", complaint: 0, testing: 1, other: 0, total: 1 }
      ])
    end

    it "populates issues from the client's rows" do
      expect(result.issues.map { |i| i[:issue_id] }).to eq(["4547", "5165"])
    end

    it "populates project_breakdown derived from issues" do
      expect(result.project_breakdown).to eq([
        { project: "Virtuous HRM", complaint: 1, testing: 1, other: 0, total: 2 }
      ])
    end
  end
end
