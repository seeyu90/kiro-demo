# frozen_string_literal: true

module Sheets
  class FetchProjectHistory < ApplicationActor
    input :project, default: nil
    output :overview_rows
    output :detail
    output :roster_unavailable
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

      issue_result = Sheets::FetchIssueDashboard.result
      return propagate_failure(issue_result) unless issue_result.success?

      # 307 的專案命名跟 305/roster 是兩套完全獨立的體系（見下方 build_detail 附註），無法靠
      # Sheets::FetchProjectBurndown 自己的 project 篩選對上，故一律抓全量（project: nil），
      # 篩選邏輯自己在 build_detail 做。
      burndown_result = Sheets::FetchProjectBurndown.result(status: "all")
      return propagate_failure(burndown_result) unless burndown_result.success?

      # overview_rows 一律計算（詳情頁的專案下拉選單需要完整專案清單），detail 僅在帶
      # project 參數時額外計算。
      self.overview_rows = build_overview_rows(roster, progress_result.grouped_data)
      if project.present?
        roster_row = resolve_roster_row(roster, project)
        self.detail = build_detail(project, roster_row, burndown_result.issues, issue_result.issues)
      end
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
    def build_overview_rows(roster, progress_grouped)
      progress_grouped.map do |project_name, tasks|
        roster_row = resolve_roster_row(roster, project_name)
        planned = tasks.filter_map { |t| t[:planned_completion_date] }.max
        ongoing = tasks.any? { |t| t[:actual_completion_date].blank? }
        actual = ongoing ? nil : tasks.filter_map { |t| t[:actual_completion_date] }.max

        {
          project_name: project_name,
          customer: roster_row[:customer],
          pm: roster_row[:pm],
          status: roster_row[:status],
          planned_completion_date: planned,
          actual_completion_date: actual,
          tasks: tasks
        }
      end
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
    #   規則安全推得。改為讀取 Roster 人工維護的「307對應專案」欄（`burndown_names_raw`）：
    #   307 議題只要其 project 名稱整串出現在這欄文字裡就算屬於該專案，不管欄位裡用逗號或空白
    #   分隔多個名稱（見 Sheets::FetchProjectRoster 的解析附註）。沒填這欄或 Roster 查無此專案
    #   時，退回直接以 305 傳入的 project 字串精確比對（原本的行為，涵蓋沒有 Roster 資料時仍
    #   可能剛好命名一致的情況）。
    def build_detail(project, roster_row, burndown_issues, all_issues)
      canonical_name = roster_row[:project_name].presence || project
      project_issues = all_issues.select { |i| i[:project] == canonical_name }

      burndown_names_raw = roster_row[:burndown_names_raw].presence
      matched_burndown_issues =
        if burndown_names_raw
          burndown_issues.select { |i| burndown_names_raw.include?(i[:project].to_s) }
        else
          burndown_issues.select { |i| i[:project] == project }
        end

      {
        work_hours_series: aggregate_work_hours(matched_burndown_issues),
        ideal_series: aggregate_ideal_series(matched_burndown_issues),
        actual_series: aggregate_actual_series(matched_burndown_issues),
        testing_trend: weekly_testing_counts(project_issues),
        complaint_summary: complaint_status(project_issues)
      }
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

    def weekly_testing_counts(issues)
      testing = issues.select { |i| i[:type] == "TestingBug" }
      counts = Hash.new(0)
      testing.each do |issue|
        week = week_start(issue[:start_date])
        next if week.nil?

        counts[week] += 1
      end
      counts.keys.sort.map { |week| { date: week, count: counts[week] } }
    end

    def week_start(date_str)
      date = parse_date(date_str)
      return nil if date.nil?

      date.beginning_of_week(:monday).iso8601
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
