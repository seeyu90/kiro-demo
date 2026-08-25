# frozen_string_literal: true

class ProjectProfilesSheetsClient
  include GoogleSheetsCredentials

  # 與既有 ProjectRosterSheetsClient 同一份試算表（300_員工專案），不同分頁：「專案」分頁
  # （已用真實 Service Account 憑證確認過，非佔位假設）以「Github/Notion」欄位存放與本頁
  # 階段紀錄 Sheet 的 `project` 欄一致的專案代碼（例如 HRM、JZNPMS），比既有
  # ProjectRosterSheetsClient 讀的「專案工程師對照表」分頁（鍵是專案全名／專案縮寫）更適合
  # 直接對應本頁需求，故另開一個 Client 讀這個分頁，不修改既有 ProjectRosterSheetsClient。
  SPREADSHEET_ID = "101fF0GlW2iwjC6TNQnNgKjUrxJg-3Ia5nCYox6haTNM"
  SHEET_NAME = ENV.fetch("PROJECT_PROFILES_SHEET_NAME", "專案")

  # 欄位：Github/Notion, Redmine 專案, 303 專案, 客戶, PM, 狀態（A~F），52 列足夠涵蓋。
  RANGE_SUFFIX = "!A1:F100"

  SCOPES = [ "https://www.googleapis.com/auth/spreadsheets.readonly" ].freeze

  # 比照 PhaseRecordsSheetsClient／既有 305/306 慣例，見該檔附註。
  CACHE_KEY = "project_profiles_sheets_client/fetch_rows/#{SPREADSHEET_ID}"
  CACHE_EXPIRY = 5.minutes

  def self.fetch_rows
    new.fetch_rows
  end

  # 2026-08-25 使用者要求拿掉「重新整理資料」按鈕與資料新鮮度提示，移除 force 參數與
  # fetched_at 追蹤，理由同 PhaseRecordsSheetsClient 附註。
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
