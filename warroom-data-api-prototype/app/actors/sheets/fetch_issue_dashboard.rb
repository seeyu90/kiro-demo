# frozen_string_literal: true

module Sheets
  class FetchIssueDashboard < ApplicationActor
    # 起訖日期區間篩選，取代原本的單一 month 參數：兩者皆空時預設當月（需求 9.1）；
    # 只給一邊時另一邊視為不限制（比照 305/307 共用的 DateRangeFilterable 慣例）。
    input :from, default: nil
    input :to, default: nil
    input :project, default: nil
    # 狀態／類型改成多選（比照 305 的 task_types 慣例）：controller 沒帶這個 query param 時
    # （使用者第一次載入頁面）傳 nil，Actor 套用預設值；使用者主動把勾選全部取消送出表單時，
    # controller 會傳空陣列 []，此時視為「不篩選、顯示全部」，不是「不显示任何一筆」——跟
    # 「類型」欄位原本 blank? 就是不篩選的行為一致，只是從單一值改成陣列。
    input :status, default: nil
    input :breakdown_sort, default: nil
    input :breakdown_dir, default: "desc"
    # 「議題資料」分頁的搜尋框（比對主旨／議題編號／負責人）與類型篩選（見 TYPE_CATEGORIES）。
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
    output :selected_month_record
    output :daily_kpi_for_range
    output :month_project_breakdown
    output :projects
    output :statuses
    output :types
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

    # 「類型」篩選下拉的固定選項：不是「試算表裡目前出現過哪些值」（那樣會冒出空字串跟
    # 「Other」兩個分別代表同一件事的選項），而是業務本來就只認這三種分類，其餘原始值一律
    # 歸「Other」（見 issue_type_category）。
    TYPE_CATEGORIES = %w[Complaint TestingBug Other].freeze

    # 「議題資料」分頁狀態篩選的預設值：使用者第一次進頁面（未帶 status query param）時，
    # 只顯示還沒處理完的議題，不是把全部歷史議題一次攤開。比照
    # Sheets::FetchProjectProgress::DEFAULT_TASK_TYPES 的慣例，供 Controller 在
    # 「@selected_status 要顯示成預先勾選哪幾個」時引用同一份定義，不重複寫一次。
    DEFAULT_STATUSES = [ "新建立" ].freeze

    def call
      self.month_kpi          = parse_month_kpi(IssueSheetsClient.fetch_month_kpi_rows)
      self.daily_kpi          = parse_daily_kpi(IssueSheetsClient.fetch_daily_kpi_rows)
      self.issues              = parse_issues(IssueSheetsClient.fetch_issue_rows)
      self.project_breakdown = compute_project_breakdown(issues)

      # 月份選單（起訖日期輸入的 min/max guardrail）：原本納入 month_kpi 的月份清單，但月度
      # KPI 已經全部改成即時算（見 compute_month_kpi），不再依賴 month_kpi 的涵蓋範圍——月份
      # 選單改依 issues 實際的 start_date 範圍，使用者才能查到 month_kpi 表本來就沒涵蓋到的
      # 更早期資料（該表只有 2026 年幾個月，但 issues 一路回溯到 2023 年）。
      current_year_month = Date.current.strftime("%Y-%m")
      issue_year_months = issues.filter_map { |i| i[:start_date]&.slice(0, 7) }
      self.available_months = (issue_year_months + [ current_year_month ]).uniq.sort

      self.selected_from, self.selected_to = resolve_range(current_year_month)

      # 每日趨勢與依專案分類統計皆依所選期間呈現（兩者與議題 KPI 同屬「統計摘要」分頁籤，
      # 理應一起隨期間切換）；依專案分類以議題的 start_date（建立日）判斷所屬日期，
      # 議題明細本身則不受期間篩選（見需求 8）。
      self.daily_kpi_for_range = fill_daily_kpi_gaps(
        daily_kpi.select { |d| date_in_range?(d[:date], selected_from, selected_to) }, selected_from, selected_to
      )
      range_issues = issues.select { |i| date_in_range?(i[:start_date], selected_from, selected_to) }
      self.month_project_breakdown = sort_project_breakdown(compute_project_breakdown(range_issues))
      self.selected_month_record = compute_month_kpi(range_issues)

      # 原本沒有排序，是掃描 raw_2023～raw_2027（依年度分頁串接）時每個專案第一次出現的巧合
      # 順序，跟字母、注音都無關，被使用者回報看不出規則。改依字母排序（大小寫不分）；中文
      # 專案名稱沒有現成的注音／拼音排序函式庫可用（Ruby 內建 String 比較是萬國碼碼位序，不是
      # 注音），退而求其次至少讓中英文各自的排序都符合直覺，不是原本的隨機順序。
      self.projects = issues.map { |i| i[:project] }.compact.uniq.sort_by(&:downcase)
      self.statuses = issues.map { |i| i[:status] }.compact.uniq
      self.types = TYPE_CATEGORIES
      self.filtered_issues = filter_issues(issues)
      # KPI 卡片依「目前篩選結果」（含搜尋／類型篩選，分頁之前的完整結果）計算，不是
      # 分頁後那一頁的子集合，也不是完全未篩選的 issues 全量。
      self.issue_kpis = compute_issue_kpis(filtered_issues)
    rescue Google::Apis::ClientError => e
      # 錯誤對應邏輯與 305 Sheets::FetchProjectProgress 相同（見 rails-standards.md 的
      # failure_code 對應表）：三個讀取類別（議題 KPI／每日趨勢／議題明細）中任一失敗，
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

        case issue_type_category(issue[:type])
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
      # status／type 皆為陣列：status 為 nil（controller 完全沒收到這個 query param，代表
      # 使用者還沒送出過篩選表單）時套用 DEFAULT_STATUSES；使用者主動勾選後送出、即使全部
      # 取消勾選，controller 也會傳一個（可能是空的）陣列，此時空陣列視為「不篩選」，不會
      # 又掉回預設值——不然使用者永遠沒辦法用「清空狀態勾選」來看到全部狀態。type 沒有內建
      # 預設子集合（原本 blank? 就是不篩選），故 nil／[] 兩種情況都視為不篩選。
      selected_statuses = status.nil? ? DEFAULT_STATUSES : Array(status).reject(&:blank?)
      selected_types = Array(type).reject(&:blank?)

      issues
        .select { |i| project.blank? || i[:project] == project }
        .select { |i| selected_statuses.empty? || selected_statuses.include?(i[:status]) }
        .select { |i| selected_types.empty? || selected_types.include?(issue_type_category(i[:type])) }
        .select { |i| q.blank? || issue_matches_query?(i, q) }
        # 原始順序是 raw_2023～raw_2027 依分頁串接，等於「最舊的排最前面」——清空篩選會先看到
        # 447 筆裡最早的 2023 年資料。改成依議題編號降冪，新的排最前面（議題編號遞增產生，
        # 數字比字串排序才不會把「999」排在「1002」後面）。
        .sort_by { |i| -i[:issue_id].to_i }
    end

    # 三分類：Complaint／TestingBug 照原值，其餘（空白或任何其他字串，例如 "Other"）一律歸
    # 「Other」。跟 compute_project_breakdown、type 篩選共用同一套分類，只需要維護一處。
    def issue_type_category(type)
      TYPE_CATEGORIES.include?(type) ? type : "Other"
    end

    def issue_matches_query?(issue, query)
      needle = query.to_s.downcase
      [ issue[:subject], issue[:issue_id], issue[:assigned_to] ].any? { |value| value.to_s.downcase.include?(needle) }
    end

    # KPI 卡片：待處理議題（未完成）／緊急客訴（未完成的客訴且已逾期——資料裡沒有優先權／
    # 嚴重度欄位，「客訴+已逾期」是目前能從既有資料算出最接近「緊急」的定義，見
    # warroom-issue-dashboard-ux-refresh 任務 2.1 的取捨說明）。兩者都只算「未完成」的議題，
    # 已完成的議題不算緊急。
    #
    # 原本還有第三張「逾期或未定到期日」卡（未完成且已逾期，或沒填到期日又沒有對應 SLA 可
    # 判斷），跟「緊急客訴」高度重疊（逾期的客訴兩張卡都算）、又把「已逾期」跟「不知道到期日」
    # 兩種不同性質的東西用一個 OR 混在一起，使用者反應看不出這張卡實際在回答什麼問題，決定
    # 直接移除，不再計算。
    def compute_issue_kpis(issues)
      pending = issues.reject { |i| self.class.done?(i) }
      urgent_count = pending.count { |i| i[:type] == "Complaint" && self.class.overdue?(i) }
      # 累積花費工時不限「未完成」——已完成的議題一樣花了那些工時，此卡片算的是「投入成本」
      # 不是「還剩多少要做」，跟前面只算 pending 的卡片語意不同。
      total_hours_sum = issues.sum { |i| i[:total_hours].to_f }

      {
        pending: pending.size,
        urgent_complaints: urgent_count,
        total_hours_sum: total_hours_sum.round(2)
      }
    end

    # from／to 皆空時，預設當月區間（不是「最新已結算月份」）：議題 KPI 現在全部即時算（見
    # compute_month_kpi），當月進行中一樣有真實數字可看，預設卻停在上個月會讓使用者以為要
    # 自己動手切換才看得到「現在」的狀況。只給一邊時，另一邊視為不限制。
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

    # 客訴／測試／總Bug／攔截率／完成數／未結案／平均天數／SLA達標率全部改由這裡即時算，
    # 不再讀 month_kpi 表：以真實資料逐月比對過，month_kpi 表這幾欄與 issues 原始資料經常對
    # 不上（例如 2026-08 客訴，表上 25、issues 實際算出 27）。使用者提供了產生 month_kpi 的
    # n8n 腳本原始碼，這裡幾乎是照抄那份邏輯（資料來源換成這裡已解析過的 issues），拿正確
    # 公式重算後，完全吻合的月份（例如 2026-02／04／06）證實公式無誤；仍有落差的月份
    # （例如 2026-08：完成數表上 13、重算 16），研判是 month_kpi 本身是某次執行當下的快照，
    # 那之後試算表上的個別列被回頭訂正過（狀態、work_days 等會隨時間變動的欄位），快照沒有
    # 跟著更新——改成即時算，這類落差往後不會再發生。
    #
    # 公式（皆以「客訴」為分母／分子主體）：
    # - 攔截率＝測試 ÷ (客訴＋測試) × 100（已用真實資料反推驗證，8 個月全部對上到小數點後
    #   兩位）；total_bug（客訴＋測試）只當攔截率的分母用，不對外顯示獨立卡片——使用者
    #   反應這張卡只是前兩張卡相加，自己心算就好，移除騰出版面給更有用的指標。
    # - 完成數：客訴且狀態「恰好」是「已解決」——注意這比全站其他地方用的
    #   ISSUE_DONE_STATUS_PATTERN（完成│確認│關閉│解決│結束）窄很多；照抄 n8n 腳本原始定義，
    #   不是本頁另外訂的規則。
    # - 未結案：客訴總數－完成數，兩者相加必為客訴總數，方便使用者一眼看出「這個月的客訴
    #   目前處理到哪裡」。原本 n8n 腳本的定義是「狀態恰好是『新建立』或『實作中』，不分
    #   類型」，跟這裡改成的「客訴且非已解決」不是同一件事（例如「已拒絕」「已暫停」的客訴，
    #   原定義不算未結案，這裡會算）——刻意改成跟完成數互補，讓兩張卡數字對得起來比忠於
    #   原始腳本更重要，且這張卡本來就不是照抄 n8n（腳本沒有拆分「未結」到底算不算客訴專屬）。
    # - 平均天數：客訴（不分完成與否）的 work_days 總和 ÷ 客訴筆數。
    # - SLA達標率：客訴裡 work_days 恰好等於 1（腳本裡 SLA_COMPLAINT 天數）的筆數 ÷ 客訴筆數
    #   ×100——這個 1 天是 n8n 腳本自訂的回報用 SLA 目標，跟本頁「緊急客訴」判斷逾期用的
    #   ISSUE_SLA_DAYS["Complaint"]＝2 天是兩回事，本來就是各自獨立維護的兩個數字，不要
    #   誤以為要對齊。
    # - 遲期客訴：客訴裡「目前仍未完成（用全站共通的 done? 判斷，不是上面完成數的窄定義）
    #   且已逾期（用全站共通的 overdue?／2 天 SLA）」的筆數——前面幾項都是「回顧型」（這個月
    #   做得如何），這張是「現在還有什麼在燒」的即時風險指標，跟「議題資料」分頁的「緊急客訴」
    #   是同一套判斷邏輯，只是這裡限定在本頁所選期間的客訴。
    # - 總花費工時：不分類型（客訴／測試／其他都算，也不分完成與否），算的是投入成本，
    #   跟「議題資料」分頁的「累積總花費工時」是同一個概念，差別只在這裡限定所選期間。
    #
    # 分母為 0（區間內沒有客訴／沒有客訴＋測試）時，比率類欄位回傳 nil，View 顯示「－」，
    # 不假裝算得出一個數字；計數類欄位恆為整數，不會是 nil。
    COMPLAINT_SLA_DAYS = 1
    COMPLAINT_DONE_STATUS = "已解決"

    def compute_month_kpi(issues_in_range)
      complaints = issues_in_range.select { |i| i[:type] == "Complaint" }
      testing_count = issues_in_range.count { |i| i[:type] == "TestingBug" }
      # 跟「依專案分類」表格的「其他」欄同一個分類規則（見 issue_type_category）；不計入
      # total_bug／攔截率，那兩者維持只看客訴／測試的原始定義。
      other_count = issues_in_range.count { |i| issue_type_category(i[:type]) == "Other" }
      total_bug = complaints.size + testing_count
      total_days = complaints.sum { |i| i[:work_days].to_f }
      sla_pass = complaints.count { |i| i[:work_days].to_f.positive? && i[:work_days].to_f <= COMPLAINT_SLA_DAYS }
      completed_count = complaints.count { |i| i[:status] == COMPLAINT_DONE_STATUS }
      pending_complaints = complaints.reject { |i| self.class.done?(i) }

      {
        complaint: complaints.size,
        testing: testing_count,
        other: other_count,
        block_rate: total_bug.positive? ? (testing_count.to_f / total_bug * 100).round(2) : nil,
        completed: completed_count,
        unresolved: complaints.size - completed_count,
        avg_days: complaints.any? ? (total_days / complaints.size).round(2) : nil,
        sla_rate: complaints.any? ? (sla_pass.to_f / complaints.size * 100).round(2) : nil,
        overdue_complaints: pending_complaints.count { |i| self.class.overdue?(i) },
        # 不分類型（客訴／測試／其他都算），跟「議題資料」分頁「累積總花費工時」卡是同一個
        # 概念（投入成本，不分完成與否），只是這裡限定在本頁所選期間，不是全部議題。
        total_hours_sum: issues_in_range.sum { |i| i[:total_hours].to_f }.round(2)
      }
    end

    def date_in_range?(date_str, from_bound, to_bound)
      return false if date_str.blank?

      date = Date.parse(date_str.to_s)
      (from_bound.blank? || date >= from_bound) && (to_bound.blank? || date <= to_bound)
    rescue ArgumentError, TypeError
      false
    end

    # 每日趨勢圖用陣列索引決定 X 軸間距（見 IssuesHelper#trend_chart_points），不是依日期本身
    # 的間隔，兩個相鄰資料點永遠等距。daily_kpi 分頁本身沒有假日／週末的列（業務不在假日回報，
    # 一年約 185 列對應約 260 個平日），若直接拿這些「有資料的日子」當資料點，週末造成的 2～3
    # 天空隙跟平日的 1 天空隙在圖上會畫成同樣寬度，時間軸因此失真。改為把整個所選區間逐日補
    # 齊，缺的日子補 0，X 軸間距才會真正對應日曆天數。
    #
    # 區間橫跨到未來（例如當月預設到月底，但月份還沒過完）時，上限收在「今天」，不畫還沒發生
    # 的日子（那些不是「當天 0 筆」，是「還沒到那一天」，補 0 反而是謊報）。任一邊界為 nil
    # （開放式區間，例如只給 from 沒給 to）時無法決定要補到哪一天，維持原樣不補。
    def fill_daily_kpi_gaps(records, from_bound, to_bound)
      return records if from_bound.blank? || to_bound.blank?

      range_end = [ to_bound, Date.current ].min
      return records if from_bound > range_end

      by_date = records.index_by { |r| r[:date] }
      (from_bound..range_end).map do |date|
        by_date[date.iso8601] || { date: date.iso8601, complaint: 0, testing: 0, other: 0, total: 0 }
      end
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
