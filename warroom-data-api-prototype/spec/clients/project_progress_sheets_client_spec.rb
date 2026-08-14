# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectProgressSheetsClient do
  include ActiveSupport::Testing::TimeHelpers

  let(:header_row) { ["專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延誤"] }
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

  # rows_by_range: { "功能!A:G" => [[...], ...] or nil, ... }
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

  def all_sheets_rows(header_only: false)
    described_class::SHEET_NAMES.each_with_object({}) do |name, acc|
      row = ["#{name}-project", "#{name}-task", "done", "owner", "2026/1/1", "2026/1/2", "0"]
      acc["#{name}!A:G"] = header_only ? [header_row] : [header_row, row]
    end
  end

  describe ".fetch_rows" do
    context "when Rails credentials exist" do
      before { stub_credentials }

      it "calls the API once per type sheet with correct parameters" do
        fake_service = stub_service_for(all_sheets_rows)

        described_class.fetch_rows

        described_class::SHEET_NAMES.each do |name|
          expect(fake_service).to have_received(:get_spreadsheet_values)
            .with(described_class::SPREADSHEET_ID, "#{name}!A:G", value_render_option: "FORMATTED_VALUE")
            .once
        end
      end

      it "merges all sheets' rows, keeping only the first sheet's header row" do
        stub_service_for(all_sheets_rows)

        result = described_class.fetch_rows
        tagged_header = header_row + ["類型"]

        expect(result.first).to eq(tagged_header)
        expect(result.count { |row| row == tagged_header }).to eq(1)
        expect(result.size).to eq(described_class::SHEET_NAMES.size + 1)
      end

      it "tags each data row with its originating sheet name as an 8th element" do
        stub_service_for(all_sheets_rows)

        result = described_class.fetch_rows

        described_class::SHEET_NAMES.each do |name|
          expect(result).to include(
            ["#{name}-project", "#{name}-task", "done", "owner", "2026/1/1", "2026/1/2", "0", name]
          )
        end
      end
    end

    context "when Rails credentials return nil, fallback to ENV var" do
      before do
        ENV["GOOGLE_SHEETS_CREDENTIALS_JSON"] = fake_creds_json
        fake_credentials = double("credentials")
        allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(fake_credentials)
      end

      it "uses the environment variable for credentials" do
        stub_service_for(all_sheets_rows(header_only: true))

        result = described_class.fetch_rows

        expect(result).to eq([header_row + ["類型"]])
      end
    end

    context "when both Rails credentials and ENV var are missing" do
      it "raises StandardError with a Chinese message" do
        expect { described_class.fetch_rows }
          .to raise_error(StandardError, /找不到 Google Service Account 憑證/)
      end
    end

    context "when Google API returns successfully" do
      before { stub_credentials }

      it "returns the merged array of rows" do
        stub_service_for(all_sheets_rows)

        result = described_class.fetch_rows

        expect(result).to eq(
          [header_row + ["類型"]] + described_class::SHEET_NAMES.map do |name|
            ["#{name}-project", "#{name}-task", "done", "owner", "2026/1/1", "2026/1/2", "0", name]
          end
        )
      end

      it "pads short rows (trailing empty cells trimmed by the Sheets API) before tagging, so the type lands in the 8th slot" do
        # Google Sheets omits trailing empty cells: a row with a blank "延誤" column
        # comes back with only 6 elements instead of 7.
        short_row = ["功能-project", "功能-task", "done", "owner", "2026/1/1", "2026/1/2"]
        rows = all_sheets_rows
        rows["功能!A:G"] = [header_row, short_row]
        stub_service_for(rows)

        result = described_class.fetch_rows

        tagged_short_row = result.find { |row| row[0] == "功能-project" }
        expect(tagged_short_row).to eq(short_row + [nil, "功能"])
      end

      it "treats a sheet with a nil response as contributing no rows" do
        rows = all_sheets_rows
        rows["PR!A:G"] = nil
        stub_service_for(rows)

        result = described_class.fetch_rows

        # 功能(header+data) + PR(nil→0) + 調整/遺漏/臭蟲(data only, header dropped) = 2+0+1+1+1
        expect(result).not_to include(nil)
        expect(result.size).to eq(5)
        expect(result).not_to include(["PR-project", "PR-task", "done", "owner", "2026/1/1", "2026/1/2", "0", "PR"])
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
        expect { described_class.fetch_rows }.to raise_error(Google::Apis::ClientError)
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
        expect { described_class.fetch_rows }.to raise_error(Google::Apis::ClientError)
      end
    end
  end

  describe ".fetched_at" do
    it "returns nil when nothing has ever been cached" do
      expect(described_class.fetched_at).to be_nil
    end

    it "records the time of the underlying API fetch" do
      # 測試環境的 cache_store 是 :null_store（快取實質停用），無法驗證真的「命中快取」，
      # 這裡換成真實的 MemoryStore，只為了確認 fetched_at 真的會被寫入並可讀回。
      stub_credentials
      stub_service_for(all_sheets_rows(header_only: true))
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

      travel_to Time.zone.parse("2026-03-01 09:00:00") do
        described_class.fetch_rows
        expect(described_class.fetched_at).to eq(Time.zone.parse("2026-03-01 09:00:00"))
      end
    end
  end

  describe ".fetch_rows with force: true" do
    it "passes force: true through to Rails.cache.fetch, bypassing any existing cache entry" do
      stub_credentials
      stub_service_for(all_sheets_rows(header_only: true))

      expect(Rails.cache).to receive(:fetch)
        .with(described_class::CACHE_KEY, hash_including(force: true))
        .and_call_original

      described_class.fetch_rows(force: true)
    end
  end
end
