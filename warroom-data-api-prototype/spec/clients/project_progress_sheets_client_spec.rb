# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectProgressSheetsClient do
  include ActiveSupport::Testing::TimeHelpers

  # 來源是以年度命名的分頁（n8n 從 Slack 同步），欄位 A~J。
  let(:source_header) do
    [ "sheetName", "專案名稱", "類型", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "最後更新", "record_key" ]
  end
  let(:source_row) do
    [ "2026", "P1", "功能", "T1", "完成", "Alice", "2026/1/1", "2026/1/2", "2026/1/2 10:00", "k1" ]
  end
  # 對外仍維持既有列格式，呼叫端不需要知道來源換了分頁。
  let(:output_header) { described_class::OUTPUT_HEADER }
  let(:output_row) { [ "P1", "T1", "完成", "Alice", "2026/1/1", "2026/1/2", nil, "功能" ] }
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

  def main_range
    "#{described_class::SHEET_NAME}#{described_class::RANGE_SUFFIX}"
  end

  # rows_by_range: { "2026!A:J" => [[...], ...] or nil }
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

  def source_rows(header_only: false)
    { main_range => header_only ? [ source_header ] : [ source_header, source_row ] }
  end

  describe ".fetch_rows" do
    context "when Rails credentials exist" do
      before { stub_credentials }

      it "reads the year sheet once with the expected range" do
        fake_service = stub_service_for(source_rows)

        described_class.fetch_rows

        expect(fake_service).to have_received(:get_spreadsheet_values)
          .with(described_class::SPREADSHEET_ID, main_range, value_render_option: "FORMATTED_VALUE")
          .once
      end

      # 類型是來源資料的一個欄位，不再靠「這一列是從哪個分頁抓的」推斷，所以「未分類」這種
      # 沒有對應衍生分頁的任務也讀得到（舊做法會整批漏掉）。
      it "remaps the source columns onto the existing row contract, type included" do
        uncategorized = [ "2026", "P2", "未分類", "T2", "未完成", "Bob", "", "", "", "k2" ]
        stub_service_for(main_range => [ source_header, source_row, uncategorized ])

        result = described_class.fetch_rows

        expect(result.first).to eq(output_header)
        expect(result[1]).to eq(output_row)
        expect(result[2]).to eq([ "P2", "T2", "未完成", "Bob", "", "", nil, "未分類" ])
      end

      it "pads short rows (trailing empty cells trimmed by the Sheets API) so columns do not shift" do
        short_row = [ "2026", "P3", "PR", "T3", "未完成", "Carol" ] # 預計/實際/最後更新/record_key 皆空
        stub_service_for(main_range => [ source_header, short_row ])

        expect(described_class.fetch_rows.last).to eq([ "P3", "T3", "未完成", "Carol", nil, nil, nil, "PR" ])
      end

      it "returns an empty array when the sheet has no rows at all" do
        stub_service_for(main_range => nil)

        expect(described_class.fetch_rows).to eq([])
      end
    end

    context "when Rails credentials return nil, fallback to ENV var" do
      before do
        ENV["GOOGLE_SHEETS_CREDENTIALS_JSON"] = fake_creds_json
        fake_credentials = double("credentials")
        allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(fake_credentials)
      end

      it "uses the environment variable for credentials" do
        stub_service_for(source_rows(header_only: true))

        result = described_class.fetch_rows

        expect(result).to eq([ output_header ])
      end
    end

    context "when both Rails credentials and ENV var are missing" do
      it "raises StandardError with a Chinese message" do
        expect { described_class.fetch_rows }
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
      stub_service_for(source_rows(header_only: true))
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
      stub_service_for(source_rows(header_only: true))

      expect(Rails.cache).to receive(:fetch)
        .with(described_class::CACHE_KEY, hash_including(force: true))
        .and_call_original

      described_class.fetch_rows(force: true)
    end

    it "does not overwrite fetched_at when a forced refetch fails" do
      # 真實情境：快取內已有先前成功寫入的資料，使用者按「重新整理資料」(force: true)，
      # 這次 API 呼叫卻失敗（額度、網路錯誤等）。舊的快取資料與 fetched_at 都不應被
      # 這次失敗的嘗試污染──fetched_at 必須仍然反映「上一次真正成功」的時間，
      # 否則後續依 fetched_at 做的判斷會以為資料是新的。
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      stub_credentials

      success_time = Time.zone.parse("2026-03-01 09:00:00")
      failure_time = Time.zone.parse("2026-03-01 09:02:00")

      fake_service = stub_service_for(source_rows(header_only: true))

      travel_to success_time do
        described_class.fetch_rows
      end

      allow(fake_service).to receive(:get_spreadsheet_values).and_raise(Google::Apis::RateLimitError.new("Rate limit exceeded"))

      travel_to failure_time do
        expect { described_class.fetch_rows(force: true) }.to raise_error(Google::Apis::RateLimitError)
        expect(described_class.fetched_at).to eq(success_time)
      end
    end
  end
end
