# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhaseRecordsSheetsClient do
  let(:fake_creds_json) { '{"type":"service_account","project_id":"fake"}' }
  let(:header) do
    %w[project issue_id issue_name stage planned_date actual_date status reason unique_key sheet_year]
  end

  before do
    allow(Rails.application.credentials).to receive(:dig).and_return(nil)
    ENV.delete("GOOGLE_SHEETS_CREDENTIALS_JSON")
    allow(Rails.application.credentials).to receive(:dig)
      .with(:google_sheets, :service_account_json)
      .and_return(fake_creds_json)

    fake_credentials = double("credentials")
    allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(fake_credentials)
  end

  it "reads all three year tabs, strips each tab's own header row, merges into one array, and re-tags UTF-8" do
    fake_service = double("SheetsService")
    allow(Google::Apis::SheetsV4::SheetsService).to receive(:new).and_return(fake_service)
    allow(fake_service).to receive(:authorization=)

    row_2024 = [ "HRM".dup.force_encoding(Encoding::ASCII_8BIT), "202412 優化", "", "開案", "2024-12-02",
                 "2024-12-02", "完成", "", "HRM|202412 優化|開案", "2024" ]
    row_2026 = [ "AMAS", "5136", "現場報工", "開案", "2026-08-05", "2026-08-05", "完成", "", "AMAS|5136|開案", "2026" ]

    allow(fake_service).to receive(:get_spreadsheet_values)
      .with(described_class::SPREADSHEET_ID, "2024#{described_class::RANGE_SUFFIX}", value_render_option: "FORMATTED_VALUE")
      .and_return(double("Response", values: [ header, row_2024 ]))
    allow(fake_service).to receive(:get_spreadsheet_values)
      .with(described_class::SPREADSHEET_ID, "2025#{described_class::RANGE_SUFFIX}", value_render_option: "FORMATTED_VALUE")
      .and_return(double("Response", values: [ header ]))
    allow(fake_service).to receive(:get_spreadsheet_values)
      .with(described_class::SPREADSHEET_ID, "2026#{described_class::RANGE_SUFFIX}", value_render_option: "FORMATTED_VALUE")
      .and_return(double("Response", values: [ header, row_2026 ]))

    result = described_class.fetch_rows

    expect(result).to eq([ row_2024, row_2026 ])
    expect(result.first.first.encoding).to eq(Encoding::UTF_8)
  end

  it "returns an empty array when a tab has no values at all" do
    fake_service = double("SheetsService")
    allow(Google::Apis::SheetsV4::SheetsService).to receive(:new).and_return(fake_service)
    allow(fake_service).to receive(:authorization=)
    allow(fake_service).to receive(:get_spreadsheet_values).and_return(double("Response", values: nil))

    expect(described_class.fetch_rows).to eq([])
  end

  # 2026-08-25 使用者要求比照既有 305/306 快取慣例，見 ProjectProgressSheetsClient 對應測試。
end
