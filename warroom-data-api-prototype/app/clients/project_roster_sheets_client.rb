# frozen_string_literal: true

class ProjectRosterSheetsClient
  include GoogleSheetsCredentials

  SPREADSHEET_ID = "101fF0GlW2iwjC6TNQnNgKjUrxJg-3Ia5nCYox6haTNM"

  # 實際分頁名稱（已用真實 Service Account 憑證對真實試算表確認過，非佔位假設）：試算表內
  # 這份「專案清單」資料實際存放在名為「專案工程師對照表」的分頁，與規劃階段依欄位內容猜測的
  # 「專案清單」不同。環境變數可在不改程式碼的情況下調整（比照既有 BurndownSheetsClient::
  # SHEET_NAME 的取捨），供日後分頁改名時使用。
  SHEET_NAME = ENV.fetch("PROJECT_ROSTER_SHEET_NAME", "專案工程師對照表")

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
