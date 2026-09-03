# frozen_string_literal: true

module Summary
  # CEO 週報彙總：把 305/306/307/階段追蹤四個既有 Actor 的結果，依 Roster 的專案清單為主鍵
  # 彙總成「每個專案一筆健康度」+「公司層 KPI」，供 ExecutiveSummaryController 渲染單一頁面。
  #
  # 專案識別串接沿用既有慣例（同 Sheets::FetchProjectHistory）：305 的專案名稱以 Roster 的
  # 「專案（全名）」或「專案縮寫」比對，307 議題以 Roster 的 burndown_names_raw 子字串比對。
  # 306（臭蟲議題）的 project 欄位比照同一套規則盡量比對，比對不到時不影響專案卡片健康度
  # （客訴數只是補充資訊），只在公司層 KPI 計入總數。
  #
  # 階段追蹤（Sheets::FetchPhaseTracking）刻意「不」併入每個專案的健康度卡片：階段追蹤讀的是
  # 另一份試算表的「專案」分頁（ProjectProfilesSheetsClient，鍵是 Notion/Github 專案代碼，例如
  # HRM、JZNPMS），跟 Roster 的「專案（全名）／縮寫」是第三套完全獨立的命名系統，且目前沒有
  # 任何既有欄位（不像 307 有 burndown_names_raw）能可靠對照兩者。勉強用客戶/PM 相同去猜測
  # 對應專案，在客戶或 PM 有重複時會猜錯，對 CEO 儀表板這種決策依據來說,錯誤的對照比不對照
  # 更危險，故階段追蹤的例外改成獨立一節呈現（見 phase_exceptions），不假裝跟其他四個資料源
  # 對到同一張卡片上。
  class BuildExecutiveSummary < ApplicationActor
    include BurndownHelper

    output :projects
    output :portfolio
    output :phase_exceptions
    output :phase_exceptions_by_customer
    output :last_week_summary
    output :roster_unavailable
    output :burndown_unavailable
    output :issues_unavailable
    output :phase_tracking_unavailable
    output :failure_code
    output :message

    def call
      # 305 是核心資料（跟 Sheets::FetchProjectHistory 同一個取捨）：沒有 305 就沒有「有哪些
      # 專案、有沒有逾期任務」這個健康度儀表板最基本的依據，讀取失敗即整頁失敗。
      progress_result = Sheets::FetchProjectProgress.result(scope: "all", incomplete_only: false)
      return fail!(failure_code: progress_result.failure_code, message: progress_result.message) unless progress_result.success?

      roster = fetch_roster
      burndown_issues = fetch_burndown_issues
      issue_rows = fetch_issue_dashboard
      phase_cards = fetch_phase_cards

      self.projects = build_projects(roster, progress_result.grouped_data, burndown_issues, issue_rows)
      self.phase_exceptions = build_phase_exceptions(phase_cards)
      self.phase_exceptions_by_customer = group_phase_exceptions_by_customer(phase_exceptions)
      self.last_week_summary = build_last_week_summary(progress_result.grouped_data, phase_cards, issue_rows)
      self.portfolio = build_portfolio(projects, issue_rows, phase_exceptions)
    end

    private

    # ── 子資料源讀取（皆為非核心，個別失敗時降級，不擋整頁）──────────────────

    def fetch_roster
      result = Sheets::FetchProjectRoster.result
      self.roster_unavailable = !result.success?
      roster_unavailable ? [] : result.roster
    end

    def fetch_burndown_issues
      result = Sheets::FetchProjectBurndown.result(status: "all")
      self.burndown_unavailable = !result.success?
      burndown_unavailable ? [] : result.issues
    end

    def fetch_issue_dashboard
      result = Sheets::FetchIssueDashboard.result(status: "")
      self.issues_unavailable = !result.success?
      issues_unavailable ? nil : result
    end

    def fetch_phase_cards
      result = Sheets::FetchPhaseTracking.result
      self.phase_tracking_unavailable = !result.success?
      phase_tracking_unavailable ? [] : result.cards
    end

    # ── 專案識別對照（比照 Sheets::FetchProjectHistory 既有邏輯，獨立實作不共用程式碼）────

    def resolve_roster_row(roster, project_name)
      roster.find { |r| r[:project_name] == project_name } ||
        roster.find { |r| r[:abbreviation].present? && r[:abbreviation] == project_name } ||
        {}
    end

    def matched_burndown_issues(roster_row, project_name, burndown_issues)
      burndown_names_raw = roster_row[:burndown_names_raw].presence
      if burndown_names_raw
        burndown_issues.select { |i| burndown_names_raw.include?(i[:project].to_s) }
      else
        burndown_issues.select { |i| i[:project] == project_name }
      end
    end

    # 306 沒有 burndown_names_raw 那樣的人工對照欄，只比對專案全名／縮寫；比對不到時
    # complaint_count 為 nil（顯示「—」），不影響健康度。
    def matched_project_breakdown(roster_row, project_name, project_breakdown)
      project_breakdown.find { |b| b[:project] == project_name } ||
        (project_breakdown.find { |b| b[:project] == roster_row[:abbreviation] } if roster_row[:abbreviation].present?)
    end

    # ── 每個專案的健康度彙總 ────────────────────────────────────────

    def build_projects(roster, progress_grouped, burndown_issues, issue_dashboard_result)
      project_breakdown = issue_dashboard_result&.project_breakdown || []

      progress_grouped.map do |project_name, tasks|
        roster_row = resolve_roster_row(roster, project_name)
        matched_burndown = matched_burndown_issues(roster_row, project_name, burndown_issues)
        breakdown_row = matched_project_breakdown(roster_row, project_name, project_breakdown)

        overdue_tasks = tasks.select { |t| Sheets::FetchProjectProgress.overdue?(t) }
        due_this_week_tasks = tasks.select { |t| task_due_this_week_not_overdue?(t) }
        completed_count = tasks.count { |t| Sheets::FetchProjectProgress::COMPLETED_STATUSES.include?(t[:status]) }

        active_burndown_issues = matched_burndown.reject { |i| i[:status] == "done" }
        burndown_flag = burndown_flag_for(active_burndown_issues)
        at_risk_burndown_issues = active_burndown_issues.select { |i| [ :at_risk, :over ].include?(burndown_status(i)[:key]) }

        {
          project_name: project_name,
          customer: roster_row[:customer],
          pm: roster_row[:pm],
          health: health_for(overdue_tasks.size, burndown_flag, due_this_week_tasks.size),
          task_completion_percent: task_completion_percent(tasks.size, completed_count),
          overdue_task_count: overdue_tasks.size,
          due_this_week_count: due_this_week_tasks.size,
          overdue_tasks: overdue_tasks.map { |t| { task_name: t[:task_name], owner: t[:owner], delay_days: t[:delay_days] } },
          burndown_flag: burndown_flag,
          at_risk_burndown_issues: at_risk_burndown_issues.map { |i|
            { issue_title: i[:issue_title], assignees: i[:assignees], burndown_label: burndown_status(i)[:label] }
          },
          complaint_count: breakdown_row&.dig(:total)
        }
      end.sort_by { |p| HEALTH_SORT_ORDER.fetch(p[:health]) }
    end

    HEALTH_SORT_ORDER = { critical: 0, at_risk: 1, on_track: 2 }.freeze

    def week_range
      Sheets::FetchProjectProgress.week_range(Date.current)
    end

    def task_due_this_week_not_overdue?(task)
      return false if Sheets::FetchProjectProgress::COMPLETED_STATUSES.include?(task[:status])
      return false if Sheets::FetchProjectProgress.overdue?(task)

      date = Sheets::FetchProjectProgress.parse_date(task[:planned_completion_date])
      date && date <= week_range.last
    end

    # 沒有任何有效議題（例如整批已完成或完全沒對應到 307）時回傳 nil，畫面顯示「—」，
    # 不假裝有燃盡資料可判斷。
    def burndown_flag_for(active_issues)
      return nil if active_issues.empty?

      keys = active_issues.map { |i| burndown_status(i)[:key] }
      return :over if keys.include?(:over)
      return :at_risk if keys.include?(:at_risk)
      return :unknown if keys.all? { |k| k == :unknown }

      :on_track
    end

    # 紅燈：有逾期任務，或燃盡超支。黃燈：本週有任務即將到期（尚未逾期），或燃盡略慢。
    # 綠燈：以上皆無。
    def health_for(overdue_count, burndown_flag, due_this_week_count)
      return :critical if overdue_count.positive? || burndown_flag == :over
      return :at_risk if due_this_week_count.positive? || burndown_flag == :at_risk

      :on_track
    end

    # 305 任務完成率（已完成／總數，非工時比例）：一律以「有沒有 305 任務」為前提可算，
    # 不依賴 307 是否有對應資料，跟 Sheets::FetchProjectHistory 的工時進度％是不同概念。
    def task_completion_percent(total, completed)
      return nil if total.zero?

      ((completed.to_f / total) * 100).round
    end

    # ── 階段追蹤例外（獨立於專案卡片，見類別註解）────────────────────────

    # 只挑「需要注意」的卡片：目前所在階段狀態為延誤未完成／未完成（比照
    # ProjectPhaseTrackingHelper::STATUS_TAG_CLASS 的紅色分類）。「暫緩」是刻意擱置、非緊急，
    # 不算需要 CEO 注意的例外，故不列入（見使用者回饋：暫緩狀態不重要，不需要顯示）；
    # 已完成／延誤已完成的卡片同樣不算例外（已結束，不需要 CEO 再花時間看）。
    NEEDS_ATTENTION_STATUSES = %w[延誤未完成 未完成].freeze

    # 只看最近半年：這份資料源沒有年度篩選就是全部歷史（Sheets::FetchPhaseTracking 的 year
    # 這裡故意不帶，見 fetch_phase_cards），會把陳年舊資料也混進「本週應追蹤項目」；改用
    # 「目前所在階段」的預計日期做滾動 6 個月篩選（而非固定行事曆年度），理由是使用者要的是
    # 「最近」而非「今年」，兩者在年初/年底會有落差（比照使用者回饋：只看最近半年的）。
    # 抓不到日期的卡片視為「無法判斷新舊」，保守起見不顯示（此頁的目的是收斂，不是盡量列出）。
    RECENT_MONTHS = 6

    def build_phase_exceptions(cards)
      cutoff = Date.current - RECENT_MONTHS.months

      cards.filter_map do |card|
        next unless NEEDS_ATTENTION_STATUSES.include?(card[:status])

        current_stage = card[:stages].reverse.find { |s| s[:primary] }
        planned_date = Sheets::FetchProjectProgress.parse_date(current_stage&.dig(:primary, :planned_date))
        next if planned_date.nil? || planned_date < cutoff

        {
          project_code: card[:project],
          issue_label: card[:issue_name].presence || card[:issue_id],
          customer: card[:customer],
          pm: card[:pm],
          stage: current_stage&.dig(:stage),
          status: card[:status]
        }
      end
    end

    # 按客戶彙總階段追蹤例外筆數（決策稽核用途從逐筆表格改成一行一個客戶的計數，避免十幾筆
    # 攤平列出；客戶為空時歸類「未知客戶」，不得直接丟掉不顯示）。
    def group_phase_exceptions_by_customer(phase_exceptions)
      phase_exceptions
        .group_by { |e| e[:customer].presence || "未知客戶" }
        .map { |customer, exceptions| { customer: customer, count: exceptions.size, exceptions: exceptions } }
        .sort_by { |g| -g[:count] }
    end

    # ── 上週總結（純檢視上週已發生的事，不需要任何跨週快照/資料庫——見
    # .kiro/specs/warroom-executive-weekly-summary/design.md「Phase 2」的取捨：CEO 要的是
    # 「上週發生了什麼」而非逐週數字對比，用既有的日期欄位即時篩選即可，不必等 Phase 2 的
    # 資料庫）。307 沒有「實際完成日期」欄位（只有 status，見 Sheets::FetchProjectHistory
    # 附註），無法可靠判斷「上週完成的議題」；306 雖然同樣沒有「解決日期」，但客訴數本來就是
    # 依「通報日期」（daily_kpi 的 date 欄）逐日統計，不需要解決日期也能算出「上週新增幾件
    # 客訴」，故納入上週總結。──────────────────────────────────────────

    def last_week_range
      Sheets::FetchProjectProgress.week_range(Date.current - 7)
    end

    def build_last_week_summary(progress_grouped, phase_cards, issue_dashboard_result)
      range = last_week_range
      completed_tasks = last_week_completed_tasks(progress_grouped, range)
      completed_stages = last_week_completed_stages(phase_cards, range)

      {
        range_start: range.first,
        range_end: range.last,
        completed_task_count: completed_tasks.size,
        completed_tasks: completed_tasks,
        completed_stage_count: completed_stages.size,
        completed_stages: completed_stages,
        complaint_count: last_week_complaint_count(issue_dashboard_result, range)
      }
    end

    # 306 讀取失敗時回傳 nil（畫面顯示「—」），不得顯示 0——0 代表「確認上週零客訴」，
    # 跟「不知道」是完全不同的訊息。
    def last_week_complaint_count(issue_dashboard_result, range)
      return nil if issue_dashboard_result.nil?

      issue_dashboard_result.daily_kpi.sum do |d|
        date = Sheets::FetchProjectProgress.parse_date(d[:date])
        date && range.cover?(date) ? d[:complaint].to_i : 0
      end
    end

    def last_week_completed_tasks(progress_grouped, range)
      progress_grouped.flat_map do |project_name, tasks|
        tasks.select { |t| task_completed_in_range?(t, range) }
          .map { |t| { project_name: project_name, task_name: t[:task_name], owner: t[:owner] } }
      end
    end

    def task_completed_in_range?(task, range)
      return false unless Sheets::FetchProjectProgress::COMPLETED_STATUSES.include?(task[:status])

      date = Sheets::FetchProjectProgress.parse_date(task[:actual_completion_date])
      date && range.cover?(date)
    end

    def last_week_completed_stages(phase_cards, range)
      phase_cards.flat_map do |card|
        card[:stages].filter_map do |stage|
          record = stage[:primary]
          next unless record

          date = Sheets::FetchProjectProgress.parse_date(record[:actual_date])
          next unless date && range.cover?(date)

          { project_code: card[:project], issue_label: card[:issue_name].presence || card[:issue_id],
            stage: stage[:stage], customer: card[:customer] }
        end
      end
    end

    # ── 公司層 KPI ──────────────────────────────────────────────

    def build_portfolio(projects, issue_dashboard_result, phase_exceptions)
      health_counts = projects.group_by { |p| p[:health] }
      selected_month_record = issue_dashboard_result&.selected_month_record

      {
        project_count: projects.size,
        red_count: health_counts[:critical]&.size || 0,
        yellow_count: health_counts[:at_risk]&.size || 0,
        green_count: health_counts[:on_track]&.size || 0,
        overdue_task_total: projects.sum { |p| p[:overdue_task_count] },
        sla_rate: selected_month_record&.dig(:sla_rate),
        month_complaint_count: selected_month_record&.dig(:complaint),
        urgent_complaint_count: issue_dashboard_result&.issue_kpis&.dig(:urgent_complaints),
        phase_pending_count: phase_exceptions.size
      }
    end
  end
end
