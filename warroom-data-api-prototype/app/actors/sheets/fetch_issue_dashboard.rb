# frozen_string_literal: true

module Sheets
  class FetchIssueDashboard < ApplicationActor
    input :month, default: nil
    input :project, default: nil
    input :status, default: "新建立"
    input :breakdown_sort, default: nil
    input :breakdown_dir, default: "desc"
    # 「議題資料」分頁的搜尋框（比對主旨／議題編號／負責人）與快捷篩選 Tag（目前只有
    # 「只看客訴」，固定送出 type="Complaint"，不是自由輸入）。
    input :q, default: nil
    input :type, default: nil

    output :month_kpi
    output :daily_kpi
    output :issues
    output :project_breakdown
    output :failure_code
    output :message

    # 以下皆為「議題資料」HTML 頁面專用的衍生輸出，供 IssuesController 直接使用、不影響
    # 上面 4 個既有輸出（Api::IssueDashboardController 仍讀取全量、未篩選的版本）。
    output :available_months
    output :selected_month
    output :selected_month_record
    output :selected_month_pending
    output :daily_kpi_for_month
    output :month_project_breakdown
    output :projects
    output :statuses
    output :filtered_issues
    output :issue_kpis

    # 「狀態」欄位是自由輸入的中文文字（來源是 Redmine，可能出現「新建立」「處理中」「已確認」
    # 「已解決」「已關閉」「已結束」等各種寫法），無法窮舉每一種可能值，改用關鍵字比對判斷
    # 「是否已完成」。IssuesHelper#issue_status_badge_class 的 badge 顏色判斷也共用同一個
    # 常數（只有這裡的「完成／未完成」二分法，processing／new 的細分只有 View 呈現用，不影響
    # KPI 計算，故不需要共用）。
    ISSUE_DONE_STATUS_PATTERN = /完成|確認|關閉|解決|結束/

    BREAKDOWN_SORT_KEYS = %w[complaint testing other total].freeze
    BREAKDOWN_SORT_DIRS = %w[asc desc].freeze

    def call
      self.month_kpi          = parse_month_kpi(IssueSheetsClient.fetch_month_kpi_rows)
      self.daily_kpi          = parse_daily_kpi(IssueSheetsClient.fetch_daily_kpi_rows)
      self.issues              = parse_issues(IssueSheetsClient.fetch_issue_rows)
      self.project_breakdown = compute_project_breakdown(issues)

      # 月份選單納入進行中的當月（即使 month_kpi 尚無該月列，因為月結數字要等月底才產生），
      # 但預設選中仍是最新「已結算」月份，確保頁面載入時直接看到有意義的月結數字。
      current_year_month = Date.current.strftime("%Y-%m")
      self.available_months = (month_kpi.map { |m| m[:year_month] } + [ current_year_month ]).uniq.sort
      self.selected_month = month.presence || month_kpi.map { |m| m[:year_month] }.max
      self.selected_month_record = month_kpi.find { |m| m[:year_month] == selected_month }
      self.selected_month_pending = selected_month_record.nil? && selected_month == current_year_month

      # 每日趨勢與依專案分類統計皆依所選月份呈現（兩者與月度 KPI 同屬「統計摘要」分頁籤，
      # 理應一起隨月份切換）；依專案分類以議題的 start_date（建立日）判斷所屬月份，
      # 議題明細本身則不受月份篩選（見需求 8）。
      self.daily_kpi_for_month = daily_kpi.select { |d| same_month?(d[:date], selected_month) }
      month_issues = issues.select { |i| same_month?(i[:start_date], selected_month) }
      self.month_project_breakdown = sort_project_breakdown(compute_project_breakdown(month_issues))

      self.projects = issues.map { |i| i[:project] }.compact.uniq
      self.statuses = issues.map { |i| i[:status] }.compact.uniq
      self.filtered_issues = filter_issues(issues)
      # KPI 卡片依「目前篩選結果」（含搜尋／快捷篩選，分頁之前的完整結果）計算，不是
      # 分頁後那一頁的子集合，也不是完全未篩選的 issues 全量。
      self.issue_kpis = compute_issue_kpis(filtered_issues)
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
    # work_days, sheet_name（略過，僅為來源標記，不需輸出）, project, total_hours（花費時間，
    # warroom-issue-dashboard-ux-refresh 任務 6 新增；L 欄，浮點數，可能有小數如 0.75）。
    # issue_id／subject／status 任一為空白則跳過該列（需求 5.5），其餘正常列不受影響。
    # tracker 為「測試」的議題屬於測試性質議題（非真實缺陷），不列入品質相關統計與呈現，
    # 於解析階段整批跳過，不進入 issues／project_breakdown 輸出，API 與 HTML 頁面皆不會看到。
    def parse_issues(rows)
      return [] if rows.nil? || rows.size <= 1

      rows[1..].filter_map do |row|
        next if blank_row?(row)

        issue_id, subject, type, tracker, status, assigned_to,
          start_date, due_date, work_days, _sheet_name, project, total_hours =
            row.values_at(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)
        next if [ issue_id, subject, status ].any? { |value| value.to_s.strip.empty? }
        next if tracker.to_s.strip == "測試"

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
          project: project,
          total_hours: safe_float(total_hours)
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

    # @breakdown_sort 為 nil 時維持原始（依專案分組）順序，不排序。
    # 以 project 名稱作為次要排序鍵（tie-breaker）：Ruby 的 sort_by 不保證穩定排序，若僅依主要
    # 排序欄位排序，同分的列在不同請求間相對順序可能不一致，畫面上會不穩定地跳動。
    def sort_project_breakdown(rows)
      return rows unless BREAKDOWN_SORT_KEYS.include?(breakdown_sort)

      sorted = rows.sort_by { |row| [ row[breakdown_sort.to_sym], row[:project] ] }
      effective_dir = BREAKDOWN_SORT_DIRS.include?(breakdown_dir) ? breakdown_dir : "desc"
      effective_dir == "desc" ? sorted.reverse : sorted
    end

    def filter_issues(issues)
      issues
        .select { |i| project.blank? || i[:project] == project }
        .select { |i| status.blank? || i[:status] == status }
        .select { |i| type.blank? || i[:type] == type }
        .select { |i| q.blank? || issue_matches_query?(i, q) }
    end

    def issue_matches_query?(issue, query)
      needle = query.to_s.downcase
      [ issue[:subject], issue[:issue_id], issue[:assigned_to] ].any? { |value| value.to_s.downcase.include?(needle) }
    end

    def issue_done?(issue)
      issue[:status].to_s.match?(ISSUE_DONE_STATUS_PATTERN)
    end

    def issue_overdue?(issue)
      due = issue[:due_date]
      return false if due.blank?

      Date.parse(due) < Date.current
    rescue ArgumentError, TypeError
      false
    end

    # KPI 卡片：待處理議題（未完成）／緊急客訴（未完成的客訴且已逾期——資料裡沒有優先權／
    # 嚴重度欄位，「客訴+已逾期」是目前能從既有資料算出最接近「緊急」的定義，見
    # warroom-issue-dashboard-ux-refresh 任務 2.1 的取捨說明）／逾期或未定到期日（未完成
    # 且到期日已過或缺漏）。三者都只算「未完成」的議題，已完成的議題不算緊急也不算逾期。
    def compute_issue_kpis(issues)
      pending = issues.reject { |i| issue_done?(i) }
      urgent_complaints = pending.select { |i| i[:type] == "Complaint" && issue_overdue?(i) }
      overdue_or_undated = pending.select { |i| i[:due_date].blank? || issue_overdue?(i) }
      # 累積花費工時不限「未完成」——已完成的議題一樣花了那些工時，此卡片算的是「投入成本」
      # 不是「還剩多少要做」，跟前三個只算 pending 的卡片語意不同。
      total_hours_sum = issues.sum { |i| i[:total_hours].to_f }

      {
        pending: pending.size,
        urgent_complaints: urgent_complaints.size,
        overdue_or_undated: overdue_or_undated.size,
        total_hours_sum: total_hours_sum.round(2)
      }
    end

    # 以日期欄位前 7 碼（YYYY-MM）判斷是否屬於指定月份，與 prototype 的 sameMonth() 邏輯一致。
    def same_month?(date_str, year_month)
      date_str.is_a?(String) && date_str[0, 7] == year_month
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
