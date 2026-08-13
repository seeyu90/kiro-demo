# frozen_string_literal: true

class SheetsApiClient
  SPREADSHEET_ID = "11gwDnOqEiGqj_VF2XF7AzxiJTiOW_k2knF6-4yQCej8"
  SHEET_RANGE    = "2026!A:G"
  SCOPES         = ["https://www.googleapis.com/auth/spreadsheets.readonly"].freeze

  # 回傳原始列陣列（含標題列），若 API 呼叫失敗則重新拋出例外
  # @return [Array<Array<String>>] 原始列資料
  # @raise [Google::Apis::ClientError]  403 / 404 等 API 層級錯誤
  # @raise [Google::Apis::ServerError]  5xx 伺服器端錯誤
  # @raise [StandardError]              憑證載入失敗或其他未預期錯誤
  def self.fetch_rows
    new.fetch_rows
  end

  def fetch_rows
    service = build_service
    response = service.get_spreadsheet_values(
      SPREADSHEET_ID,
      SHEET_RANGE,
      value_render_option: "FORMATTED_VALUE"
    )
    response.values || []
  end

  private

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
