# frozen_string_literal: true

class IssueSheetsClient
  SPREADSHEET_ID = "1RdU2p9b7fwNgO5e59jN-00a5KLOQ91xrFhj2NenyKTc"

  # 分頁名稱已依 warroom-issue-dashboard-real-source Task 1 確認，取自試算表
  # xl/workbook.xml 的官方分頁清單。raw_2023~raw_2025、raw_2027 為隱藏分頁（不影響
  # API 讀取）；raw_2027 目前僅有標題列、無資料列。
  MONTH_KPI_SHEET = "month_kpi"
  DAILY_KPI_SHEET = "daily_kpi"
  ISSUE_SHEETS    = %w[raw_2023 raw_2024 raw_2025 raw_2026 raw_2027].freeze

  MONTH_KPI_RANGE = "A:J"
  DAILY_KPI_RANGE = "A:E"
  ISSUE_RANGE     = "A:K"

  SCOPES = ["https://www.googleapis.com/auth/spreadsheets.readonly"].freeze

  def self.fetch_month_kpi_rows
    new.fetch_rows(MONTH_KPI_SHEET, MONTH_KPI_RANGE)
  end

  def self.fetch_daily_kpi_rows
    new.fetch_rows(DAILY_KPI_SHEET, DAILY_KPI_RANGE)
  end

  # raw_2023~raw_2027 皆使用相同欄位結構（issue_id, subject, type, tracker, status,
  # assigned_to, start_date, due_date, work_days, sheet_name, project），與 305 的
  # SheetsApiClient 不同，這裡不需要額外附加分頁標記：試算表本身已含 sheet_name／project 欄位。
  def self.fetch_issue_rows
    new.fetch_and_merge_rows(ISSUE_SHEETS, ISSUE_RANGE)
  end

  def fetch_rows(sheet_name, range_suffix)
    response = build_service.get_spreadsheet_values(
      SPREADSHEET_ID,
      "#{sheet_name}!#{range_suffix}",
      value_render_option: "FORMATTED_VALUE"
    )
    (response.values || []).map { |row| retag_utf8(row) }
  end

  # 合併多個分頁的列，僅保留第一個分頁的標題列，其餘分頁只併入資料列。
  def fetch_and_merge_rows(sheet_names, range_suffix)
    combined = []
    sheet_names.each_with_index do |sheet_name, index|
      rows = fetch_rows(sheet_name, range_suffix)
      combined.concat(index.zero? ? rows : rows.drop(1))
    end
    combined
  end

  private

  # google-apis-sheets_v4 回傳的儲存格字串會被標記為 ASCII-8BIT，即使實際內容是
  # 合法 UTF-8 位元組；標記錯誤會讓後續跟程式碼裡的 UTF-8 常值字串併接時噴
  # Encoding::CompatibilityError，因此在來源處統一重新標記為 UTF-8（純改標記，不改變位元組內容）。
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

  # 憑證讀取策略：Rails credentials 優先，fallback 至環境變數。
  # 與 305 的 SheetsApiClient 共用同一組 Service Account 憑證（同一 Google Cloud 專案）。
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
