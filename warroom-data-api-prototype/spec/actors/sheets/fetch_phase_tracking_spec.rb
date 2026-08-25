# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sheets::FetchPhaseTracking do
  def record_row(project:, issue_id:, stage:, planned:, actual:, status: "完成", reason: "", issue_name: "")
    [ project, issue_id, issue_name, stage, planned, actual, status, reason,
      "#{project}|#{issue_id}|#{stage}", planned.to_s[0, 4] ]
  end

  let(:profile_header) { %w[Github/Notion Redmine\ 專案 303\ 專案 客戶 PM 狀態] }
  let(:profile_rows) { [ profile_header, [ "HRM", "Virtuous HRM", "HRM", "AMAS", "楊欣翰", "維護" ] ] }

  before do
    allow(ProjectProfilesSheetsClient).to receive(:fetch_rows).and_return(profile_rows)
  end

  describe "#call" do
    it "groups records by (project, issue_id), not by project alone" do
      rows = [
        record_row(project: "HRM", issue_id: "202412 優化", stage: "開案", planned: "2024-12-02", actual: "2024-12-02"),
        record_row(project: "HRM", issue_id: "202411優化", stage: "開案", planned: "2024-11-01", actual: "2024-11-01")
      ]
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_return(rows)

      result = described_class.result

      expect(result).to be_success
      expect(result.cards.map { |c| [ c[:project], c[:issue_id] ] }).to contain_exactly(
        [ "HRM", "202412 優化" ], [ "HRM", "202411優化" ]
      )
    end

    it "carries issue_name through onto the card when present, alongside issue_id" do
      rows = [
        record_row(project: "AGPMS", issue_id: "4548", issue_name: "現場報工", stage: "開案",
                    planned: "2026-01-06", actual: "2026-01-06")
      ]
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_return(rows)

      card = described_class.result.cards.first
      expect(card).to include(issue_id: "4548", issue_name: "現場報工")
    end

    it "leaves issue_name nil when the sheet's issue_name column is blank (older-style rows)" do
      rows = [ record_row(project: "HRM", issue_id: "202412 優化", stage: "開案", planned: "2024-12-02", actual: "2024-12-02") ]
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_return(rows)

      expect(described_class.result.cards.first[:issue_name]).to be_nil
    end

    it "keeps every record for a stage instead of deduping by unique_key, with the last row as primary and earlier ones as history" do
      rows = [
        record_row(project: "HRM", issue_id: "4656", stage: "開案", planned: "2026-01-12", actual: "2026-01-12", reason: "第一次排程"),
        record_row(project: "HRM", issue_id: "4656", stage: "開案", planned: "2026-01-30", actual: "2026-01-30", reason: "重新排程")
      ]
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_return(rows)

      card = described_class.result.cards.first
      kickoff = card[:stages].find { |s| s[:stage] == "開案" }

      expect(kickoff[:primary][:reason]).to eq("重新排程")
      expect(kickoff[:history].map { |r| r[:reason] }).to eq([ "第一次排程" ])
    end

    it "builds a full STAGE_ORDER row set per card, with nil primary/empty history for stages that have no record" do
      rows = [ record_row(project: "HRM", issue_id: "4656", stage: "開案", planned: "2026-01-12", actual: "2026-01-12") ]
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_return(rows)

      card = described_class.result.cards.first

      expect(card[:stages].map { |s| s[:stage] }).to eq(described_class::STAGE_ORDER)
      requirement_stage = card[:stages].find { |s| s[:stage] == "需求確認" }
      expect(requirement_stage[:primary]).to be_nil
      expect(requirement_stage[:history]).to eq([])
    end

    it "skips a row whose stage value is not one of the 5 STAGE_ORDER values" do
      rows = [
        record_row(project: "HRM", issue_id: "4656", stage: "開案", planned: "2026-01-12", actual: "2026-01-12"),
        record_row(project: "HRM", issue_id: "4656", stage: "驗收", planned: "2026-02-01", actual: nil)
      ]
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_return(rows)

      card = described_class.result.cards.first
      expect(card[:stages].sum { |s| (s[:primary] ? 1 : 0) + s[:history].size }).to eq(1)
    end

    it "skips a row with a blank project or issue_id" do
      rows = [
        record_row(project: "", issue_id: "4656", stage: "開案", planned: "2026-01-12", actual: "2026-01-12"),
        record_row(project: "HRM", issue_id: "", stage: "開案", planned: "2026-01-12", actual: "2026-01-12")
      ]
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_return(rows)

      expect(described_class.result.cards).to eq([])
    end

    it "attaches customer/pm from the profile lookup by project code" do
      rows = [ record_row(project: "HRM", issue_id: "4656", stage: "開案", planned: "2026-01-12", actual: "2026-01-12") ]
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_return(rows)

      card = described_class.result.cards.first
      expect(card).to include(customer: "AMAS", pm: "楊欣翰")
    end

    it "does not use the profile sheet's 維護-style project status as the card status" do
      rows = [ record_row(project: "HRM", issue_id: "4656", stage: "開案", planned: "2026-01-12", actual: "2026-01-12", status: "完成") ]
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_return(rows)

      expect(described_class.result.cards.first[:status]).to eq("完成")
    end

    it "derives status from the furthest STAGE_ORDER stage that has a record, not an earlier stage" do
      rows = [
        record_row(project: "HRM", issue_id: "4656", stage: "開案", planned: "2026-01-01", actual: "2026-01-01", status: "完成"),
        record_row(project: "HRM", issue_id: "4656", stage: "開發", planned: "2026-01-10", actual: nil, status: "延誤未完成")
      ]
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_return(rows)

      expect(described_class.result.cards.first[:status]).to eq("延誤未完成")
    end

    it "orders a stage's history newest-superseded-first, oldest last" do
      rows = [
        record_row(project: "HRM", issue_id: "4656", stage: "開案", planned: "2026-01-01", actual: "2026-01-01", reason: "第一次"),
        record_row(project: "HRM", issue_id: "4656", stage: "開案", planned: "2026-01-15", actual: "2026-01-15", reason: "第二次"),
        record_row(project: "HRM", issue_id: "4656", stage: "開案", planned: "2026-01-30", actual: "2026-01-30", reason: "第三次（目前）")
      ]
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_return(rows)

      kickoff = described_class.result.cards.first[:stages].find { |s| s[:stage] == "開案" }

      expect(kickoff[:primary][:reason]).to eq("第三次（目前）")
      expect(kickoff[:history].map { |r| r[:reason] }).to eq([ "第二次", "第一次" ])
    end

    it "degrades gracefully (customer/pm nil, status still derived from stage data) when the profile sheet fails" do
      rows = [ record_row(project: "HRM", issue_id: "4656", stage: "開案", planned: "2026-01-12", actual: "2026-01-12", status: "完成") ]
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_return(rows)
      allow(ProjectProfilesSheetsClient).to receive(:fetch_rows).and_raise(Google::Apis::ClientError.new("boom"))

      result = described_class.result

      expect(result).to be_success
      expect(result.profiles_unavailable).to be true
      expect(result.cards.first).to include(customer: nil, pm: nil, status: "完成")
    end

    it "filters cards by year using each record's planned_date year, and computes available_years from the unfiltered set" do
      rows = [
        record_row(project: "HRM", issue_id: "A", stage: "開案", planned: "2025-01-01", actual: "2025-01-01"),
        record_row(project: "HRM", issue_id: "B", stage: "開案", planned: "2026-01-01", actual: "2026-01-01")
      ]
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_return(rows)

      result = described_class.result(year: "2025")

      expect(result.cards.map { |c| c[:issue_id] }).to eq([ "A" ])
      expect(result.available_years).to eq([ "2026", "2025" ])
    end

    it "returns all cards when year is blank" do
      rows = [
        record_row(project: "HRM", issue_id: "A", stage: "開案", planned: "2025-01-01", actual: "2025-01-01"),
        record_row(project: "HRM", issue_id: "B", stage: "開案", planned: "2026-01-01", actual: "2026-01-01")
      ]
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_return(rows)

      expect(described_class.result(year: nil).cards.size).to eq(2)
    end

    it "maps a 404 to sheet_not_found" do
      error = Google::Apis::ClientError.new("Not found")
      allow(error).to receive(:status_code).and_return(404)
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_raise(error)

      result = described_class.result

      expect(result).not_to be_success
      expect(result.failure_code).to eq(:sheet_not_found)
    end

    it "maps a 403 to access_denied" do
      error = Google::Apis::ClientError.new("Forbidden")
      allow(error).to receive(:status_code).and_return(403)
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_raise(error)

      expect(described_class.result.failure_code).to eq(:access_denied)
    end

    it "maps an unexpected error to internal_error" do
      allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_raise(StandardError, "boom")

      expect(described_class.result.failure_code).to eq(:internal_error)
    end
  end
end
