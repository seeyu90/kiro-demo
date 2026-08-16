# frozen_string_literal: true

module Sheets
  class FetchProjectHistory < ApplicationActor
    input :project, default: nil
    output :overview_rows
    output :detail
    output :failure_code
    output :message

    RESOLVED_STATUSES = %w[已結束 已解決].freeze

    def call
      roster_result = Sheets::FetchProjectRoster.result
      return propagate_failure(roster_result) unless roster_result.success?

      progress_result = Sheets::FetchProjectProgress.result(scope: "all", incomplete_only: false)
      return propagate_failure(progress_result) unless progress_result.success?

      issue_result = Sheets::FetchIssueDashboard.result
      return propagate_failure(issue_result) unless issue_result.success?

      burndown_result = Sheets::FetchProjectBurndown.result(project: project, status: "all")
      return propagate_failure(burndown_result) unless burndown_result.success?

      # overview_rows 一律計算（詳情頁的專案下拉選單需要完整專案清單），detail 僅在帶
      # project 參數時額外計算。
      self.overview_rows = build_overview_rows(roster_result.roster, progress_result.grouped_data)
      self.detail = build_detail(project, burndown_result.issues, issue_result.issues) if project.present?
    end

    private

    # 四個子 Actor 中任一失敗即整體失敗，不做部分成功回傳；直接沿用先失敗的那個 Actor 的
    # failure_code/message，不重新包裝（需求 6.1）。
    def propagate_failure(result)
      fail!(failure_code: result.failure_code, message: result.message)
    end

    # ── 橫向總覽 ──────────────────────────────────────────────

    # 以 305 的專案名稱為主體（有進度可看的專案），Roster 找不到對應列時客戶/PM/狀態為 nil，
    # 不視為錯誤（需求 2.1、2.2）。
    def build_overview_rows(roster, progress_grouped)
      roster_by_name = roster.index_by { |r| r[:project_name] }

      progress_grouped.map do |project_name, tasks|
        roster_row = roster_by_name[project_name] || {}
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

    def build_detail(project, burndown_issues, all_issues)
      project_issues = all_issues.select { |i| i[:project] == project }

      {
        work_hours_series: aggregate_work_hours(burndown_issues),
        ideal_series: aggregate_ideal_series(burndown_issues),
        actual_series: aggregate_actual_series(burndown_issues),
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
