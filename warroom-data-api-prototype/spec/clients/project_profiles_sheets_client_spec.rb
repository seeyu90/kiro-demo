# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectProfilesSheetsClient do
  let(:fake_creds_json) { '{"type":"service_account","project_id":"fake"}' }

  before do
    allow(Rails.application.credentials).to receive(:dig).and_return(nil)
    ENV.delete("GOOGLE_SHEETS_CREDENTIALS_JSON")
    allow(Rails.application.credentials).to receive(:dig)
      .with(:google_sheets, :service_account_json)
      .and_return(fake_creds_json)

    fake_credentials = double("credentials")
    allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(fake_credentials)
  end

  it "reads the 專案 tab (Github/Notion code column) and re-tags string cells as UTF-8" do
    fake_service = double("SheetsService")
    allow(Google::Apis::SheetsV4::SheetsService).to receive(:new).and_return(fake_service)
    allow(fake_service).to receive(:authorization=)

    row = [ "HRM".dup.force_encoding(Encoding::ASCII_8BIT), "Virtuous HRM", "HRM", "AMAS", "楊欣翰", "維護" ]
    response = double("Response", values: [ row ])
    allow(fake_service).to receive(:get_spreadsheet_values)
      .with(described_class::SPREADSHEET_ID,
            "#{described_class::SHEET_NAME}#{described_class::RANGE_SUFFIX}",
            value_render_option: "FORMATTED_VALUE")
      .and_return(response)

    result = described_class.fetch_rows

    expect(result).to eq([ [ "HRM", "Virtuous HRM", "HRM", "AMAS", "楊欣翰", "維護" ] ])
    expect(result.first.first.encoding).to eq(Encoding::UTF_8)
  end

  it "returns an empty array when the sheet has no values" do
    fake_service = double("SheetsService")
    allow(Google::Apis::SheetsV4::SheetsService).to receive(:new).and_return(fake_service)
    allow(fake_service).to receive(:authorization=)
    allow(fake_service).to receive(:get_spreadsheet_values).and_return(double("Response", values: nil))

    expect(described_class.fetch_rows).to eq([])
  end

  # 2026-08-25 使用者要求比照既有 305/306 快取慣例，見 ProjectProgressSheetsClient 對應測試。
end
