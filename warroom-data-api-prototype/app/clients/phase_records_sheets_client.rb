# frozen_string_literal: true

class PhaseRecordsSheetsClient
  include GoogleSheetsCredentials

  SPREADSHEET_ID = "1YQp4f-5v985W4EV59jhSAdhTKMn2Mc-0PW-qYc6vKpU"

  # n8n 把 Notion「階段紀錄」資料庫同步進本試算表，依年度拆成三個分頁：分頁名稱就是年度字串
  # 本身（"2024"／"2025"／"2026"），每個分頁各自帶一列表頭。三個分頁是同一份資料依時間區分
  # 年度，故本 Client 讀出後直接合併成單一陣列，不視為三種不同來源。
  TABS = %w[2024 2025 2026].freeze

  # 欄位固定為 A~J（project, issue_id, issue_name, stage, planned_date, actual_date, status,
  # reason, unique_key, sheet_year。issue_name 只在 issue_id 是純 Redmine ID 時才會填，
  # issue_id 本身仍是 unique_key／議題分組用的識別欄），列數目前最大約 1003 列（2024 分頁），
  # 抓大一點的上限避免日後資料增長超出範圍卻無聲截斷。
  RANGE_SUFFIX = "!A1:J2000"

  SCOPES = [ "https://www.googleapis.com/auth/spreadsheets.readonly" ].freeze

  # 比照既有 305/306（ProjectProgressSheetsClient／IssueSheetsClient）的快取慣例：每次請求
  # 即時打 4 個分頁（本 Client 3 個 ＋ ProjectProfilesSheetsClient 1 個）會拖慢頁面（實測單次
  # 請求 3~4 秒）。三個年度分頁的合併結果快取成同一把鍵，5 分鐘。
  CACHE_KEY = "phase_records_sheets_client/fetch_rows/#{SPREADSHEET_ID}"
  CACHE_EXPIRY = 5.minutes

  def self.fetch_rows
    new.fetch_rows
  end

  # 回傳值不含任何分頁的表頭列，呼叫端可將每一列視為資料列直接解析。Rails.cache.fetch 只快取
  # 成功結果：區塊內拋出 Google::Apis::ClientError 等例外時不會寫入快取，下次請求照常重試。
  def fetch_rows
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_EXPIRY) { fetch_rows_from_api }
  end

  private

  def fetch_rows_from_api
    service = build_service
    TABS.flat_map do |tab|
      response = service.get_spreadsheet_values(
        SPREADSHEET_ID,
        "#{tab}#{RANGE_SUFFIX}",
        value_render_option: "FORMATTED_VALUE"
      )
      rows = response.values || []
      rows[1..].to_a.map { |row| retag_utf8(row) }
    end
  end

  # 與既有 305/306/307 Client 相同的重新標記慣例（見 rails-standards.md「其他慣例」）。
  def retag_utf8(row)
    row.map do |cell|
      cell.is_a?(String) ? cell.dup.force_encoding(Encoding::UTF_8) : cell
    end
  end

  def build_service
    service = Google::Apis::SheetsV4::SheetsService.new
    service.authorization = credentials
    service
  end
end
