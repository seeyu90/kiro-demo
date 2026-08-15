# frozen_string_literal: true

module Sheets
  class FetchProjectBurndown < ApplicationActor
    output :issues
    output :failure_code
    output :message

    # 表頭週欄位格式：MM/DD（例如 "8/10"、"08/10"）。
    WEEK_HEADER_PATTERN = /\A(\d{1,2})\/(\d{1,2})\z/
    # 固定欄位 A~H 共 8 欄，週欄位自第 9 欄（I 欄，0-based index 8）起。
    FIXED_COLUMN_COUNT = 8

    def call
      rows = BurndownSheetsClient.fetch_rows
      header = rows.first || []
      week_dates = parse_week_dates(header)

      self.issues = parse_issues(rows.drop(1), week_dates)
    rescue Google::Apis::ClientError => e
      # 錯誤對應邏輯比照 306 Sheets::FetchIssueDashboard（見 rails-standards.md 的
      # failure_code 對應表）。
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

    # 週欄位解析與跨年份判斷（見 requirements.md 需求 2）：越靠左（越靠近固定欄位）代表越接近的
    # 一週。第一個週欄位以 Date.current 為錨點推算年份；若依當年年份組出的日期晚於錨點 3 天以上，
    # 視為去年同週。後續（更早的）週欄位先沿用前一欄推算出的年份組日期，若該日期晚於前一欄（較近
    # 一週）的日期，代表跨過年底邊界，年份減 1 重新組出。無法組成合法日期的欄位（如 2/30）整欄跳過，
    # 不納入任何議題的週序列。回傳依「表頭原始左到右順序」（近→遠）的 { index:, date: } 陣列。
    def parse_week_dates(header)
      today = Date.current
      previous_date = nil
      previous_year = nil

      header.each_with_index.filter_map do |cell, index|
        next if index < FIXED_COLUMN_COUNT

        match = cell.to_s.strip.match(WEEK_HEADER_PATTERN)
        next unless match

        month, day = match.captures.map(&:to_i)
        year = previous_year || today.year
        date = build_date(year, month, day)
        next if date.nil?

        if previous_date.nil?
          if date > today + 3
            year -= 1
            date = build_date(year, month, day)
            next if date.nil?
          end
        elsif date > previous_date
          year -= 1
          date = build_date(year, month, day)
          next if date.nil?
        end

        previous_date = date
        previous_year = year
        { index: index, date: date }
      end
    end

    def build_date(year, month, day)
      Date.new(year, month, day)
    rescue ArgumentError
      nil
    end

    # 列解析：固定欄位 A~H → reported_remaining_hours, project, issue_title, assignee, issue_id,
    # start_date, due_date, estimated_hours；project／issue_title／issue_id 任一空白則跳過整列。
    # 每一列解析完成後即計算該議題自己的 ideal_series／actual_series（見需求 3），一併寫入輸出的
    # Hash（BurndownIssueBlueprint 的 :actual_series／:ideal_series 欄位即取自這裡）。
    def parse_issues(rows, week_dates)
      sorted_week_dates = week_dates.sort_by { |w| w[:date] }

      rows.filter_map do |row|
        next if blank_row?(row)

        reported_remaining_hours, project, issue_title, assignee, issue_id,
          start_date_raw, due_date_raw, estimated_hours_raw = row.values_at(0, 1, 2, 3, 4, 5, 6, 7)
        next if [ project, issue_title, issue_id ].any? { |value| value.to_s.strip.empty? }

        estimated_hours = safe_float(estimated_hours_raw) || 0.0
        start_date = normalize_date(start_date_raw)
        due_date = normalize_date(due_date_raw)

        # 週欄位儲存格為空白時視為 0 人時，不拋出例外（需求 1.4）。
        weekly_hours = sorted_week_dates.map { |w| safe_float(row[w[:index]]) || 0.0 }

        {
          issue_id: issue_id,
          project: project,
          issue_title: issue_title,
          assignee: assignee,
          start_date: start_date,
          due_date: due_date,
          estimated_hours: estimated_hours,
          reported_remaining_hours: safe_float(reported_remaining_hours),
          actual_series: compute_actual_series(sorted_week_dates, weekly_hours, estimated_hours),
          ideal_series: compute_ideal_series(sorted_week_dates, start_date, due_date, estimated_hours)
        }
      end
    end

    # 實際剩餘人時序列：週欄位依日期由舊到新排序後，逐週累加該欄位人時，
    # remaining = estimated_hours − 累積人時（需求 3.3）。
    def compute_actual_series(sorted_week_dates, weekly_hours, estimated_hours)
      cumulative = 0.0

      sorted_week_dates.each_with_index.map do |w, i|
        cumulative += weekly_hours[i]
        { date: w[:date].iso8601, hours: (estimated_hours - cumulative).round(2) }
      end
    end

    # 理想剩餘人時序列：start_date／due_date 皆合法且 due_date 晚於 start_date 時，依時間比例
    # 線性計算（比例 0 時＝estimated_hours，比例 1 時＝0，clamp 至 0..1）；否則回傳空陣列，
    # 不拋出例外（需求 3.1、3.2）。
    def compute_ideal_series(sorted_week_dates, start_date, due_date, estimated_hours)
      start_d = parse_date(start_date)
      due_d = parse_date(due_date)
      return [] if start_d.nil? || due_d.nil? || due_d <= start_d

      total_span = (due_d - start_d).to_f

      sorted_week_dates.map do |w|
        ratio = ((w[:date] - start_d).to_f / total_span).clamp(0.0, 1.0)
        { date: w[:date].iso8601, hours: (estimated_hours * (1 - ratio)).round(2) }
      end
    end

    def parse_date(date_str)
      return nil if date_str.nil? || date_str.to_s.strip.empty?

      Date.parse(date_str.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    # 與 305/306 既有 normalize_date 邏輯相同；維持獨立實作而非抽共用 module（同既有取捨）。
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

    def safe_float(value)
      return nil if value.nil? || value.to_s.strip.empty?

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
