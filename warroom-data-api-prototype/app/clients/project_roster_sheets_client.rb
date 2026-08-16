# frozen_string_literal: true

class ProjectRosterSheetsClient
  include GoogleSheetsCredentials

  SPREADSHEET_ID = "101fF0GlW2iwjC6TNQnNgKjUrxJg-3Ia5nCYox6haTNM"

  # 分頁名稱佔位，比照 BurndownSheetsClient::SHEET_NAME 的既有取捨：待實際串接時人工確認
  # 是否與真實分頁名稱相符，環境變數可在不改程式碼的情況下調整。
  SHEET_NAME = ENV.fetch("PROJECT_ROSTER_SHEET_NAME", "專案清單")

  # 專案數量遠小於 200 列，不需要 BurndownSheetsClient 那種動態欄寬探測。
  RANGE_SUFFIX = "!A1:J200"

  SCOPES = [ "https://www.googleapis.com/auth/spreadsheets.readonly" ].freeze

  def self.fetch_rows
    new.fetch_rows
  end

  def fetch_rows
    service = build_service
    response = service.get_spreadsheet_values(
      SPREADSHEET_ID,
      "#{SHEET_NAME}#{RANGE_SUFFIX}",
      value_render_option: "FORMATTED_VALUE"
    )
    (response.values || []).map { |row| retag_utf8(row) }
  end

  private

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
