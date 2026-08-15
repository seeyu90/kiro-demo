# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sheets::FetchProjectBurndown do
  include ActiveSupport::Testing::TimeHelpers

  let(:actor) { described_class.new(ServiceActor::Result.to_result({})) }
  let(:fixed_header) { %w[剩餘人時 專案 議題 人員 議題ID 開案日期 完成日期 預估人時] }

  before { travel_to(Date.new(2026, 8, 14)) }
  after { travel_back }

  describe "#parse_week_dates" do
    it "infers this year for a recent week column within the 3-day tolerance window" do
      header = fixed_header + [ "08/10" ]

      result = actor.send(:parse_week_dates, header)

      expect(result).to eq([ { index: 8, date: Date.new(2026, 8, 10) } ])
    end

    it "steps back a year for the first column when it would land more than 3 days in the future" do
      travel_back
      travel_to(Date.new(2026, 1, 2))
      header = fixed_header + [ "01/10" ]

      result = actor.send(:parse_week_dates, header)

      expect(result).to eq([ { index: 8, date: Date.new(2025, 1, 10) } ])
    end

    it "keeps this year for the first column within the 3-day tolerance window" do
      travel_back
      travel_to(Date.new(2026, 1, 2))
      header = fixed_header + [ "01/04" ]

      result = actor.send(:parse_week_dates, header)

      expect(result).to eq([ { index: 8, date: Date.new(2026, 1, 4) } ])
    end

    it "decrements the year for a later (earlier-week) column that crosses the year boundary" do
      header = fixed_header + [ "01/05", "12/29" ]

      result = actor.send(:parse_week_dates, header)

      expect(result).to eq([
        { index: 8, date: Date.new(2026, 1, 5) },
        { index: 9, date: Date.new(2025, 12, 29) }
      ])
    end

    it "does not cross years for normal descending same-year weeks" do
      header = fixed_header + [ "08/10", "08/03", "07/27" ]

      result = actor.send(:parse_week_dates, header)

      expect(result.map { |w| w[:date] }).to eq([
        Date.new(2026, 8, 10), Date.new(2026, 8, 3), Date.new(2026, 7, 27)
      ])
    end

    it "skips a column with an impossible date without raising, and without disrupting later columns" do
      header = fixed_header + [ "08/10", "02/30", "07/27" ]

      result = actor.send(:parse_week_dates, header)

      expect(result.map { |w| w[:index] }).to eq([ 8, 10 ])
      expect(result.map { |w| w[:date] }).to eq([ Date.new(2026, 8, 10), Date.new(2026, 7, 27) ])
    end

    it "ignores non MM/DD header cells" do
      header = fixed_header + [ "備註", "08/10" ]

      result = actor.send(:parse_week_dates, header)

      expect(result).to eq([ { index: 9, date: Date.new(2026, 8, 10) } ])
    end

    it "returns an empty array when there are no week columns" do
      expect(actor.send(:parse_week_dates, fixed_header)).to eq([])
    end
  end

  describe "#compute_actual_series" do
    it "subtracts cumulative weekly hours from estimated_hours, oldest week first" do
      sorted = [
        { index: 9, date: Date.new(2026, 8, 3) },
        { index: 8, date: Date.new(2026, 8, 10) }
      ]

      result = actor.send(:compute_actual_series, sorted, [ 4.0, 3.0 ], 10.0)

      expect(result).to eq([
        { date: "2026-08-03", hours: 6.0 },
        { date: "2026-08-10", hours: 3.0 }
      ])
    end

    it "treats blank weekly hours (already normalized to 0.0 by the caller) as no consumption" do
      sorted = [ { index: 8, date: Date.new(2026, 8, 10) } ]

      result = actor.send(:compute_actual_series, sorted, [ 0.0 ], 5.0)

      expect(result).to eq([ { date: "2026-08-10", hours: 5.0 } ])
    end
  end

  describe "#compute_ideal_series" do
    let(:sorted) do
      [
        { index: 9, date: Date.new(2026, 8, 1) },
        { index: 8, date: Date.new(2026, 8, 15) }
      ]
    end

    it "linearly interpolates remaining hours between start_date and due_date" do
      result = actor.send(:compute_ideal_series, sorted, "2026-08-01", "2026-08-31", 30.0)

      expect(result).to eq([
        { date: "2026-08-01", hours: 30.0 },
        { date: "2026-08-15", hours: 16.0 }
      ])
    end

    it "clamps weeks before start_date to the full estimated hours" do
      result = actor.send(:compute_ideal_series, sorted, "2026-08-10", "2026-08-31", 21.0)

      expect(result.first).to eq({ date: "2026-08-01", hours: 21.0 })
    end

    it "clamps weeks after due_date to 0" do
      result = actor.send(:compute_ideal_series, sorted, "2026-07-01", "2026-08-10", 10.0)

      expect(result.last).to eq({ date: "2026-08-15", hours: 0.0 })
    end

    it "returns an empty array when start_date is missing" do
      expect(actor.send(:compute_ideal_series, sorted, nil, "2026-08-31", 10.0)).to eq([])
    end

    it "returns an empty array when due_date is missing" do
      expect(actor.send(:compute_ideal_series, sorted, "2026-08-01", nil, 10.0)).to eq([])
    end

    it "returns an empty array when due_date is not after start_date" do
      expect(actor.send(:compute_ideal_series, sorted, "2026-08-10", "2026-08-10", 10.0)).to eq([])
    end
  end

  describe "#parse_issues" do
    let(:header) { fixed_header + [ "08/10", "08/03" ] }

    it "maps fixed columns A~H to the expected keys and computes both series" do
      rows = [ [ "2", "AG 亞炬", "議題A", "王贊勛", "1001", "2026/08/01", "2026/08/15", "10", "3", "2" ] ]

      result = actor.send(:parse_issues, rows, actor.send(:parse_week_dates, header))

      expect(result.size).to eq(1)
      issue = result.first
      expect(issue).to include(
        issue_id: "1001", project: "AG 亞炬", issue_title: "議題A", assignee: "王贊勛",
        start_date: "2026-08-01", due_date: "2026-08-15", estimated_hours: 10.0,
        reported_remaining_hours: 2.0
      )
      expect(issue[:actual_series]).to eq([
        { date: "2026-08-03", hours: 8.0 },
        { date: "2026-08-10", hours: 5.0 }
      ])
      expect(issue[:ideal_series]).not_to be_empty
    end

    it "treats a blank weekly cell as 0 hours instead of raising" do
      rows = [ [ "", "P", "T", "A", "1001", "2026/08/01", "2026/08/15", "10", "", "2" ] ]

      result = actor.send(:parse_issues, rows, actor.send(:parse_week_dates, header))

      expect(result.first[:actual_series].last[:hours]).to eq(8.0) # 10 - (2+0)
    end

    it "skips a row when project is blank" do
      rows = [ [ "2", "", "T", "A", "1001", "", "", "10", "", "" ] ]

      expect(actor.send(:parse_issues, rows, [])).to eq([])
    end

    it "skips a row when issue_title is blank" do
      rows = [ [ "2", "P", "", "A", "1001", "", "", "10", "", "" ] ]

      expect(actor.send(:parse_issues, rows, [])).to eq([])
    end

    it "skips a row when issue_id is blank" do
      rows = [ [ "2", "P", "T", "A", "", "", "", "10", "", "" ] ]

      expect(actor.send(:parse_issues, rows, [])).to eq([])
    end

    it "skips blank rows" do
      rows = [ [ "2", "P", "T", "A", "1001", "", "", "10", "", "" ], [], Array.new(10) ]

      expect(actor.send(:parse_issues, rows, []).size).to eq(1)
    end

    it "defaults estimated_hours to 0.0 when the cell is blank" do
      rows = [ [ "", "P", "T", "A", "1001", "", "", "", "", "" ] ]

      expect(actor.send(:parse_issues, rows, []).first[:estimated_hours]).to eq(0.0)
    end
  end

  describe "#call" do
    subject(:result) { described_class.result }

    let(:header) { fixed_header + [ "08/10" ] }
    let(:rows) do
      [
        header,
        [ "2", "AG 亞炬", "議題A", "王贊勛", "1001", "2026/08/01", "2026/08/15", "10", "3" ]
      ]
    end

    before { allow(BurndownSheetsClient).to receive(:fetch_rows).and_return(rows) }

    it "populates issues from the client's rows" do
      expect(result.issues.map { |i| i[:issue_id] }).to eq([ "1001" ])
    end

    context "when BurndownSheetsClient raises Google::Apis::ClientError status 404" do
      before do
        error = Google::Apis::ClientError.new("Not Found")
        allow(error).to receive(:status_code).and_return(404)
        allow(BurndownSheetsClient).to receive(:fetch_rows).and_raise(error)
      end

      it "returns failure_code: :sheet_not_found" do
        expect(result).not_to be_success
        expect(result.failure_code).to eq(:sheet_not_found)
        expect(result.message).to include("找不到指定分頁或試算表")
      end
    end

    context "when BurndownSheetsClient raises Google::Apis::ClientError status 403" do
      before do
        error = Google::Apis::ClientError.new("Forbidden")
        allow(error).to receive(:status_code).and_return(403)
        allow(BurndownSheetsClient).to receive(:fetch_rows).and_raise(error)
      end

      it "returns failure_code: :access_denied" do
        expect(result).not_to be_success
        expect(result.failure_code).to eq(:access_denied)
        expect(result.message).to include("資料來源存取權限不足")
      end
    end

    context "when BurndownSheetsClient raises Google::Apis::ClientError with another status code" do
      before do
        error = Google::Apis::ClientError.new("Bad Request")
        allow(error).to receive(:status_code).and_return(400)
        allow(BurndownSheetsClient).to receive(:fetch_rows).and_raise(error)
      end

      it "returns failure_code: :internal_error" do
        expect(result).not_to be_success
        expect(result.failure_code).to eq(:internal_error)
        expect(result.message).to include("Google Sheets API 錯誤")
      end
    end

    context "when BurndownSheetsClient raises a StandardError (e.g. missing credentials)" do
      before do
        allow(BurndownSheetsClient).to receive(:fetch_rows)
          .and_raise(StandardError.new("找不到 Google Service Account 憑證"))
      end

      it "returns failure_code: :internal_error" do
        expect(result).not_to be_success
        expect(result.failure_code).to eq(:internal_error)
        expect(result.message).to include("未預期的內部錯誤")
      end
    end
  end
end
