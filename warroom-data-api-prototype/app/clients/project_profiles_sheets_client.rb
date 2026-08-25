# frozen_string_literal: true

class ProjectProfilesSheetsClient
  include GoogleSheetsCredentials

  # 與既有 ProjectRosterSheetsClient 同一份試算表（300_員工專案），不同分頁：「專案」分頁的
  # 「Github/Notion」欄存放的專案代碼（例如 HRM、JZNPMS）直接對應本頁階段紀錄 Sheet 的 `project`
  # 欄，比 ProjectRosterSheetsClient 讀的「專案工程師對照表」分頁（鍵是專案全名／縮寫）更適合，
  # 故另開一個 Client，不修改既有 ProjectRosterSheetsClient。
  SPREADSHEET_ID = "101fF0GlW2iwjC6TNQnNgKjUrxJg-3Ia5nCYox6haTNM"
  SHEET_NAME = ENV.fetch("PROJECT_PROFILES_SHEET_NAME", "專案")

  # 欄位：Github/Notion, Redmine 專案, 303 專案, 客戶, PM, 狀態（A~F），100 列足夠涵蓋。
  RANGE_SUFFIX = "!A1:F100"

  SCOPES = [ "https://www.googleapis.com/auth/spreadsheets.readonly" ].freeze

  # 比照 PhaseRecordsSheetsClient／既有 305/306 慣例，見該檔附註。
  CACHE_KEY = "project_profiles_sheets_client/fetch_rows/#{SPREADSHEET_ID}"
  CACHE_EXPIRY = 5.minutes

  def self.fetch_rows
    new.fetch_rows
  end

  # 無 force 參數／fetched_at 追蹤，理由同 PhaseRecordsSheetsClient 附註。
  def fetch_rows
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_EXPIRY) { fetch_rows_from_api }
  end

  private

  def fetch_rows_from_api
    service = build_service
    response = service.get_spreadsheet_values(
      SPREADSHEET_ID,
      "#{SHEET_NAME}#{RANGE_SUFFIX}",
      value_render_option: "FORMATTED_VALUE"
    )
    (response.values || []).map { |row| retag_utf8(row) }
  end

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
