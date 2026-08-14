class DashboardController < ApplicationController
  PRIORITY_TYPES = ["功能", "PR"].freeze
  SCOPES = %w[all due_this_week overdue].freeze
  # 真實試算表的「狀態」欄位是自由輸入的中文文字，非固定英文 enum；實際觀察到的值只有
  # 「完成」「已確認」「未完成」三種，其中「完成」與「已確認」皆代表任務已結束（「已確認」
  # 的紀錄一律已有實際完成日期），故兩者皆視為完成狀態；沒有「進行中」「待開始」的細分。
  COMPLETED_STATUSES = ["完成", "已確認"].freeze
  UNFINISHED_STATUS = "未完成".freeze
  FRESH_THRESHOLD = 10.seconds

  helper_method :overdue?

  def index
    result = Sheets::FetchProjectProgress.result(force: params[:refresh] == "1")
    if result.success?
      build_success(result.grouped_data, result.fetched_at)
    else
      build_failure(result.message)
    end
  end

  private

  def build_success(grouped_data, fetched_at)
    @freshness_label   = freshness_label(fetched_at)
    @grouped_data      = grouped_data
    @project_names     = grouped_data.keys
    @selected_project  = params[:project].presence
    @task_types        = sorted_task_types(grouped_data.values.flatten)
    @selected_types    = selected_task_types
    @scope             = SCOPES.include?(params[:scope]) ? params[:scope] : "due_this_week"
    @incomplete_only   = params[:incomplete_only] != "0"
    @today             = Date.current
    @week_range        = week_range(@today)

    all_tasks     = grouped_data.values.flatten
    scoped_tasks  = all_tasks.select { |t| matches_project_and_type?(t) }
    @summary      = compute_summary(scoped_tasks)

    display_project_names = @selected_project ? [@selected_project] : @project_names
    filtered = filter_tasks(all_tasks)
    grouped_filtered = filtered.group_by { |t| t[:project_name] }

    @display_data = display_project_names.index_with do |name|
      tasks = sort_overdue_first(grouped_filtered[name] || [])
      ProjectTaskBlueprint.render_as_hash(tasks)
    end
    @error = nil
  end

  def build_failure(message)
    @freshness_label  = nil
    @grouped_data     = {}
    @project_names    = []
    @selected_project = nil
    @task_types       = []
    @selected_types   = PRIORITY_TYPES
    @scope            = "due_this_week"
    @incomplete_only  = true
    @summary          = { total: 0, completed: 0, incomplete: 0, overdue: 0 }
    @display_data     = {}
    @error            = message
  end

  def selected_task_types
    raw = params[:task_type]
    return PRIORITY_TYPES.dup if raw.nil?

    Array(raw).reject(&:blank?)
  end

  def sorted_task_types(tasks)
    types = tasks.map { |t| t[:task_type] }.compact.uniq
    types.sort_by { |t| PRIORITY_TYPES.index(t) || PRIORITY_TYPES.length }
  end

  def matches_project_and_type?(task)
    return false if @selected_project && task[:project_name] != @selected_project
    return false if @selected_types.any? && !@selected_types.include?(task[:task_type])

    true
  end

  def filter_tasks(tasks)
    tasks.select do |t|
      next false unless matches_project_and_type?(t)
      next false if @incomplete_only && COMPLETED_STATUSES.include?(t[:status])
      next false if @scope == "overdue" && !overdue?(t)
      next false if @scope == "due_this_week" && !due_by_this_week_end?(t)

      true
    end
  end

  def overdue?(task)
    return false if COMPLETED_STATUSES.include?(task[:status])

    date = parse_date(task[:planned_completion_date])
    date && date < @today
  end

  # 本週到期＝不晚於本週週日，不限下界，涵蓋所有已逾期任務（不論逾期發生於本週內或更早）。
  def due_by_this_week_end?(task)
    return false if COMPLETED_STATUSES.include?(task[:status])

    date = parse_date(task[:planned_completion_date])
    date && date <= @week_range.last
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def week_range(date)
    monday = date - (date.wday.zero? ? 6 : date.wday - 1)
    (monday..(monday + 6))
  end

  def compute_summary(tasks)
    completed = tasks.count { |t| COMPLETED_STATUSES.include?(t[:status]) }
    {
      total: tasks.size,
      completed: completed,
      incomplete: tasks.size - completed,
      overdue: tasks.count { |t| overdue?(t) }
    }
  end

  def sort_overdue_first(tasks)
    tasks.sort_by { |t| overdue?(t) ? 0 : 1 }
  end

  # fetched_at 為 nil 代表快取層尚未成功寫入過（理論上不會發生於成功結果，防禦性處理）。
  # 剛從 Google Sheets API 取得（快取未命中）時 elapsed 趨近 0，一律顯示「剛剛更新」；
  # 否則以快取寫入時間換算成「X 分鐘前」，讓使用者知道畫面資料的時效。
  def freshness_label(fetched_at)
    return nil if fetched_at.nil?

    elapsed = Time.current - fetched_at
    return "資料剛剛更新" if elapsed < FRESH_THRESHOLD

    minutes = (elapsed / 60).floor
    minutes.zero? ? "資料剛剛更新" : "資料更新於 #{minutes} 分鐘前"
  end
end
