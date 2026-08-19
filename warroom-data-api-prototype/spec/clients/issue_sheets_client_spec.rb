# frozen_string_literal: true

require "rails_helper"

RSpec.describe IssueSheetsClient do
  let(:month_kpi_header) { %w[year_month 客訴 測試 總Bug 攔截率 完成數 未結案 平均天數 SLA達標率 Top3] }
  let(:daily_kpi_header) { %w[日期 客訴 測試 其他 總計] }
  let(:issue_header) do
    %w[issue_id subject type tracker status assigned_to start_date due_date work_days sheet_name project]
  end
  let(:fake_creds_json) { '{"type":"service_account","project_id":"fake"}' }

  before do
    allow(Rails.application.credentials).to receive(:dig).and_return(nil)
    ENV.delete("GOOGLE_SHEETS_CREDENTIALS_JSON")
  end

  def stub_credentials
    fake_credentials = double("credentials")
    allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(fake_credentials)
    allow(Rails.application.credentials).to receive(:dig)
      .with(:google_sheets, :service_account_json)
      .and_return(fake_creds_json)
  end

  # rows_by_range: { "month_kpi!A:J" => [[...], ...] or nil, ... }
  def stub_service_for(rows_by_range)
    fake_service = double("SheetsService")
    allow(Google::Apis::SheetsV4::SheetsService).to receive(:new).and_return(fake_service)
    allow(fake_service).to receive(:authorization=)
    rows_by_range.each do |range, rows|
      response = double("Response", values: rows)
      allow(fake_service).to receive(:get_spreadsheet_values)
        .with(described_class::SPREADSHEET_ID, range, value_render_option: "FORMATTED_VALUE")
        .and_return(response)
    end
    fake_service
  end

  def issue_rows_for(sheet_name, count: 1)
    Array.new(count) do |i|
      ["#{sheet_name}-#{i}", "subject-#{i}", "Complaint", "臭蟲", "已結束", "owner",
       "2026/1/1", "2026/1/2", "1", sheet_name, "project-#{sheet_name}"]
    end
  end

  def all_issue_sheets_rows(empty_sheets: [])
    described_class::ISSUE_SHEETS.each_with_object({}) do |name, acc|
      rows = empty_sheets.include?(name) ? [issue_header] : [issue_header] + issue_rows_for(name)
      acc["#{name}!A:L"] = rows
    end
  end

  describe ".fetch_month_kpi_rows" do
    context "when Rails credentials exist" do
      before { stub_credentials }

      it "requests the month_kpi sheet with the correct range" do
        fake_service = stub_service_for({ "month_kpi!A:J" => [month_kpi_header] })

        described_class.fetch_month_kpi_rows

        expect(fake_service).to have_received(:get_spreadsheet_values)
          .with(described_class::SPREADSHEET_ID, "month_kpi!A:J", value_render_option: "FORMATTED_VALUE")
          .once
      end

      it "returns the raw rows" do
        data_row = ["2026-08", "15", "9", "24", "37.5", "6", "3", "3.1", "25", "王贊勛:8"]
        stub_service_for({ "month_kpi!A:J" => [month_kpi_header, data_row] })

        result = described_class.fetch_month_kpi_rows

        expect(result).to eq([month_kpi_header, data_row])
      end

      it "returns an empty array when the API responds with a nil values payload" do
        stub_service_for({ "month_kpi!A:J" => nil })

        expect(described_class.fetch_month_kpi_rows).to eq([])
      end
    end
  end

  describe ".fetch_daily_kpi_rows" do
    before { stub_credentials }

    it "requests the daily_kpi sheet with the correct range" do
      fake_service = stub_service_for({ "daily_kpi!A:E" => [daily_kpi_header] })

      described_class.fetch_daily_kpi_rows

      expect(fake_service).to have_received(:get_spreadsheet_values)
        .with(described_class::SPREADSHEET_ID, "daily_kpi!A:E", value_render_option: "FORMATTED_VALUE")
        .once
    end

    it "returns the raw rows" do
      data_row = ["2026-08-13", "0", "0", "0", "0"]
      stub_service_for({ "daily_kpi!A:E" => [daily_kpi_header, data_row] })

      expect(described_class.fetch_daily_kpi_rows).to eq([daily_kpi_header, data_row])
    end
  end

  describe ".fetch_issue_rows" do
    context "when Rails credentials exist" do
      before { stub_credentials }

      it "calls the API once per raw_YYYY sheet with correct parameters" do
        fake_service = stub_service_for(all_issue_sheets_rows)

        described_class.fetch_issue_rows

        described_class::ISSUE_SHEETS.each do |name|
          expect(fake_service).to have_received(:get_spreadsheet_values)
            .with(described_class::SPREADSHEET_ID, "#{name}!A:L", value_render_option: "FORMATTED_VALUE")
            .once
        end
      end

      it "merges all sheets' rows, keeping only the first sheet's header row" do
        stub_service_for(all_issue_sheets_rows)

        result = described_class.fetch_issue_rows

        expect(result.first).to eq(issue_header)
        expect(result.count { |row| row == issue_header }).to eq(1)
      end

      it "does not append any extra tagging column (real sheet already has sheet_name/project)" do
        stub_service_for(all_issue_sheets_rows)

        result = described_class.fetch_issue_rows

        expect(result.first.size).to eq(issue_header.size)
      end

      it "includes data rows from every raw_YYYY sheet, including the currently-empty raw_2027" do
        stub_service_for(all_issue_sheets_rows(empty_sheets: ["raw_2027"]))

        result = described_class.fetch_issue_rows

        expect(result).to include(a_collection_including("raw_2023-0"))
        expect(result).to include(a_collection_including("raw_2026-0"))
        expect(result.flatten).not_to include("raw_2027-0")
      end

      it "treats a sheet with a nil response as contributing no rows" do
        rows = all_issue_sheets_rows
        rows["raw_2024!A:L"] = nil
        stub_service_for(rows)

        result = described_class.fetch_issue_rows

        expect(result).not_to include(nil)
        # header (from raw_2023) + raw_2023 data + raw_2024(nil→0) + raw_2025/2026/2027 data
        expect(result.size).to eq(1 + 4)
      end

      it "re-tags string cells to UTF-8 encoding" do
        data_row = ["raw_2023-0", "客訴主旨", "Complaint", "臭蟲", "已結束", "owner",
                    "2026/1/1", "2026/1/2", "1", "raw_2023", "project"]
        rows = all_issue_sheets_rows
        rows["raw_2023!A:L"] = [issue_header, data_row]
        stub_service_for(rows)

        result = described_class.fetch_issue_rows
        subject_cell = result.find { |row| row[0] == "raw_2023-0" }[1]

        expect(subject_cell.encoding).to eq(Encoding::UTF_8)
      end
    end

    context "when Rails credentials return nil, fallback to ENV var" do
      before do
        ENV["GOOGLE_SHEETS_CREDENTIALS_JSON"] = fake_creds_json
        fake_credentials = double("credentials")
        allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(fake_credentials)
      end

      it "uses the environment variable for credentials" do
        stub_service_for(all_issue_sheets_rows(empty_sheets: described_class::ISSUE_SHEETS))

        result = described_class.fetch_issue_rows

        expect(result).to eq([issue_header])
      end
    end

    context "when both Rails credentials and ENV var are missing" do
      it "raises StandardError with a Chinese message" do
        expect { described_class.fetch_issue_rows }
          .to raise_error(StandardError, /找不到 Google Service Account 憑證/)
      end
    end

    context "when Google API raises ClientError (403)" do
      before do
        stub_credentials
        fake_service = double("SheetsService")
        allow(Google::Apis::SheetsV4::SheetsService).to receive(:new).and_return(fake_service)
        allow(fake_service).to receive(:authorization=)
        error = Google::Apis::ClientError.new("Forbidden")
        error.instance_variable_set(:@status_code, 403)
        allow(fake_service).to receive(:get_spreadsheet_values).and_raise(error)
      end

      it "re-raises the ClientError without catching it" do
        expect { described_class.fetch_issue_rows }.to raise_error(Google::Apis::ClientError)
      end
    end

    context "when Google API raises ClientError (404)" do
      before do
        stub_credentials
        fake_service = double("SheetsService")
        allow(Google::Apis::SheetsV4::SheetsService).to receive(:new).and_return(fake_service)
        allow(fake_service).to receive(:authorization=)
        error = Google::Apis::ClientError.new("Not Found")
        error.instance_variable_set(:@status_code, 404)
        allow(fake_service).to receive(:get_spreadsheet_values).and_raise(error)
      end

      it "re-raises the ClientError without catching it" do
        expect { described_class.fetch_issue_rows }.to raise_error(Google::Apis::ClientError)
      end
    end
  end
end
