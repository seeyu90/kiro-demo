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

    before do
      allow(IssueSheetsClient).to receive(:fetch_month_kpi_rows).and_return(month_kpi_rows)
      allow(IssueSheetsClient).to receive(:fetch_daily_kpi_rows).and_return(daily_kpi_rows)
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
  end
end
