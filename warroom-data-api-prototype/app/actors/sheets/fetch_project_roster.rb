# frozen_string_literal: true

module Sheets
  class FetchProjectRoster < ApplicationActor
    output :roster
    output :failure_code
    output :message

    def call
      rows = ProjectRosterSheetsClient.fetch_rows
      self.roster = parse_rows(rows)
    rescue Google::Apis::ClientError => e
      if e.status_code == 404 || e.message.to_s.include?("Unable to parse range")
        fail!(failure_code: :sheet_not_found, message: "找不到指定分頁或試算表：#{e.message}")
      elsif e.status_code == 403
        fail!(failure_code: :access_denied, message: "資料來源存取權限不足：#{e.message}")
      else
        fail!(failure_code: :internal_error, message: "Google Sheets API 錯誤：#{e.message}")
      end
    rescue => e
      fail!(failure_code: :internal_error, message: "未預期的內部錯誤：#{e.message}")
    end

    private

    # 欄位對應：A=專案（全名）、B=專案縮寫、C=狀態、D=比例、E=生效月份、F=失效月份、G=負責RD、
    # H=客戶、I=PM。D~G 與本頁面呈現無關，不解析；PM 之後（J 欄）內容意義不明，不解析（見
    # requirements.md 不納入範圍）。真實試算表以空白列分隔不同客戶群組，「專案」欄位空白的列
    # 整列跳過，不納入輸出，其餘正常列不受影響。
    def parse_rows(rows)
      return [] if rows.nil? || rows.size <= 1

      rows[1..].filter_map do |row|
        next if row.nil?

        project_name, abbreviation, status, _ratio, _effective_month, _expiry_month,
          _owner_rd, customer, pm = row.values_at(0, 1, 2, 3, 4, 5, 6, 7, 8)
        next if project_name.to_s.strip.empty?

        {
          project_name: project_name,
          abbreviation: abbreviation,
          status: status,
          customer: customer,
          pm: pm
        }
      end
    end
  end
end
