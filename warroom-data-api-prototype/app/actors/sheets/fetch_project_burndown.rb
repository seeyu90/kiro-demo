# frozen_string_literal: true

module Sheets
  class FetchProjectBurndown < ApplicationActor
    output :issues
    output :failure_code
    output :message

    # 表頭週欄位格式：MM/DD（例如 "8/10"、"08/10"）。
    WEEK_HEADER_PATTERN = /\A(\d{1,2})\/(\d{1,2})\z/
    # 固定欄位 A~I 共 9 欄（新增「狀態」於 H 欄，完成日期與預估人時之間），週欄位自第 10 欄
    # （J 欄，0-based index 9）起。
    FIXED_COLUMN_COUNT = 9
    # 狀態欄位（H 欄）的合法值；其餘內容（空白、殘留數字等髒資料）視為無法辨識，交由
    # controller 端 fallback 到 due_date 判斷進行中／已完成（見 BurndownController#issue_in_progress?）。
    VALID_STATUSES = %w[未開始 執行中 已完成].freeze

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

    # 列解析與合併：固定欄位 A~I → reported_remaining_hours, project, issue_title, assignee,
    # issue_id, start_date, due_date, status_raw, estimated_hours；project／issue_title／issue_id
    # 任一空白則跳過整列。同一議題（同 issue_id）可能拆成多列分別填給不同人員，故先逐列解析成
    # 原始資料，再依 issue_id 合併為單一議題後才計算 ideal_series／actual_series（見下方
    # merge_rows）。
    def parse_issues(rows, week_dates)
      sorted_week_dates = week_dates.sort_by { |w| w[:date] }
      raw_rows = rows.filter_map { |row| parse_row(row, sorted_week_dates) }
      merge_rows(raw_rows, sorted_week_dates)
    end

    def parse_row(row, sorted_week_dates)
      return nil if blank_row?(row)

      reported_remaining_hours, project, issue_title, assignee, issue_id,
        start_date_raw, due_date_raw, status_raw, estimated_hours_raw = row.values_at(0, 1, 2, 3, 4, 5, 6, 7, 8)
      return nil if [ project, issue_title, issue_id ].any? { |value| value.to_s.strip.empty? }

      {
        issue_id: issue_id,
        project: project,
        issue_title: issue_title,
        assignee: assignee,
        start_date: normalize_date(start_date_raw),
        due_date: normalize_date(due_date_raw),
        status_raw: status_raw,
        estimated_hours: safe_float(estimated_hours_raw) || 0.0,
        reported_remaining_hours: safe_float(reported_remaining_hours),
        # 週欄位儲存格為空白時視為 0 人時，不拋出例外（需求 1.4）。
        weekly_hours: sorted_week_dates.map { |w| safe_float(row[w[:index]]) || 0.0 }
      }
    end

    # 依 issue_id 合併同議題的多列（真實資料常見：同一議題拆給多位人員分別填寫）：
    # - assignees：該議題所有人員清單（保留原始順序、去重）
    # - estimated_hours／reported_remaining_hours：加總（後者若各列皆空白則維持 nil）
    # - 週人時：同一週的各列人時加總
    # - start_date／due_date：僅在「該列 due_date 晚於 start_date」時視為合法列，取合法列中最早
    #   的 start_date、最晚的 due_date；全部列皆不合法（含空白）時回傳 nil（進而讓 ideal_series
    #   算出空陣列，而非讓單一列的髒資料拖累或誤植整個議題的區間）。
    def merge_rows(raw_rows, sorted_week_dates)
      raw_rows.group_by { |r| r[:issue_id] }.map do |issue_id, group|
        first = group.first
        # 每列的 start_date 只解析一次、重複使用（下面的合法區間判斷、開案週裁切都需要），
        # 避免對同一個日期字串重複呼叫 Date.parse。
        parsed_starts = group.index_with { |r| parse_date(r[:start_date]) }

        valid_ranges = group.filter_map do |r|
          start_d = parsed_starts[r]
          due_d = parse_date(r[:due_date])
          [ start_d, due_d ] if start_d && due_d && due_d > start_d
        end
        start_date = valid_ranges.map(&:first).min&.iso8601
        due_date = valid_ranges.map(&:last).max&.iso8601

        remaining_values = group.filter_map { |r| r[:reported_remaining_hours] }
        estimated_hours = group.sum { |r| r[:estimated_hours] }

        # 議題自己的燃盡圖只畫「該議題開案當週之後」的週次，不套用整份試算表的完整週範圍
        # （否則議題開案前那幾個月會被畫成一條沒有意義的平線）。開案日期取全部列裡「任一列本身
        # 合法的日期」（不要求該列同時有合法的完成日期，跟上面 start_date／due_date 的合併規則
        # 是兩件事）；找不到任何合法開案日期時，維持顯示完整週範圍（無法判斷該從哪週開始裁切）。
        # 週欄位代表的是「當週固定那一天」（例如每週一），比對時先把開案日期正規化到當週週一
        # 再比較，避免像「開案 08/13（週四）」被誤判晚於「週欄位 08/10（週一）」而整週被裁掉
        # ——兩者其實屬於同一週。
        # 取捨：若開案日期之前的週欄位仍被填了人時（理論上不該發生），該部分人時會被裁掉、不計入
        # 實際序列的累加。
        trim_from = parsed_starts.values.compact.min&.beginning_of_week(:monday)
        window_indices = sorted_week_dates.each_index.select do |i|
          trim_from.nil? || sorted_week_dates[i][:date] >= trim_from
        end
        week_window = window_indices.map { |i| sorted_week_dates[i] }

        # 依人員分組一次，同時算出議題整體週人時（各人加總）與每人自己的週人時，
        # 不用各自完整掃過 group 兩次。
        by_assignee = group.reject { |r| r[:assignee].to_s.strip.empty? }.group_by { |r| r[:assignee] }
        per_assignee_weekly = by_assignee.transform_values { |rows| window_indices.map { |i| rows.sum { |r| r[:weekly_hours][i] } } }
        weekly_hours = window_indices.each_index.map { |idx| per_assignee_weekly.values.sum { |w| w[idx] } }

        {
          issue_id: issue_id,
          project: first[:project],
          issue_title: first[:issue_title],
          assignees: by_assignee.keys,
          start_date: start_date,
          due_date: due_date,
          status: merge_status(group),
          estimated_hours: estimated_hours,
          reported_remaining_hours: remaining_values.empty? ? nil : remaining_values.sum,
          actual_series: compute_actual_series(week_window, weekly_hours, estimated_hours),
          ideal_series: compute_ideal_series(week_window, start_date, due_date, estimated_hours),
          per_assignee: per_assignee_series(by_assignee, per_assignee_weekly, week_window)
        }
      end
    end

    # 每位人員各自「累積消耗人時」序列（由 0 往上累加，不是剩餘人時）：供議題卡片下方的堆疊圖
    # 使用——多人份的累積人時堆疊起來，天生就是同一個基準（疊到頂＝議題整體的累積消耗），
    # 不會像「各自的剩餘人時 vs. 議題整體理想線」那樣因為基準不同（個人份量 vs. 團隊總量）而
    # 誤導判讀進度落後多少。同一人若拆成多列（例如更正列），merge_rows 已先依人員名稱分組，
    # 故這裡不會把同一人畫成兩塊色塊。
    def per_assignee_series(by_assignee, per_assignee_weekly, week_window)
      by_assignee.map do |assignee, rows|
        {
          assignee: assignee,
          estimated_hours: rows.sum { |r| r[:estimated_hours] },
          cumulative_series: compute_cumulative_series(week_window, per_assignee_weekly[assignee])
        }
      end
    end

    def compute_cumulative_series(sorted_week_dates, weekly_hours)
      cumulative = 0.0

      sorted_week_dates.each_with_index.map do |w, i|
        cumulative += weekly_hours[i]
        { date: w[:date].iso8601, hours: cumulative.round(2) }
      end
    end

    # 合併同議題多列的狀態：只採計合法值（VALID_STATUSES）；任一列為「未開始」或「執行中」即代表
    # 議題整體尚未完成（回傳 "in_progress"），全部合法列皆為「已完成」才回傳 "done"；沒有任何一列
    # 是合法值時回傳 nil（交由 controller fallback 到 due_date 判斷）。
    def merge_status(group)
      valid = group.map { |r| r[:status_raw].to_s.strip }.select { |s| VALID_STATUSES.include?(s) }
      return nil if valid.empty?

      valid.any? { |s| s != "已完成" } ? "in_progress" : "done"
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
    #
    # 開案／完成兩端補上錨點：試算表目前的週欄位不一定剛好涵蓋到開案週或完成週（例如完成日期
    # 還沒到，試算表最新一週還沒到那天），若只依現有週欄位畫線，理想線會在試算表資料範圍的
    # 邊界處被截斷，看起來像是線沒畫完。這裡確保理想線一定包含「開案＝滿額」「完成＝歸零」
    # 這兩個端點，即使超出目前週欄位範圍，讓斜線完整畫到底。錨點日期正規化到當週週一（比照
    # 其他週欄位一律是週一），維持 X 軸日期格式一致，不會冒出一個非週一的孤立日期。
    def compute_ideal_series(sorted_week_dates, start_date, due_date, estimated_hours)
      start_d = parse_date(start_date)
      due_d = parse_date(due_date)
      return [] if start_d.nil? || due_d.nil? || due_d <= start_d

      total_span = (due_d - start_d).to_f

      points = sorted_week_dates.map do |w|
        ratio = ((w[:date] - start_d).to_f / total_span).clamp(0.0, 1.0)
        { date: w[:date].iso8601, hours: (estimated_hours * (1 - ratio)).round(2) }
      end

      anchors = [
        { date: start_d.beginning_of_week(:monday).iso8601, hours: estimated_hours.round(2) },
        { date: due_d.beginning_of_week(:monday).iso8601, hours: 0.0 }
      ]
      # 錨點排在前面：Array#uniq 保留「第一次出現」的元素，若某週欄位剛好落在錨點同一天
      # （例如 due_date 本身不是週一、但正規化後跟某週欄位同一週），錨點的保證值（滿額／歸零）
      # 必須贏過該週依比例算出的值，理想線才能真的準時歸零／從滿額開始。
      (anchors + points).uniq { |p| p[:date] }.sort_by { |p| p[:date] }
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

    # FORMATTED_VALUE（見 BurndownSheetsClient）可能把數字格式化成含千分位逗號的字串
    # （例如 "1,200"），先去除逗號再轉型，避免合法數字被誤判為無法解析而靜默歸零。
    def safe_float(value)
      return nil if value.nil? || value.to_s.strip.empty?

      Float(value.to_s.delete(","))
    rescue ArgumentError, TypeError
      nil
    end
  end
end
