# frozen_string_literal: true

module Sheets
  class FetchIssueDashboard < ApplicationActor
    output :month_kpi
    output :daily_kpi
    output :issues
    output :project_breakdown
    output :failure_code
    output :message

    def call
      self.month_kpi         = parse_month_kpi(IssueSheetsClient.fetch_month_kpi_rows)
      self.daily_kpi          = parse_daily_kpi(IssueSheetsClient.fetch_daily_kpi_rows)
      self.issues              = parse_issues(IssueSheetsClient.fetch_issue_rows)
      self.project_breakdown = compute_project_breakdown(issues)
    rescue Google::Apis::ClientError => e
      # 錯誤對應邏輯與 305 Sheets::FetchProjectProgress 相同（見 rails-standards.md 的
      # failure_code 對應表）：三個讀取類別（月度 KPI／每日趨勢／議題明細）中任一失敗，
      # 整個請求即失敗，不做部分成功回傳（需求 6.2）；project_breakdown 為衍生計算，
      # 不會單獨觸發此例外。
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

    # 欄位對應：year_month, 客訴, 測試, 總Bug, 攔截率, 完成數, 未結案, 平均天數, SLA達標率, Top3
    # 不解析 Top3 欄位，不納入輸出（需求 3.3——負責人不作為統計主軸，見需求 3a）。
    def parse_month_kpi(rows)
      return [] if rows.nil? || rows.size <= 1

      rows[1..].filter_map do |row|
        next if blank_row?(row)

        year_month, complaint, testing, total_bug, block_rate,
          completed, unresolved, avg_days, sla_rate = row.values_at(0, 1, 2, 3, 4, 5, 6, 7, 8)
        next if year_month.to_s.strip.empty?

        {
          year_month: year_month,
          complaint: safe_integer(complaint),
          testing: safe_integer(testing),
          total_bug: safe_integer(total_bug),
          block_rate: safe_float(block_rate),
          completed: safe_integer(completed),
          unresolved: safe_integer(unresolved),
          avg_days: safe_float(avg_days),
          sla_rate: safe_float(sla_rate)
        }
      end
    end

    # 欄位對應：日期, 客訴, 測試, 其他, 總計。total 空字串視為 0（需求 4.3）；
    # 結果依 date 升冪排序，確保趨勢圖 X 軸順序正確，不依賴來源順序（需求 4.4）。
    def parse_daily_kpi(rows)
      return [] if rows.nil? || rows.size <= 1

      records = rows[1..].filter_map do |row|
        next if blank_row?(row)

        date, complaint, testing, other, total = row.values_at(0, 1, 2, 3, 4)
        next if date.to_s.strip.empty?

        {
          date: date,
          complaint: safe_integer(complaint),
          testing: safe_integer(testing),
          other: safe_integer(other),
          total: total.to_s.strip.empty? ? 0 : safe_integer(total)
        }
      end

      records.sort_by { |r| r[:date] }
    end

    # 欄位對應：issue_id, subject, type, tracker, status, assigned_to, start_date, due_date,
    # work_days, sheet_name（略過，僅為來源標記，不需輸出）, project。
    # issue_id／subject／status 任一為空白則跳過該列（需求 5.5），其餘正常列不受影響。
    def parse_issues(rows)
      return [] if rows.nil? || rows.size <= 1

      rows[1..].filter_map do |row|
        next if blank_row?(row)

        issue_id, subject, type, tracker, status, assigned_to,
          start_date, due_date, work_days, _sheet_name, project = row.values_at(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
        next if [issue_id, subject, status].any? { |value| value.to_s.strip.empty? }

        {
          issue_id: issue_id,
          subject: subject,
          type: type,
          tracker: tracker,
          status: status,
          assigned_to: assigned_to,
          start_date: normalize_date(start_date),
          due_date: normalize_date(due_date),
          work_days: safe_integer(work_days),
          project: project
        }
      end
    end

    # 依 project 分組統計 complaint／testing／other 筆數與 total（需求 3a），與 prototype 的
    # computeProjectBreakdown 邏輯一致；純記憶體運算，不再次呼叫 IssueSheetsClient。
    def compute_project_breakdown(issues)
      grouped = issues.each_with_object({}) do |issue, acc|
        key = issue[:project].to_s.strip.empty? ? "未分類" : issue[:project]
        acc[key] ||= { project: key, complaint: 0, testing: 0, other: 0 }

        case issue[:type]
        when "Complaint" then acc[key][:complaint] += 1
        when "TestingBug" then acc[key][:testing] += 1
        else acc[key][:other] += 1
        end
      end

      grouped.values.map { |row| row.merge(total: row[:complaint] + row[:testing] + row[:other]) }
    end

    # 與 305 Sheets::FetchProjectProgress#normalize_date 邏輯相同；維持獨立實作而非抽共用
    # module（同一 karpathy-guidelines 取捨，見 design.md「Components and Interfaces」段落）。
    def normalize_date(date_str)
      return nil if date_str.nil? || date_str.to_s.empty?

      match = date_str.to_s.match(%r{\A(\d{4})[-/](\d{1,2})[-/](\d{1,2})\z})
      return date_str unless match

      year, month, day = match.captures
      "#{year}-#{month.rjust(2, '0')}-#{day.rjust(2, '0')}"
    end

    def blank_row?(row)
      row.nil? || row.all? { |cell| cell.to_s.strip.empty? }
    end

    # 有效整數字串則轉換；否則保留原始值，不拋出例外（沿用 305 Sheets::FetchProjectProgress
    # 的 delay_days 處理慣例）。
    def safe_integer(value)
      return nil if value.nil? || value.to_s.strip.empty?

      Integer(value, 10)
    rescue ArgumentError, TypeError
      value
    end

    def safe_float(value)
      return nil if value.nil? || value.to_s.strip.empty?

      Float(value)
    rescue ArgumentError, TypeError
      value
    end
  end
end
