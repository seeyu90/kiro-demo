# frozen_string_literal: true

class BurndownSheetsClient
  include GoogleSheetsCredentials

  SPREADSHEET_ID = "1A8L0a-5xZSkRpxeN7Gk2Z4O7ZOv4FIy9o2RjQ5odI8k"

  # 實際分頁名稱：試算表每年會新建一個以年度命名的分頁（例如 "2026"），但新分頁不保證在
  # 跨年當天就已建好，因此不依 Date.current.year 自動判斷（那樣會在新分頁還沒建好前，跨年
  # 當天直接打不到資料、整頁壞掉）。改用環境變數 BURNDOWN_SHEET_NAME，新分頁建好後只要調整
  # 環境變數並重啟服務即可切換，不需要改程式碼；沒有設定環境變數時，退回這裡寫死的預設值
  # （目前已確認的分頁名稱），是唯一需要調整的地方。
  SHEET_NAME = ENV.fetch("BURNDOWN_SHEET_NAME", "2026")

  HEADER_RANGE_SUFFIX = "!A1:ZZ1"
  # 遠大於現有 307 試算表的實際列數；取捨：不做「每次呼叫都精準抓取實際列數」的第二次探測，
  # 改用固定上限列數換取實作簡單（見 design.md「動態欄寬」段落）。
  MAX_DATA_ROWS = 500

  SCOPES = [ "https://www.googleapis.com/auth/spreadsheets.readonly" ].freeze
  CACHE_EXPIRY = 5.minutes

  # 比照 ProjectProgressSheetsClient／IssueSheetsClient 的快取作法：快取鍵含分頁名稱，
  # 避免年度切換分頁（SHEET_NAME）改變時誤用到舊分頁的快取值。
  def self.fetch_rows
    Rails.cache.fetch(cache_key, expires_in: CACHE_EXPIRY) do
      new.fetch_rows
    end
  end

  def self.cache_key
    "burndown_sheets_client/fetch_rows/#{SPREADSHEET_ID}/#{SHEET_NAME}"
  end
  private_class_method :cache_key

  def fetch_rows
    service = build_service
    last_col = last_column_letter(service)
    response = service.get_spreadsheet_values(
      SPREADSHEET_ID,
      "#{SHEET_NAME}!A1:#{last_col}#{MAX_DATA_ROWS}",
      value_render_option: "FORMATTED_VALUE"
    )
    (response.values || []).map { |row| retag_utf8(row) }
  end

  private

  # 動態欄寬：先讀表頭列，取表頭列陣列中「最後一個非空元素的索引」換算最後一欄字母
  # （而非非空元素的「數量」），避免表頭中間出現空白儲存格時，換算出過窄的欄位範圍而
  # 靜默漏掉後面的週欄位資料（Sheets API 只省略「尾端」空白儲存格，中間空白仍會保留為
  # 空字串佔位，見 design.md「動態欄寬」段落）。
  def last_column_letter(service)
    response = service.get_spreadsheet_values(
      SPREADSHEET_ID,
      "#{SHEET_NAME}#{HEADER_RANGE_SUFFIX}",
      value_render_option: "FORMATTED_VALUE"
    )
    header_row = (response.values || []).first || []
    last_index = header_row.rindex { |cell| !cell.to_s.strip.empty? } || 0
    column_letter(last_index)
  end

  # 0-based 欄位索引 → A1 表示法字母（0→A、25→Z、26→AA、...）。
  def column_letter(index)
    letters = ""
    n = index
    loop do
      letters = (n % 26 + 65).chr + letters
      n = n / 26 - 1
      break if n.negative?
    end
    letters
  end

  # google-apis-sheets_v4 回傳的儲存格字串會被標記為 ASCII-8BIT，即使實際內容是合法 UTF-8
  # 位元組；標記錯誤會讓後續跟程式碼裡的 UTF-8 常值字串併接時噴 Encoding::CompatibilityError，
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
end
