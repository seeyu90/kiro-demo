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
    # H=客戶、I=PM、J=307對應專案。D~G 與本頁面呈現無關，不解析。真實試算表以空白列分隔不同
    # 客戶群組，「專案」欄位空白的列整列跳過，不納入輸出，其餘正常列不受影響。
    #
    # J 欄（307對應專案）是後來人工補上的對照欄：305/roster 與 307 是三套完全獨立的專案命名
    # 系統，且 305/roster 的一個專案在 307 常常拆成好幾個項目追蹤（例如「AG 亞炬」對應 307 的
    # 「亞炬 PMS」「亞炬 Else」「亞炬 Flow」「亞炬 Wms」四項），沒有規律可循，只能靠人工維護
    # 這份對照，不是每個專案都會填（沒有 307 追蹤的專案留空是正常狀態，不是缺漏）。實務上這欄
    # 有時用逗號分隔、有時用空白分隔，且每個 307 名稱本身也可能含空白（如「亞炬 PMS」），無法
    # 用固定分隔符可靠拆開；故不在這裡拆解，原樣保留整段文字，比對時改用「307 真實名稱是否為
    # 這段文字的子字串」判斷（見 Sheets::FetchProjectHistory#build_detail），不管分隔符是什麼
    # 都能正確比對。
    def parse_rows(rows)
      return [] if rows.nil? || rows.size <= 1

      rows[1..].filter_map do |row|
        next if row.nil?

        project_name, abbreviation, status, _ratio, _effective_month, _expiry_month,
          _owner_rd, customer, pm, burndown_names_raw = row.values_at(0, 1, 2, 3, 4, 5, 6, 7, 8, 9)
        next if project_name.to_s.strip.empty?

        {
          project_name: project_name,
          abbreviation: abbreviation,
          status: status,
          customer: customer,
          pm: pm,
          burndown_names_raw: burndown_names_raw.to_s
        }
      end
    end
  end
end
