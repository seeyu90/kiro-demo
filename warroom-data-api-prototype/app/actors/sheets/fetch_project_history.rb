# frozen_string_literal: true

module Sheets
  class FetchProjectHistory < ApplicationActor
    input :project, default: nil
    input :year, default: nil
    output :overview_rows
    output :overview_years
    output :detail
    output :roster_unavailable
    output :gantt_duration_unavailable
    output :failure_code
    output :message

    RESOLVED_STATUSES = %w[已結束 已解決].freeze

    def call
      # Roster（客戶/PM 對照）失敗時降級顯示，不擋整頁：305/306/307 才是本頁面的核心資料，
      # 客戶/PM 只是錦上添花的補充欄位。實務上發現這份試算表常常還沒把 Service Account 加進
      # 共用名單（跟 305/306/307 是不同試算表、不同擁有者，共用設定各自獨立），若因此讓整頁
      # 連 305/306/307 都看不到，反而讓一個非核心資料源的權限問題擋住核心功能。找不到對應
      # 專案時客戶/PM/狀態顯示 `—`（需求 2.2）；roster 整體失敗時所有專案都顯示 `—`，
      # 差別只在於前者是「查得到 roster 但這個專案不在清單裡」，後者是「roster 整批查不到」，
      # 對畫面呈現而言是同一件事，故共用同一套「找不到就給空值」的處理方式。
      roster_result = Sheets::FetchProjectRoster.result
      if roster_result.success?
        roster = roster_result.roster
        self.roster_unavailable = false
      else
        roster = []
        self.roster_unavailable = true
      end

      progress_result = Sheets::FetchProjectProgress.result(scope: "all", incomplete_only: false)
      return propagate_failure(progress_result) unless progress_result.success?

      # 307 的專案命名跟 305/roster 是兩套完全獨立的體系（見 build_detail／matched_burndown_
      # issues 附註），無法靠 Sheets::FetchProjectBurndown 自己的 project 篩選對上，故一律抓
      # 全量（project: nil），篩選邏輯自己做。橫向總覽的甘特圖也需要這份資料才能畫出真正的
      # 開發區間（307 才有 start_date～due_date；305 只有檢查點，見需求 1），故不論是否選定
      # project 都呼叫一次，橫向總覽與縱向歷程共用同一份 burndown_issues，避免重複打 API。
      #
      # 【設計變更】307 過去只在縱向歷程呼叫，理由是「不讓非核心資料來源的問題拖累總覽頁」；
      # 現在總覽甘特圖需要它，但沿用同一個精神：307 失敗時甘特圖降級為全部專案皆無色塊
      # （gantt_duration_unavailable，畫面顯示提示文字），不擋總覽頁（需求 1.3）。只有在使用者
      # 已選定 project、縱向歷程本來就必須依賴 307 時，307 失敗才會讓整體請求失敗（需求 1.3a，
      # 行為不變）。
      burndown_overview_result = Sheets::FetchProjectBurndown.result(status: "all")
      duration_data_available = burndown_overview_result.success?
      if duration_data_available
        burndown_issues = burndown_overview_result.issues
        self.gantt_duration_unavailable = false
      elsif project.blank?
        burndown_issues = []
        self.gantt_duration_unavailable = true
      else
        return propagate_failure(burndown_overview_result)
      end

      # 年度下拉選單的選項固定依「全部」燃盡議題算出（不受目前篩選影響），選單本身不會因為使用者
      # 選了某個年度就少了其他年度可選。
      self.overview_years = burndown_issues.filter_map { |i| i[:start_date].to_s[0, 4].presence }.uniq.sort.reverse

      self.overview_rows =
        build_overview_rows(roster, progress_result.grouped_data, burndown_issues, year, duration_data_available)
      return unless project.present?

      issue_result = Sheets::FetchIssueDashboard.result
      return propagate_failure(issue_result) unless issue_result.success?

      roster_row = resolve_roster_row(roster, project)
      self.detail = build_detail(project, roster_row, burndown_issues, issue_result.issues, year)
    end

    private

    # 四個子 Actor 中任一失敗即整體失敗，不做部分成功回傳；直接沿用先失敗的那個 Actor 的
    # failure_code/message，不重新包裝（需求 6.1）。
    def propagate_failure(result)
      fail!(failure_code: result.failure_code, message: result.message)
    end

    # 實測發現 305 的專案名稱有時用 Roster 的「專案」全名（如 "Virtuous HRM"），有時用「專案
    # 縮寫」（如 "亞炬 Platform"、"RAG"），沒有固定用哪一欄，故兩欄都查找，任一欄比對到就算
    # （同一個縮寫理論上不會同時是另一個專案的全名，實務資料裡也沒出現這種衝突）。橫向總覽
    # （build_overview_rows）與縱向歷程（build_detail 解析 canonical 名稱／客戶）都靠這個
    # 共用查找，確保兩處對同一個 305 專案名稱的解讀一致。
    def resolve_roster_row(roster, project_name)
      roster.find { |r| r[:project_name] == project_name } ||
        roster.find { |r| r[:abbreviation].present? && r[:abbreviation] == project_name } ||
        {}
    end

    # ── 橫向總覽 ──────────────────────────────────────────────

    # 以 305 的專案名稱為主體（有進度可看的專案），Roster 找不到對應列時客戶/PM/狀態為 nil，
    # 不視為錯誤（需求 2.1、2.2）。
    #
    # 每列的議題清單（:tasks）一律用該專案對應到的 307 議題（依 year 篩選開案年度，預設今年，
    # 由 controller 決定，見 ProjectHistoryController#index），同一份清單同時供甘特圖畫時程條、
    # 清單頁展開後的議題明細表格使用，避免兩處各自維護一份轉換邏輯。
    #
    # IF 已指定年度（year 有值）AND 307 資料本身可用（duration_data_available），
    # THEN 該年度沒有任何對應議題的專案直接不列入總覽（不顯示空白列/空白展開內容，使用者要求
    # 「今年沒有任何議題的專案就不列出來」）；307 整批讀取失敗時（duration_data_available 為
    # false）不套用這條排除規則，維持既有降級慣例——全部專案照常列出、只是議題清單是空的，
    # 不讓一個非核心資料源的問題把整個專案清單清空。
    def build_overview_rows(roster, progress_grouped, burndown_issues, year, duration_data_available)
      progress_grouped.filter_map do |project_name, _progress_tasks|
        roster_row = resolve_roster_row(roster, project_name)
        matched = matched_burndown_issues(roster_row, project_name, burndown_issues)
        matched_in_year = filter_issues_by_year(matched, year)

        next if duration_data_available && year.present? && matched_in_year.empty?

        tasks = duration_tasks_from_burndown(matched_in_year)

        {
          project_name: project_name,
          customer: roster_row[:customer],
          pm: roster_row[:pm],
          status: roster_row[:status],
          tasks: tasks,
          progress_percent: progress_percent_for(tasks),
          hours_estimated: sum_estimated_hours(tasks),
          hours_consumed: sum_consumed_hours(tasks),
          has_overdue: tasks.any? { |t| duration_task_overdue?(t) }
        }
      end
    end

    def filter_issues_by_year(issues, year)
      return issues if year.blank?

      issues.select { |i| i[:start_date].to_s.start_with?(year.to_s) }
    end

    # 307↔Roster 對應規則：Roster 該專案列的 burndown_names_raw 有值時，307 議題的 project 名稱
    # 只要整串出現在該欄文字裡即算對應；為空時退回以 project_name（呼叫端傳入的分組鍵／使用者
    # 選定的專案名稱）與 307 議題的 project 精確比對。橫向總覽（build_overview_rows）與縱向歷程
    # （build_detail）共用同一份規則，確保兩處對同一個專案給出一致的 307 對應結果（需求 1a）。
    def matched_burndown_issues(roster_row, project_name, burndown_issues)
      burndown_names_raw = roster_row[:burndown_names_raw].presence
      if burndown_names_raw
        burndown_issues.select { |i| burndown_names_raw.include?(i[:project].to_s) }
      else
        burndown_issues.select { |i| i[:project] == project_name }
      end
    end

    # 307 議題沒有「實際完成日」欄位，只有 status／due_date（見 design.md 決策）。:assignees／
    # :progress_percent／:overdue 是甘特圖 helper 不會讀取、只給清單頁展開後的議題明細表格用的
    # 欄位；同一份 hash 兩處共用，不為了「甘特圖只需要幾個欄位」另外拆一份精簡版本。
    def duration_tasks_from_burndown(issues)
      issues.map do |issue|
        consumed = consumed_hours_for(issue)
        {
          task_name: issue[:issue_title],
          assignees: issue[:assignees],
          status: issue[:status],
          start_date: issue[:start_date],
          due_date: issue[:due_date],
          done: issue[:status] == "done",
          estimated_hours: issue[:estimated_hours],
          consumed_hours: consumed,
          progress_percent: task_progress_percent(issue[:estimated_hours], consumed)
        }.then { |task| task.merge(overdue: duration_task_overdue?(task)) }
      end
    end

    def task_progress_percent(estimated_hours, consumed_hours)
      return nil if consumed_hours.nil?

      estimated = estimated_hours.to_f
      return nil if estimated.zero?

      ((consumed_hours.to_f / estimated) * 100).round.clamp(0, 100)
    end

    # 已消耗人時 = 預估人時 − actual_series 最後一筆剩餘人時；沒有任何 actual_series 資料點
    # （例如剛開案、燃盡表還沒填）時回傳 nil，不得顯示成 0（需求 2.2）。
    def consumed_hours_for(issue)
      last_point = issue[:actual_series]&.last
      return nil if last_point.nil?

      (issue[:estimated_hours].to_f - last_point[:hours].to_f).round(2)
    end

    # 只加總「有工時資料」的議題（consumed_hours 不為 nil），避免燃盡表還沒填的議題把比例拉低
    # 成看起來像 0% 進度（需求 3.1）；沒有任何議題有工時資料時回傳 nil，顯示為「—」，不得顯示
    # 0%（需求 3.3）。
    def progress_percent_for(tasks)
      pairs = tasks.filter_map { |t| [ t[:estimated_hours].to_f, t[:consumed_hours] ] unless t[:consumed_hours].nil? }
      return nil if pairs.empty?

      total_estimated = pairs.sum { |estimated, _| estimated }
      return nil if total_estimated.zero?

      total_consumed = pairs.sum { |_, consumed| consumed }
      ((total_consumed / total_estimated) * 100).round.clamp(0, 100)
    end

    def sum_estimated_hours(tasks)
      values = tasks.filter_map { |t| t[:estimated_hours] unless t[:consumed_hours].nil? }
      return nil if values.empty?

      values.sum(&:to_f).round(1)
    end

    def sum_consumed_hours(tasks)
      values = tasks.filter_map { |t| t[:consumed_hours] }
      return nil if values.empty?

      values.sum.round(1)
    end

    # 未完成且 due_date 已過今天。
    def duration_task_overdue?(task)
      return false if task[:done]

      due_date = parse_date(task[:due_date])
      due_date && due_date < Date.current
    end

    # ── 縱向歷程 ──────────────────────────────────────────────

    # 305／306／307 三邊的專案命名各自獨立，沒有單一共通鍵可以直接比對（實測發現的真實資料
    # 狀況，非假設）：
    # - 306 的議題明細用 Roster「專案」全名（如 "AG 亞炬"），故用 roster_row[:project_name]
    #   （resolve_roster_row 解析出來的 canonical 名稱）比對，而非直接拿使用者選的 305 縮寫式
    #   名稱去比對（兩者對不上）。
    # - 307 用比 305/roster 更細的顆粒度追蹤（例如「亞炬 Platform」底下實際拆成「亞炬 Else／
    #   Wms／Flow／PMS」四個 307 議題），且客戶名稱與各系統的專案前綴不一定一致（例如「立翔
    #   機電」客戶對應的專案前綴其實是「立翔」，不是「立翔機電」），無法用客戶名稱或任何自動
    #   規則安全推得。改為讀取 Roster 人工維護的「307對應專案」欄（`burndown_names_raw`），
    #   比對規則見 matched_burndown_issues（橫向總覽的甘特圖也共用同一份規則，需求 1a）。
    def build_detail(project, roster_row, burndown_issues, all_issues, year)
      canonical_name = roster_row[:project_name].presence || project
      project_issues = all_issues.select { |i| i[:project] == canonical_name }

      matched = matched_burndown_issues(roster_row, project, burndown_issues)

      work_hours_series = aggregate_work_hours(matched)
      ideal_series = aggregate_ideal_series(matched)
      actual_series = aggregate_actual_series(matched)
      testing_trend = monthly_testing_counts(project_issues)

      # 客訴議題狀態不受年度篩選影響（顯示的是「目前」已解決/未解決幾個，屬於當下狀態，不是
      # 時間趨勢），比照 306 頁「議題明細不受月份篩選影響」的既有慣例（見 requirements.md）。
      {
        available_years: available_years(work_hours_series, ideal_series, actual_series, testing_trend),
        selected_year: year,
        work_hours_series: filter_series_by_year(work_hours_series, year),
        ideal_series: filter_series_by_year(ideal_series, year),
        actual_series: filter_series_by_year(actual_series, year),
        testing_trend: filter_series_by_year(testing_trend, year),
        complaint_summary: complaint_status(project_issues)
      }
    end

    # 年度篩選只影響三個時間序列圖表（花費工時／燃盡圖／測試問題趨勢），下拉選單的可選年度依
    # 這三者實際涵蓋的日期範圍算出，避免列出該專案根本沒有資料的年份。
    def available_years(*serieses)
      serieses.flatten.filter_map { |point| point[:date].to_s[0, 4] }.uniq.sort.reverse
    end

    def filter_series_by_year(series, year)
      return series if year.blank?

      series.select { |point| point[:date].to_s.start_with?(year.to_s) }
    end

    # 依議題 actual_series（剩餘人時）相鄰兩點的差值反推每週實際花費工時：第一週花費 =
    # estimated_hours − actual_series[0]，第 N 週花費 = actual_series[N-1] − actual_series[N]
    # （需求 4.2）。
    def issue_weekly_spent(issue)
      previous_remaining = issue[:estimated_hours].to_f

      issue[:actual_series].map do |point|
        spent = (previous_remaining - point[:hours].to_f).round(2)
        previous_remaining = point[:hours].to_f
        { date: point[:date], hours: spent }
      end
    end

    def aggregate_work_hours(issues)
      sum_series_by_date(issues.map { |i| issue_weekly_spent(i) })
    end

    # 已知簡化：不同議題的 actual_series 涵蓋週別範圍可能不同（Sheets::FetchProjectBurndown
    # 依各議題自己的開案日期裁切週範圍），加總只涵蓋各議題各自有資料的週別，未涵蓋的週別視為 0
    # （見 requirements.md「已知簡化」段落）。
    def aggregate_actual_series(issues)
      sum_series_by_date(issues.map { |i| i[:actual_series] })
    end

    def sum_series_by_date(series_list)
      totals = Hash.new(0.0)
      order = []
      series_list.each do |series|
        series.each do |point|
          order << point[:date] unless totals.key?(point[:date])
          totals[point[:date]] += point[:hours].to_f
        end
      end
      order.sort.map { |date| { date: date, hours: totals[date].round(2) } }
    end

    # 不可直接加總各議題「已含起訖錨點」的 ideal_series（Sheets::FetchProjectBurndown#compute_
    # ideal_series 的輸出）——不同議題的錨點日期不同，加總後會在只有少數議題有資料的日期出現不該
    # 有的凹陷（同 warroom-project-history-static-prototype 的 project-history-detail.js 曾修正過
    # 的 bug）。改為在彙總的每一個共同日期上，逐議題以起訖日期比例公式即時算出當天的理想剩餘人時
    # 再加總；缺少合法起訖日期的議題當天回傳 nil，直接排除不計入（需求 4.3）。
    def ideal_hours_at(issue, date)
      start_d = parse_date(issue[:start_date])
      due_d = parse_date(issue[:due_date])
      return nil if start_d.nil? || due_d.nil? || due_d <= start_d

      ratio = ((date - start_d).to_f / (due_d - start_d).to_f).clamp(0.0, 1.0)
      (issue[:estimated_hours].to_f * (1 - ratio)).round(2)
    end

    def aggregate_ideal_series(issues)
      dates = issues.flat_map { |i| i[:actual_series].map { |p| Date.parse(p[:date]) } }.uniq.sort

      dates.filter_map do |date|
        values = issues.filter_map { |i| ideal_hours_at(i, date) }
        next if values.empty?

        { date: date.iso8601, hours: values.sum.round(2) }
      end
    end

    def monthly_testing_counts(issues)
      testing = issues.select { |i| i[:type] == "TestingBug" }
      counts = Hash.new(0)
      testing.each do |issue|
        month = month_start(issue[:start_date])
        next if month.nil?

        counts[month] += 1
      end
      counts.keys.sort.map { |month| { date: month, count: counts[month] } }
    end

    def month_start(date_str)
      date = parse_date(date_str)
      return nil if date.nil?

      date.beginning_of_month.iso8601
    end

    # 依議題明細清單裡每筆客訴議題自己的 status 欄位逐筆判斷，不使用 306 月度彙總欄位
    # （需求 5.2）。
    def complaint_status(issues)
      complaints = issues.select { |i| i[:type] == "Complaint" }
      resolved, unresolved = complaints.partition { |i| RESOLVED_STATUSES.include?(i[:status]) }

      { resolved_count: resolved.size, unresolved_count: unresolved.size, unresolved_list: unresolved }
    end

    def parse_date(date_str)
      return nil if date_str.nil? || date_str.to_s.strip.empty?

      Date.parse(date_str.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
