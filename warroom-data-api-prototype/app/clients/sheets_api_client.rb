# frozen_string_literal: true

class SheetsApiClient
  SPREADSHEET_ID = "11gwDnOqEiGqj_VF2XF7AzxiJTiOW_k2knF6-4yQCej8"
  SHEET_NAMES    = ["功能", "PR", "調整", "遺漏", "臭蟲"].freeze
  RANGE_SUFFIX   = "!A:G"
  SCOPES         = ["https://www.googleapis.com/auth/spreadsheets.readonly"].freeze
  CACHE_KEY      = "sheets_api_client/fetch_rows/#{SPREADSHEET_ID}"
  CACHE_EXPIRY   = 5.minutes

  # 305 進度資料分散在 5 個「類型」分頁（功能／PR／調整／遺漏／臭蟲），每個分頁欄位結構
  # 完全相同（A~G：專案名稱、任務名稱、狀態、負責人、預計完成日期、實際完成日期、延誤，
  # 「延誤」為試算表既有公式算好的值，直接讀取即可，不在程式中重新計算）。
  # 回傳單一合併後的列陣列：僅保留第一個分頁的標題列，其餘分頁只取資料列。
  #
  # @return [Array<Array<String>>] 合併後的原始列陣列（第 1 列為標題列）
  # @raise [Google::Apis::ClientError]  403 / 404 等 API 層級錯誤
  # @raise [Google::Apis::ServerError]  5xx 伺服器端錯誤
  # @raise [StandardError]              憑證載入失敗或其他未預期錯誤
  def self.fetch_rows
    new.fetch_rows
  end

  # 試算表資料變動不快，即時每次請求都重打 5 個分頁的 API 會拖慢頁面。
  # 成功結果快取 CACHE_EXPIRY 分鐘；若區塊內拋出例外（額度、權限等錯誤），
  # Rails.cache.fetch 不會快取例外，下次請求會照常重試，不會卡住舊的錯誤結果。
  def fetch_rows
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_EXPIRY) { fetch_rows_from_api }
  end

  private

  def fetch_rows_from_api
    service = build_service
    combined = []

    SHEET_NAMES.each_with_index do |sheet_name, index|
      rows = fetch_sheet_rows(service, sheet_name)
      tagged = tag_with_type(rows, sheet_name)
      combined.concat(index.zero? ? tagged : tagged.drop(1))
    end

    combined
  end

  DATA_COLUMN_COUNT = 7 # A~G

  # 每個類型分頁本身就代表一種任務類型（功能／PR／調整／遺漏／臭蟲），API 回應本身不包含
  # 這個資訊，因此在來源處依「這一列是向哪個分頁請求取得」附加第 8 欄：標題列附加固定文字
  # 「類型」，資料列附加該分頁名稱。
  #
  # Google Sheets API 會省略列尾端的空白儲存格（例如「延誤」欄為空時，該列只回傳 6 個
  # 元素而非 7 個），若不先補滿到 7 欄再附加，類型標記會誤入 delay_days 等欄位。因此附加
  # 前一律先補滿（或截斷）至恰好 7 欄，確保類型標記固定落在第 8 個位置。
  def tag_with_type(rows, sheet_name)
    rows.each_with_index.map do |row, i|
      normalized = pad_to_data_columns(row)
      i.zero? ? normalized + ["類型"] : normalized + [sheet_name]
    end
  end

  def pad_to_data_columns(row)
    (row + Array.new(DATA_COLUMN_COUNT, nil)).first(DATA_COLUMN_COUNT)
  end

  def fetch_sheet_rows(service, sheet_name)
    response = service.get_spreadsheet_values(
      SPREADSHEET_ID,
      "#{sheet_name}#{RANGE_SUFFIX}",
      value_render_option: "FORMATTED_VALUE"
    )
    (response.values || []).map { |row| retag_utf8(row) }
  end

  # google-apis-sheets_v4 回傳的儲存格字串會被標記為 ASCII-8BIT，即使實際內容是
  # 合法 UTF-8 位元組（試算表本身就是 UTF-8）。標記錯誤會讓後續任何跟程式碼裡的
  # UTF-8 常值字串（例如中文錯誤訊息）併在一起時噴 Encoding::CompatibilityError，
  # 因此在來源處統一重新標記為 UTF-8（純改標記，不改變位元組內容）。
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

  # 憑證讀取策略：Rails credentials 優先，fallback 至環境變數
  def credentials
    json = rails_credentials_json || env_credentials_json
    raise "找不到 Google Service Account 憑證，請設定 Rails credentials 或環境變數 GOOGLE_SHEETS_CREDENTIALS_JSON" if json.nil?

    Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(json),
      scope: SCOPES
    )
  end

  def rails_credentials_json
    raw = Rails.application.credentials.dig(:google_sheets, :service_account_json)
    raw.present? ? raw.to_s : nil
  rescue => _e
    nil
  end

  def env_credentials_json
    json = ENV["GOOGLE_SHEETS_CREDENTIALS_JSON"]
    json.present? ? json : nil
  end
end
