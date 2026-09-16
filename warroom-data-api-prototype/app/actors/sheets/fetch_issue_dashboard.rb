# frozen_string_literal: true

module Sheets
  class FetchIssueDashboard < ApplicationActor
    # 起訖日期區間篩選，取代原本的單一 month 參數：兩者皆空時預設沿用「最新已結算月份」；
    # 只給一邊時另一邊視為不限制（比照 305/307 共用的 DateRangeFilterable 慣例）。
    input :from, default: nil
    input :to, default: nil
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
    output :selected_from
    output :selected_to
    # 依 [selected_from, selected_to] 與 month_kpi 各月區間重疊判斷出的月份清單（含尚無已結算
    # 列的進行中當月），供 selected_month_pending 判斷「唯一命中的月份是不是當月」用。
    output :matched_months
    # matched_months 之中「真的有已結算 month_kpi 列」的月份數，這才是 selected_month_record
    # 實際彙總了幾個月的依據——區間橫跨的月份數（matched_months.size）可能包含尚無資料的
    # 進行中當月，若拿它判斷單月／彙總會誤把「只有 1 個月真的有資料」的情況當成彙總，白白
    # 隱藏掉其實可以精確顯示的比率（code review 回報）。
    output :settled_month_count
    output :selected_month_record
    output :selected_month_pending
    output :daily_kpi_for_range
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

    # 沒填到期日時的內建 SLA（依 type 而定，天數是從開始日算起「最晚應完成」的期限）：客訴兩天內
    # 要完成、測試（TestingBug／個人責任）當天要完成。取代原本「沒填到期日一律不算逾期」的判斷
    # ——這兩種類型即使沒有明確到期日，業務上仍有既定的完成期限，不該永遠不算逾期、也不該
    # 永遠被歸類到「未定到期日」（見 compute_issue_kpis 的 undated 判斷）。其餘沒有 SLA 對應的
    # 類型（Other）沒填到期日時維持「未定」，不會被視為逾期。
    ISSUE_SLA_DAYS = { "Complaint" => 2, "TestingBug" => 0 }.freeze

    def call
      self.month_kpi          = parse_month_kpi(IssueSheetsClient.fetch_month_kpi_rows)
      self.daily_kpi          = parse_daily_kpi(IssueSheetsClient.fetch_daily_kpi_rows)
      self.issues              = parse_issues(IssueSheetsClient.fetch_issue_rows)
      self.project_breakdown = compute_project_breakdown(issues)

      # 月份選單（起訖日期輸入的 min/max guardrail）納入進行中的當月（即使 month_kpi 尚無該月
      # 列，因為月結數字要等月底才產生）。
      current_year_month = Date.current.strftime("%Y-%m")
      self.available_months = (month_kpi.map { |m| m[:year_month] } + [ current_year_month ]).uniq.sort

      self.selected_from, self.selected_to = resolve_range(current_year_month)
      self.matched_months = available_months.select { |ym| month_overlaps_range?(ym, selected_from, selected_to) }
      matched_rows = month_kpi.select { |m| matched_months.include?(m[:year_month]) }
      self.settled_month_count = matched_rows.size

      # 每日趨勢與依專案分類統計皆依所選期間呈現（兩者與月度 KPI 同屬「統計摘要」分頁籤，
      # 理應一起隨期間切換）；依專案分類以議題的 start_date（建立日）判斷所屬日期，
      # 議題明細本身則不受期間篩選（見需求 8）。
      self.daily_kpi_for_range = daily_kpi.select { |d| date_in_range?(d[:date], selected_from, selected_to) }
      range_issues = issues.select { |i| date_in_range?(i[:start_date], selected_from, selected_to) }
      self.month_project_breakdown = sort_project_breakdown(compute_project_breakdown(range_issues))

      # 客訴／測試／總Bug／攔截率改由 issues 原始資料即時算（見 compute_live_month_kpi 的說明），
      # 不再受限於 month_kpi 是否已結算，故一律有值。完成數／未結案／平均天數／SLA達標率仍
      # 讀 month_kpi（見 build_sheet_month_kpi），未結算時個別欄位為 nil，View 顯示「－」。
      self.selected_month_record = compute_live_month_kpi(range_issues).merge(build_sheet_month_kpi(matched_rows))
      self.selected_month_pending = settled_month_count.zero? && matched_months == [ current_year_month ]

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

    # 「議題是否結案／是否逾期／到期日是哪一天」這三個判斷，本 Actor（KPI 計算）與
    # Summary::BuildPmWeeklyReport（PM 週報的週別歸屬）共用同一套定義，故公開為 class method，
    # 比照 Sheets::FetchProjectProgress.overdue? 已建立的前例（同樣是為了讓其他層共用而公開）。
    def self.done?(issue)
      issue[:status].to_s.match?(ISSUE_DONE_STATUS_PATTERN)
    end

    # 回傳 [到期日, 來源]：試算表有填到期日就以它為準（`:sheet`）；沒填但該 type 有內建 SLA
    # 時，以「開始日 + SLA 天數」推算（`:sla`，PM 週報需要標示這是推算值而非試算表填的）；
    # 沒有可用依據時回傳 [nil, nil]（未定到期日，一律不視為逾期）。
    # 試算表「有填但無法解析」的髒資料一律回 [nil, nil]、不改用 SLA 推算，維持既有
    # issue_overdue? 的行為（解析失敗不算逾期），避免髒資料反而被判成逾期。
    def self.effective_due_date(issue)
      if issue[:due_date].present?
        date = parse_date(issue[:due_date])
        return date ? [ date, :sheet ] : [ nil, nil ]
      end

      sla_days = ISSUE_SLA_DAYS[issue[:type]]
      return [ nil, nil ] if sla_days.nil? || issue[:start_date].blank?

      start_date = parse_date(issue[:start_date])
      start_date ? [ start_date + sla_days, :sla ] : [ nil, nil ]
    end

    def self.overdue?(issue)
      date, = effective_due_date(issue)
      date.present? && date < Date.current
    end

    def self.parse_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
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

    # KPI 卡片：待處理議題（未完成）／緊急客訴（未完成的客訴且已逾期——資料裡沒有優先權／
    # 嚴重度欄位，「客訴+已逾期」是目前能從既有資料算出最接近「緊急」的定義，見
    # warroom-issue-dashboard-ux-refresh 任務 2.1 的取捨說明）／逾期或未定到期日（未完成
    # 且到期日已過，或沒填到期日、也沒有對應 SLA 可判斷）。三者都只算「未完成」的議題，
    # 已完成的議題不算緊急也不算逾期。
    def compute_issue_kpis(issues)
      pending = issues.reject { |i| self.class.done?(i) }
      # overdue? 每筆只算一次（Date.parse 有成本），urgent_complaints／overdue_or_undated
      # 共用同一個結果，不各自重算一次。
      urgent_count = 0
      overdue_or_undated_count = 0
      pending.each do |i|
        overdue = self.class.overdue?(i)
        undated = i[:due_date].blank? && !ISSUE_SLA_DAYS.key?(i[:type])
        urgent_count += 1 if i[:type] == "Complaint" && overdue
        overdue_or_undated_count += 1 if undated || overdue
      end
      # 累積花費工時不限「未完成」——已完成的議題一樣花了那些工時，此卡片算的是「投入成本」
      # 不是「還剩多少要做」，跟前三個只算 pending 的卡片語意不同。
      total_hours_sum = issues.sum { |i| i[:total_hours].to_f }

      {
        pending: pending.size,
        urgent_complaints: urgent_count,
        overdue_or_undated: overdue_or_undated_count,
        total_hours_sum: total_hours_sum.round(2)
      }
    end

    # from／to 皆空時，預設當月區間（不是「最新已結算月份」）：每日趨勢與依專案分類統計是
    # 即時算的，當月進行中也有資料可看，預設卻停在上個月會讓使用者以為要自己動手切換才看
    # 得到「現在」的狀況。月度 KPI 卡片本來就有 selected_month_pending 處理「本月尚未結算」
    # 的顯示（見 View 的「尚未結算」文案），不需要靠切換預設月份來迴避這個狀態。
    # 只給一邊時，另一邊視為不限制。
    def resolve_range(current_year_month)
      return [ from, to ] if from.present? || to.present?

      month_bounds(current_year_month)
    end

    def month_bounds(year_month)
      first = Date.parse("#{year_month}-01")
      [ first, first.end_of_month ]
    rescue ArgumentError, TypeError
      [ nil, nil ]
    end

    def month_overlaps_range?(year_month, from_bound, to_bound)
      month_start = Date.parse("#{year_month}-01")
      month_end = month_start.end_of_month
      (from_bound.blank? || month_end >= from_bound) && (to_bound.blank? || month_start <= to_bound)
    rescue ArgumentError, TypeError
      false
    end

    # 客訴／測試／總Bug／攔截率改由這裡即時算，不再讀 month_kpi 表的對應欄位：以真實資料
    # 逐月比對過，month_kpi 表這幾欄與 issues 原始資料經常對不上（例如 2026-08 客訴，表上
    # 25、issues 實際算出 27），研判是另一個外部流程（非本 app）產生的預先彙總快照，與
    # issues 之間存在落差，原因不明。issues 才是單一事實來源，改為即時算後兩邊必定一致。
    #
    # 攔截率＝測試 ÷ (客訴＋測試) × 100，已用真實資料反推驗證公式（8 個月全部對上到小數點後
    # 兩位）；總Bug 皆等於客訴＋測試（month_kpi 表本身也是如此，未獨立計算）。
    def compute_live_month_kpi(issues_in_range)
      complaint = issues_in_range.count { |i| i[:type] == "Complaint" }
      testing = issues_in_range.count { |i| i[:type] == "TestingBug" }
      total_bug = complaint + testing

      {
        complaint: complaint,
        testing: testing,
        total_bug: total_bug,
        block_rate: total_bug.positive? ? (testing.to_f / total_bug * 100).round(2) : nil
      }
    end

    # 完成數／未結案／平均天數／SLA達標率目前只能讀 month_kpi 表：試過幾種常見定義（依
    # start_date 所在月份、依狀態關鍵字判斷完成、以 work_days 算平均天數）逐月比對真實資料，
    # 差距達數十筆／數倍之譜，代表算法本身就猜錯，故不比照上面的客訴／測試改成即時算，避免
    # 用一個沒有把握的公式取代另一個不確定來源。
    #
    # 判斷依據是「真的有幾個月已結算資料」（matched_rows.size），不是「區間橫跨幾個月」——
    # 後者可能把尚無資料的進行中當月也算進去，讓「其實只有 1 個月有資料」的情況被誤判成彙總、
    # 白白隱藏掉本來可以精確顯示的比率（code review 回報）。
    # 剛好 1 個月有已結算列時，原樣回傳那一列這 4 個欄位（行為與改動前的單月選擇相同）；有
    # 多個月時，計數欄位（completed／unresolved）加總、比率欄位（avg_days／sla_rate）不彙總、
    # 設為 nil（不同月份的比率沒有能正確合併的算法，寧可不顯示也不要顯示誤導的近似值，見
    # View 對 nil 值顯示「－」的處理）；一個月已結算資料都沒有時，四個欄位皆為 nil。
    def build_sheet_month_kpi(matched_rows)
      return { completed: nil, unresolved: nil, avg_days: nil, sla_rate: nil } if matched_rows.empty?
      return matched_rows.first.slice(:completed, :unresolved, :avg_days, :sla_rate) if matched_rows.size == 1

      {
        completed: matched_rows.sum { |m| m[:completed].to_i },
        unresolved: matched_rows.sum { |m| m[:unresolved].to_i },
        avg_days: nil,
        sla_rate: nil
      }
    end

    def date_in_range?(date_str, from_bound, to_bound)
      return false if date_str.blank?

      date = Date.parse(date_str.to_s)
      (from_bound.blank? || date >= from_bound) && (to_bound.blank? || date <= to_bound)
    rescue ArgumentError, TypeError
      false
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

    # FORMATTED_VALUE（見 IssueSheetsClient）可能把數字格式化成含千分位逗號的字串（例如
    # "1,200"），先去除逗號再轉型，避免合法數字被誤判為無法解析（與 305
    # Sheets::FetchProjectBurndown#safe_float 的處理一致）。
    def safe_float(value)
      return nil if value.nil? || value.to_s.strip.empty?

      Float(value.to_s.delete(","))
    rescue ArgumentError, TypeError
      nil
    end
  end
end
