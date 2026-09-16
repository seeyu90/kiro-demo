# frozen_string_literal: true

module Summary
  # PM 週報（/pm_weekly_report）：把 305 任務、306 議題、階段追蹤依「本週／下週」歸屬，
  # 供 PM 每週五撰寫週報時直接參照四個區塊（逾期未完成／本週工作／下週工作／階段追蹤）。
  #
  # 與 Summary::BuildExecutiveSummary 的分工：那支做的是 CEO 的例外管理（只浮出紅黃燈專案、
  # 不列正常工作），本 Actor 做的是工作明細（含本週正常完成的項目），受眾與輸出形狀都不同，
  # 故獨立一支；但「議題是否結案／是否逾期／到期日是哪一天」的判斷共用同一組 class method
  # （`Sheets::FetchIssueDashboard.done?`／`.overdue?`／`.effective_due_date`），不各自實作。
  #
  # 階段追蹤刻意不併入 305／306 的專案分組：階段追蹤用的是第三套專案代碼命名系統
  # （Notion/Github 代碼，如 HRM、JZNPMS），目前沒有任何欄位能可靠對照回 305 的專案名稱，
  # 猜錯的對照比不對照更危險（同 Summary::BuildExecutiveSummary 既有取捨）。
  class BuildPmWeeklyReport < ApplicationActor
    input :project, default: nil

    output :week_range
    output :next_week_range
    output :fetched_at
    output :overdue_tasks
    output :this_week_due_tasks
    output :this_week_completed_tasks
    output :next_week_tasks
    output :undated_tasks
    output :overdue_issues
    output :this_week_issues
    output :next_week_issues
    output :undated_issue_count
    output :phase_items
    output :project_names
    output :selected_project
    output :issues_unavailable
    output :phase_tracking_unavailable
    output :failure_code
    output :message

    # 階段追蹤只列「還沒結束」的狀態；「完成」「延誤已完成」已結束，不是本週要處理的工作。
    PHASE_EXCEPTION_STATUSES = [ "延誤未完成", "未完成", "暫緩" ].freeze

    PHASE_BUCKET_ORDER = { overdue: 0, this_week: 1, next_week: 2 }.freeze

    def call
      # 305 是本頁核心資料（同 Summary::BuildExecutiveSummary 的取捨）：沒有 305 就沒有
      # 「這週有哪些工作」的主體，讀取失敗即整頁失敗，不做部分渲染。
      progress = Sheets::FetchProjectProgress.result(scope: "all", incomplete_only: false)
      return fail!(failure_code: progress.failure_code, message: progress.message) unless progress.success?

      self.week_range = Sheets::FetchProjectProgress.week_range(Date.current)
      self.next_week_range = Sheets::FetchProjectProgress.week_range(Date.current + 7)
      self.fetched_at = progress.fetched_at
      self.project_names = progress.project_names.compact.sort
      self.selected_project = project.presence

      classify_tasks(progress.grouped_data)
      classify_issues(fetch_issues)
      self.phase_items = build_phase_items(fetch_phase_cards)
    end

    private

    # ── 子資料源讀取（皆為非核心，個別失敗時降級，不擋整頁）──────────────────

    def fetch_issues
      result = Sheets::FetchIssueDashboard.result(status: "")
      self.issues_unavailable = !result.success?
      issues_unavailable ? [] : result.issues
    end

    def fetch_phase_cards
      result = Sheets::FetchPhaseTracking.result
      self.phase_tracking_unavailable = !result.success?
      phase_tracking_unavailable ? [] : result.cards
    end

    # ── 305 任務的週別歸屬 ────────────────────────────────────────

    # 每筆任務只會落在一個清單（需求 2.6）：已完成的先分流，未完成的才依逾期 → 本週 →
    # 下週 → 未定判斷。逾期優先於本週，所以「本週一到期、週五還沒完成」只出現在逾期清單，
    # 不會在本週待完成裡重複出現一次。
    def classify_tasks(grouped_data)
      buckets = Hash.new { |hash, key| hash[key] = [] }

      grouped_data.each do |project_name, tasks|
        next unless project_selected?(project_name)

        tasks.each do |task|
          bucket = task_bucket(task)
          buckets[bucket] << task if bucket
        end
      end

      # 逾期清單「逾期天數由多到少」與其餘清單「預計完成日由近到遠」其實是同一個排序鍵
      # （預計完成日由早到晚），不需要兩套排序。
      self.overdue_tasks = group_items(buckets[:overdue], :project_name) { |t| task_sort_key(t) }
      self.this_week_due_tasks = group_items(buckets[:this_week_due], :project_name) { |t| task_sort_key(t) }
      self.next_week_tasks = group_items(buckets[:next_week], :project_name) { |t| task_sort_key(t) }
      self.undated_tasks = group_items(buckets[:undated], :project_name) { |t| task_sort_key(t) }
      # 本週已完成依「實際完成日」排序（週內時序），不是預計完成日——PM 寫週報是照著
      # 「這週哪天做完了什麼」交代的。
      self.this_week_completed_tasks = group_items(buckets[:this_week_completed], :project_name) do |task|
        [ parse_date(task[:actual_completion_date]) || Date.new(0), task[:task_name].to_s ]
      end
    end

    def task_bucket(task)
      if Sheets::FetchProjectProgress::COMPLETED_STATUSES.include?(task[:status])
        return completed_in_week?(task, week_range) ? :this_week_completed : nil
      end

      return :overdue if Sheets::FetchProjectProgress.overdue?(task)

      date = parse_date(task[:planned_completion_date])
      return :undated if date.nil?
      return :this_week_due if week_range.cover?(date)
      return :next_week if next_week_range.cover?(date)

      # 更晚才到期的任務不屬於本次週報的範圍。
      nil
    end

    def completed_in_week?(task, range)
      date = parse_date(task[:actual_completion_date])
      date.present? && range.cover?(date)
    end

    # 預計完成日缺漏或無法解析者排在最後（同一清單內的相對順序再依任務名稱），不讓
    # nil 參與日期比較而炸掉排序。
    def task_sort_key(task)
      [ parse_date(task[:planned_completion_date]) || Date.new(9999), task[:task_name].to_s ]
    end

    # ── 306 議題的週別歸屬 ────────────────────────────────────────

    def classify_issues(issues)
      buckets = Hash.new { |hash, key| hash[key] = [] }
      undated = 0

      issues.each do |issue|
        next if Sheets::FetchIssueDashboard.done?(issue)
        next unless project_selected?(issue[:project])

        date, source = Sheets::FetchIssueDashboard.effective_due_date(issue)
        # 既無到期日也無適用 SLA 的議題不列入任何週別（沿用 306 既有「未定到期日不算逾期」
        # 的取捨），但仍要讓 PM 知道有幾筆沒排期（需求 3.6）。
        if date.nil?
          undated += 1
          next
        end

        bucket = issue_bucket(date)
        next if bucket.nil?

        buckets[bucket] << issue.merge(effective_due_date: date, due_date_estimated: source == :sla)
      end

      self.undated_issue_count = undated
      self.overdue_issues = group_items(buckets[:overdue], :project) { |i| issue_sort_key(i) }
      self.this_week_issues = group_items(buckets[:this_week], :project) { |i| issue_sort_key(i) }
      self.next_week_issues = group_items(buckets[:next_week], :project) { |i| issue_sort_key(i) }
    end

    def issue_bucket(date)
      return :overdue if date < Date.current
      return :this_week if week_range.cover?(date)
      return :next_week if next_week_range.cover?(date)

      nil
    end

    def issue_sort_key(issue)
      [ issue[:effective_due_date], issue[:subject].to_s ]
    end

    # ── 階段追蹤（獨立區塊，不併入專案分組、不受專案篩選影響）─────────────────

    def build_phase_items(cards)
      cards.filter_map do |card|
        next unless PHASE_EXCEPTION_STATUSES.include?(card[:status])

        stage = current_stage(card)
        next if stage.nil?

        date = parse_date(stage[:primary][:planned_date])
        bucket = date.nil? ? nil : issue_bucket(date)
        next if bucket.nil?

        {
          project: card[:project],
          issue_id: card[:issue_id],
          issue_name: card[:issue_name],
          customer: card[:customer],
          pm: card[:pm],
          stage: stage[:stage],
          status: card[:status],
          # 存解析後的 Date 而不是試算表原始字串：階段追蹤的日期欄沒有正規化
          # （見 Sheets::FetchPhaseTracking#parse_records），同一個 bucket 裡混到
          # 「2026-09-15」與「2026/9/1」時，字串比較會在第 5 個字元比到 '-' < '/'
          # 而把 9/15 排到 9/1 前面。這裡日期必定解析得出來（解析不出來的上面已跳過）。
          planned_date: date,
          reason: stage[:primary][:reason],
          bucket: bucket
        }
      end.sort_by { |item| [ PHASE_BUCKET_ORDER.fetch(item[:bucket]), item[:planned_date], item[:issue_id].to_s ] }
    end

    # 「目前階段」＝ STAGE_ORDER 由後往前第一個有主要紀錄的階段，與
    # Sheets::FetchPhaseTracking#current_issue_status 同一個定義，不另外發明一套。
    def current_stage(card)
      card[:stages].reverse.find { |stage| stage[:primary] }
    end

    # ── 共用小工具 ──────────────────────────────────────────────

    # 306 的 project 欄位與 305 的專案名稱不保證是同一套寫法，故採雙向包含比對；兩邊完全
    # 對不起來的 306 議題在套用專案篩選時不顯示（寧可少顯示，也不要把別的專案的客訴算進來）。
    def project_selected?(name)
      return true if selected_project.blank?

      value = name.to_s
      return false if value.blank?

      value == selected_project || value.include?(selected_project) || selected_project.include?(value)
    end

    def group_items(items, key, &sort_key)
      items.sort_by(&sort_key)
        .group_by { |item| item[key].presence || "未分類" }
        .sort
        .to_h
    end

    def parse_date(value)
      Sheets::FetchProjectProgress.parse_date(value)
    end
  end
end
