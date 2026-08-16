# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sheets::FetchProjectRoster do
  let(:header) { %w[專案 專案縮寫 狀態 比例 生效月份 失效月份 負責RD 客戶 PM] }

  describe "#call" do
    it "parses project_name/status/customer/pm and skips columns unrelated to this page" do
      rows = [
        header,
        [ "AG 亞炬", "亞炬 Platform", "維護", "40%", "2026/01", "", "王贊勛", "亞炬", "呂俐禎" ]
      ]
      allow(ProjectRosterSheetsClient).to receive(:fetch_rows).and_return(rows)

      result = described_class.result

      expect(result).to be_success
      expect(result.roster).to eq([
        { project_name: "AG 亞炬", abbreviation: "亞炬 Platform", status: "維護", customer: "亞炬", pm: "呂俐禎" }
      ])
    end

    it "skips blank rows used to separate customer groups in the real sheet" do
      rows = [
        header,
        [ "AG 亞炬", "亞炬 Platform", "維護", "40%", "2026/01", "", "王贊勛", "亞炬", "呂俐禎" ],
        [],
        [ "", "", "", "", "", "", "", "", "" ],
        [ "Virtuous HRM", "HRM", "維護", "40%", "2026/01", "", "黃靖益", "AMAS", "楊欣翰" ]
      ]
      allow(ProjectRosterSheetsClient).to receive(:fetch_rows).and_return(rows)

      result = described_class.result

      expect(result.roster.map { |r| r[:project_name] }).to eq([ "AG 亞炬", "Virtuous HRM" ])
    end

    it "returns an empty roster when the sheet has only a header row" do
      allow(ProjectRosterSheetsClient).to receive(:fetch_rows).and_return([ header ])

      expect(described_class.result.roster).to eq([])
    end

    it "maps a 404 to sheet_not_found" do
      error = Google::Apis::ClientError.new("Not found")
      allow(error).to receive(:status_code).and_return(404)
      allow(ProjectRosterSheetsClient).to receive(:fetch_rows).and_raise(error)

      result = described_class.result

      expect(result).not_to be_success
      expect(result.failure_code).to eq(:sheet_not_found)
    end

    it "maps a 403 to access_denied" do
      error = Google::Apis::ClientError.new("Forbidden")
      allow(error).to receive(:status_code).and_return(403)
      allow(ProjectRosterSheetsClient).to receive(:fetch_rows).and_raise(error)

      result = described_class.result

      expect(result.failure_code).to eq(:access_denied)
    end

    it "maps an unexpected error to internal_error" do
      allow(ProjectRosterSheetsClient).to receive(:fetch_rows).and_raise(StandardError, "boom")

      result = described_class.result

      expect(result.failure_code).to eq(:internal_error)
    end
  end
end
