# frozen_string_literal: true

require "rails_helper"

RSpec.describe BurndownSheetsClient do
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

  def stub_service(header_row:)
    fake_service = double("SheetsService")
    allow(Google::Apis::SheetsV4::SheetsService).to receive(:new).and_return(fake_service)
    allow(fake_service).to receive(:authorization=)

    header_response = double("Response", values: [ header_row ])
    allow(fake_service).to receive(:get_spreadsheet_values)
      .with(described_class::SPREADSHEET_ID,
            "#{described_class::SHEET_NAME}#{described_class::HEADER_RANGE_SUFFIX}",
            value_render_option: "FORMATTED_VALUE")
      .and_return(header_response)

    fake_service
  end

  def stub_data_range(fake_service, last_col:, rows:)
    data_response = double("Response", values: rows)
    allow(fake_service).to receive(:get_spreadsheet_values)
      .with(described_class::SPREADSHEET_ID,
            "#{described_class::SHEET_NAME}!A1:#{last_col}#{described_class::MAX_DATA_ROWS}",
            value_render_option: "FORMATTED_VALUE")
      .and_return(data_response)
  end

  describe ".fetch_rows" do
    context "when Rails credentials exist" do
      before { stub_credentials }

      it "reads the header row first to determine the last non-blank column, then fetches that range" do
        header = %w[剩餘人時 專案 議題 人員 議題ID 開案日期 完成日期 預估人時 08/10]
        fake_service = stub_service(header_row: header)
        stub_data_range(fake_service, last_col: "I", rows: [ header ])

        described_class.fetch_rows

        expect(fake_service).to have_received(:get_spreadsheet_values)
          .with(described_class::SPREADSHEET_ID,
                "#{described_class::SHEET_NAME}!A1:I#{described_class::MAX_DATA_ROWS}",
                value_render_option: "FORMATTED_VALUE")
          .once
      end

      it "ignores trailing blank header cells when computing the last column" do
        header = %w[剩餘人時 專案 議題 人員 議題ID 開案日期 完成日期 預估人時 08/10] + [ "", "" ]
        fake_service = stub_service(header_row: header)
        stub_data_range(fake_service, last_col: "I", rows: [ header ])

        described_class.fetch_rows

        expect(fake_service).to have_received(:get_spreadsheet_values)
          .with(described_class::SPREADSHEET_ID,
                "#{described_class::SHEET_NAME}!A1:I#{described_class::MAX_DATA_ROWS}",
                value_render_option: "FORMATTED_VALUE")
          .once
      end

      it "converts a last column index past Z into a double-letter column reference" do
        header = Array.new(28) { |i| "col#{i}" } # 28 欄 → 最後一欄索引 27 → AB
        fake_service = stub_service(header_row: header)
        stub_data_range(fake_service, last_col: "AB", rows: [ header ])

        described_class.fetch_rows

        expect(fake_service).to have_received(:get_spreadsheet_values)
          .with(described_class::SPREADSHEET_ID,
                "#{described_class::SHEET_NAME}!A1:AB#{described_class::MAX_DATA_ROWS}",
                value_render_option: "FORMATTED_VALUE")
          .once
      end

      it "returns the raw data rows" do
        header = %w[剩餘人時 專案 議題 人員 議題ID 開案日期 完成日期 預估人時]
        data_row = [ "2", "AG 亞炬", "議題A", "王贊勛", "1001", "2026/08/01", "2026/08/15", "10" ]
        fake_service = stub_service(header_row: header)
        stub_data_range(fake_service, last_col: "H", rows: [ header, data_row ])

        expect(described_class.fetch_rows).to eq([ header, data_row ])
      end

      it "returns an empty array when the data range response has a nil values payload" do
        header = %w[剩餘人時 專案 議題 人員 議題ID 開案日期 完成日期 預估人時]
        fake_service = stub_service(header_row: header)
        stub_data_range(fake_service, last_col: "H", rows: nil)

        expect(described_class.fetch_rows).to eq([])
      end

      it "re-tags string cells to UTF-8 encoding" do
        header = %w[剩餘人時 專案 議題 人員 議題ID 開案日期 完成日期 預估人時]
        data_row = [ "2", "AG 亞炬", "議題A", "王贊勛", "1001", "2026/08/01", "2026/08/15", "10" ]
        fake_service = stub_service(header_row: header)
        stub_data_range(fake_service, last_col: "H", rows: [ header, data_row ])

        result = described_class.fetch_rows
        project_cell = result.last[1]

        expect(project_cell.encoding).to eq(Encoding::UTF_8)
      end

      it "caches the result so a second call within the TTL does not hit the API again" do
        # 測試環境的 cache_store 是 :null_store（快取實質停用），改用真實 MemoryStore
        # 才能驗證第二次呼叫確實命中快取、不再打 API（比照 ProjectProgressSheetsClient 的作法）。
        allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

        header = %w[剩餘人時 專案 議題 人員 議題ID 開案日期 完成日期 預估人時]
        fake_service = stub_service(header_row: header)
        stub_data_range(fake_service, last_col: "H", rows: [ header ])

        described_class.fetch_rows
        described_class.fetch_rows

        expect(fake_service).to have_received(:get_spreadsheet_values).twice
      end
    end

    context "when Rails credentials return nil, fallback to ENV var" do
      before do
        ENV["GOOGLE_SHEETS_CREDENTIALS_JSON"] = fake_creds_json
        fake_credentials = double("credentials")
        allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(fake_credentials)
      end

      it "uses the environment variable for credentials" do
        header = %w[剩餘人時 專案 議題 人員 議題ID 開案日期 完成日期 預估人時]
        fake_service = stub_service(header_row: header)
        stub_data_range(fake_service, last_col: "H", rows: [ header ])

        expect(described_class.fetch_rows).to eq([ header ])
      end
    end

    context "when both Rails credentials and ENV var are missing" do
      it "raises StandardError with a Chinese message" do
        expect { described_class.fetch_rows }
          .to raise_error(StandardError, /找不到 Google Service Account 憑證/)
      end
    end

    context "when Google API raises ClientError" do
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
        expect { described_class.fetch_rows }.to raise_error(Google::Apis::ClientError)
      end
    end
  end
end
