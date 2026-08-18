# frozen_string_literal: true

module Sheets
  class FetchProjectHistory < ApplicationActor
    input :year, default: nil
    output :overview_rows
    output :overview_years
    output :roster_unavailable
    output :gantt_duration_unavailable
    output :failure_code
    output :message

    def call
      # Roster（客戶/PM 對照）失敗時降級顯示，不擋整頁：305/307 才是本頁面的核心資料，
      # 客戶/PM 只是錦上添花的補充欄位。實務上發現這份試算表常常還沒把 Service Account 加進
      # 共用名單（跟 305/307 是不同試算表、不同擁有者，共用設定各自獨立），若因此讓整頁
      # 連 305/307 都看不到，反而讓一個非核心資料源的權限問題擋住核心功能。找不到對應
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

      # 307 的專案命名跟 305/roster 是兩套完全獨立的體系（見 matched_burndown_issues 附註），
      # 無法靠 Sheets::FetchProjectBurndown 自己的 project 篩選對上，故一律抓全量
      # （project: nil），篩選邏輯自己做。307 失敗時甘特圖降級為全部專案皆無色塊
      # （gantt_duration_unavailable，畫面顯示提示文字），不擋總覽頁（需求 1.3）。
      burndown_overview_result = Sheets::FetchProjectBurndown.result(status: "all")
      duration_data_available = burndown_overview_result.success?
      if duration_data_available
        burndown_issues = burndown_overview_result.issues
        self.gantt_duration_unavailable = false
      else
        burndown_issues = []
        self.gantt_duration_unavailable = true
      end

      # 年度下拉選單的選項固定依「全部」燃盡議題算出（不受目前篩選影響），選單本身不會因為使用者
      # 選了某個年度就少了其他年度可選。
      self.overview_years = burndown_issues.filter_map { |i| i[:start_date].to_s[0, 4].presence }.uniq.sort.reverse

      self.overview_rows =
        build_overview_rows(roster, progress_result.grouped_data, burndown_issues, year, duration_data_available)
    end

    private

    # 兩個子 Actor 中任一失敗即整體失敗，不做部分成功回傳；直接沿用先失敗的那個 Actor 的
    # failure_code/message，不重新包裝（需求 6.1）。
    def propagate_failure(result)
      fail!(failure_code: result.failure_code, message: result.message)
    end

    # 實測發現 305 的專案名稱有時用 Roster 的「專案」全名（如 "Virtuous HRM"），有時用「專案
    # 縮寫」（如 "亞炬 Platform"、"RAG"），沒有固定用哪一欄，故兩欄都查找，任一欄比對到就算
    # （同一個縮寫理論上不會同時是另一個專案的全名，實務資料裡也沒出現這種衝突）。
    def resolve_roster_row(roster, project_name)
      roster.find { |r| r[:project_name] == project_name } ||
        roster.find { |r| r[:abbreviation].present? && r[:abbreviation] == project_name } ||
        {}
    end

    # 以 305 的專案名稱為主體（有進度可看的專案），Roster 找不到對應列時客戶/PM/狀態為 nil，
    # 不視為錯誤（需求 2.1、2.2）。
    #
    # 每列的議題清單（:tasks）一律用該專案對應到的 307 議題（依 year 篩選開案年度，預設今年，
    # 由 controller 決定），同一份清單同時供甘特圖畫時程條、清單頁展開後的議題明細表格使用，
    # 避免兩處各自維護一份轉換邏輯。
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
          has_overdue: tasks.any? { |t| t[:overdue] }
        }
      end
    end

    def filter_issues_by_year(issues, year)
      return issues if year.blank?

      issues.select { |i| i[:start_date].to_s.start_with?(year.to_s) }
    end

    # 307↔Roster 對應規則：Roster 該專案列的 burndown_names_raw 有值時，307 議題的 project 名稱
    # 只要整串出現在該欄文字裡即算對應；為空時退回以 project_name（呼叫端傳入的分組鍵）與 307
    # 議題的 project 精確比對。
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

    def parse_date(date_str)
      return nil if date_str.nil? || date_str.to_s.strip.empty?

      Date.parse(date_str.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
