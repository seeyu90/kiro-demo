# frozen_string_literal: true

class ProjectProgressSheetsClient
  include GoogleSheetsCredentials

  # 305 每年會換成一份新試算表（跨年當天不保證新試算表已建好），故不依 Date.current.year
  # 自動判斷，改用環境變數 PROJECT_PROGRESS_SPREADSHEET_ID，讓新試算表建好後只要調整環境
  # 變數並重啟服務即可切換；沒有設定環境變數時退回這裡寫死的預設值（同 BurndownSheetsClient
  # 的 SHEET_NAME 做法）。分頁同理，每年是一個以年度命名的新分頁。
  SPREADSHEET_ID = ENV.fetch("PROJECT_PROGRESS_SPREADSHEET_ID", "11gwDnOqEiGqj_VF2XF7AzxiJTiOW_k2knF6-4yQCej8")
  SHEET_NAME     = ENV.fetch("PROJECT_PROGRESS_SHEET_NAME", "2026")
  RANGE_SUFFIX   = "!A:J"
  # 類型 → 寬限天數對照，業務自己維護在試算表上（例如 PR 給 2 天寬限），故不寫死在程式裡。
  GRACE_SHEET_NAME  = ENV.fetch("PROJECT_PROGRESS_GRACE_SHEET_NAME", "類型設定")
  GRACE_RANGE_SUFFIX = "!A:B"
  SCOPES         = [ "https://www.googleapis.com/auth/spreadsheets.readonly" ].freeze
  CACHE_EXPIRY   = 5.minutes

  # 分頁名稱納入 cache key，避免年度切換分頁時誤用到舊分頁的快取值。
  CACHE_KEY            = "project_progress_sheets_client/fetch_rows/#{SPREADSHEET_ID}/#{SHEET_NAME}"
  FETCHED_AT_CACHE_KEY = "#{CACHE_KEY}/fetched_at"
  GRACE_CACHE_KEY      = "project_progress_sheets_client/grace_days/#{SPREADSHEET_ID}/#{GRACE_SHEET_NAME}"

  # 這份試算表的真實來源是以年度命名的分頁（n8n 從各專案 Slack 頻道同步，欄位含 record_key
  # 與最後更新時間）；「功能／PR／調整／遺漏／臭蟲」那幾個分頁是依類型切出來的衍生視圖，
  # 會漏掉類型為「未分類」的任務，且實測發現狀態欄有跟不上來源的情形（來源已填「未完成」、
  # 衍生分頁仍是空白），因此一律以年度分頁為準。
  #
  # 來源欄位為 A~J：sheetName、專案名稱、類型、任務名稱、狀態、負責人、預計完成日期、
  # 實際完成日期、最後更新、record_key。
  SOURCE_COLUMN_COUNT = 10
  SOURCE_PROJECT_NAME = 1
  SOURCE_TASK_TYPE    = 2
  SOURCE_TASK_NAME    = 3
  SOURCE_STATUS       = 4
  SOURCE_OWNER        = 5
  SOURCE_PLANNED      = 6
  SOURCE_ACTUAL       = 7

  # 對外仍維持既有的列格式（專案名稱、任務名稱、狀態、負責人、預計完成日期、實際完成日期、
  # 延誤天數、類型），呼叫端不需要知道來源換了分頁。第 7 欄「延誤天數」在年度分頁上不存在，
  # 一律給 nil——延誤天數改由 Sheets::FetchProjectProgress 以工作日扣寬限天數計算。
  OUTPUT_HEADER = [ "專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延誤天數", "類型" ].freeze

  # @return [Array<Array<String>>] 原始列陣列（第 1 列為標題列）
  # @raise [Google::Apis::ClientError]  403 / 404 等 API 層級錯誤
  # @raise [Google::Apis::ServerError]  5xx 伺服器端錯誤
  # @raise [StandardError]              憑證載入失敗或其他未預期錯誤
  # force: true 時略過現有快取直接重抓。Rails.cache.fetch 的 force 選項只影響「是否讀取既有
  # 快取」，區塊仍在拋出例外時不寫入，失敗不會清掉舊快取值。
  def self.fetch_rows(force: false)
    new.fetch_rows(force: force)
  end

  # 「類型設定」分頁的原始列（第 1 列為標題列）。格式驗證與 Integer 轉換交給呼叫端
  # （Sheets::FetchProjectProgress）處理，這裡只負責取得原始資料，比照 fetch_rows。
  # 對照表整個讀不到時回傳空陣列，由呼叫端當成「沒有寬限」處理——寬限天數只是讓延誤天數
  # 更貼近業務定義，不值得為了它讓整頁掛掉。
  def self.fetch_grace_days(force: false)
    new.fetch_grace_days(force: force)
  end

  # 目前快取內容的實際抓取時間；尚未有任何成功快取時回傳 nil。
  def self.fetched_at
    Rails.cache.read(FETCHED_AT_CACHE_KEY)
  end

  # 試算表資料變動不快，每次請求都重打 API 會拖慢頁面。成功結果快取 CACHE_EXPIRY 分鐘；
  # 若區塊內拋出例外（額度、權限等錯誤），Rails.cache.fetch 不會快取例外，下次請求會照常
  # 重試，不會卡住舊的錯誤結果。
  def fetch_rows(force: false)
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_EXPIRY, force: force) do
      fetch_rows_from_api.tap do
        Rails.cache.write(FETCHED_AT_CACHE_KEY, Time.current, expires_in: CACHE_EXPIRY)
      end
    end
  end

  # 這裡刻意連非預期的內部錯誤（例如程式本身的 bug）都一併接住，是明確的設計取捨：寬限天數
  # 只是讓延誤天數更貼近業務定義的加分項，即使抓取邏輯本身壞掉，也不該連累整頁 305 掛掉。
  # 但原本完全靜默吞掉、沒有任何紀錄，會讓「程式本身的 bug」跟「試算表暫時讀不到」這兩種
  # 完全不同的情況都變成「悄悄退回沒有寬限」，除錯時無從追起——故補上錯誤紀錄，行為
  # （退回空陣列、不讓整頁失敗）維持不變，只是不再對錯誤保持沉默。
  def fetch_grace_days(force: false)
    Rails.cache.fetch(GRACE_CACHE_KEY, expires_in: CACHE_EXPIRY, force: force) do
      fetch_grace_days_from_api
    end
  rescue Google::Apis::Error, StandardError => e
    Rails.logger.error(
      "ProjectProgressSheetsClient#fetch_grace_days 讀取「#{GRACE_SHEET_NAME}」失敗，" \
      "寬限天數退回空表：#{e.class}: #{e.message}"
    )
    []
  end

  private

  def fetch_rows_from_api
    service = build_service
    response = service.get_spreadsheet_values(
      SPREADSHEET_ID,
      "#{SHEET_NAME}#{RANGE_SUFFIX}",
      value_render_option: "FORMATTED_VALUE"
    )
    rows = (response.values || []).map { |row| retag_utf8(row) }
    return [] if rows.empty?

    [ OUTPUT_HEADER ] + rows.drop(1).map { |row| to_output_row(row) }
  end

  # Google Sheets API 會省略列尾端的空白儲存格（例如「實際完成日期」為空時，該列只回傳 7 個
  # 元素而非 10 個），先補滿到固定欄數再取值，欄位才不會錯位。
  def to_output_row(row)
    values = (row + Array.new(SOURCE_COLUMN_COUNT, nil)).first(SOURCE_COLUMN_COUNT)

    [
      values[SOURCE_PROJECT_NAME],
      values[SOURCE_TASK_NAME],
      values[SOURCE_STATUS],
      values[SOURCE_OWNER],
      values[SOURCE_PLANNED],
      values[SOURCE_ACTUAL],
      nil,
      values[SOURCE_TASK_TYPE]
    ]
  end

  # 只取原始列，不做業務層轉換或驗證（比照 fetch_rows_from_api）：格式驗證與 Integer 轉換
  # 交給 Actor 層的 Sheets::FetchProjectProgress#parse_grace_days。
  def fetch_grace_days_from_api
    service = build_service
    response = service.get_spreadsheet_values(
      SPREADSHEET_ID,
      "#{GRACE_SHEET_NAME}#{GRACE_RANGE_SUFFIX}",
      value_render_option: "FORMATTED_VALUE"
    )
    (response.values || []).map { |row| retag_utf8(row) }
  end

  # google-apis-sheets_v4 回傳的儲存格字串會被標記為 ASCII-8BIT，即使實際內容是合法 UTF-8
  # 位元組（試算表本身就是 UTF-8）。標記錯誤會讓後續任何跟程式碼裡的 UTF-8 常值字串（例如
  # 中文錯誤訊息）併在一起時噴 Encoding::CompatibilityError，因此在來源處統一重新標記為
  # UTF-8（純改標記，不改變位元組內容）。
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
