class DashboardController < ApplicationController
  include DateRangeFilterable

  SCOPES = Sheets::FetchProjectProgress::SCOPES
  PRIORITY_TYPES = Sheets::FetchProjectProgress::PRIORITY_TYPES

  helper_method :overdue?

  def index
    from, to = resolve_date_range
    result = Sheets::FetchProjectProgress.result(
      force: params[:refresh].present?,
      project: params[:project].presence,
      task_types: params.key?(:task_type) ? Array(params[:task_type]).reject(&:blank?) : nil,
      scope: SCOPES.include?(params[:scope]) ? params[:scope] : "due_this_week",
      incomplete_only: params[:incomplete_only] != "0",
      planned_from: from,
      planned_to: to
    )
    if result.success?
      build_success(result, from, to)
    else
      build_failure(result.message)
    end
  end

  private

  def build_success(result, from, to)
    @freshness_label  = freshness_label(result.fetched_at)
    @grouped_data     = result.grouped_data
    @project_names    = result.project_names
    @selected_project = params[:project].presence
    @task_types       = result.task_types_available
    @selected_types   = params.key?(:task_type) ? Array(params[:task_type]).reject(&:blank?) : PRIORITY_TYPES.dup
    @scope            = SCOPES.include?(params[:scope]) ? params[:scope] : "due_this_week"
    @incomplete_only  = params[:incomplete_only] != "0"
    @selected_from    = from
    @selected_to      = to
    @summary          = result.summary
    @display_data     = result.display_data.transform_values { |tasks| ProjectTaskBlueprint.render_as_hash(tasks) }
    @error            = nil
  end

  # 純委派給 Actor 的判斷邏輯（見 Sheets::FetchProjectProgress.overdue?），供 View
  # 顯示「逾期」標籤用，本身不含任何轉換邏輯。
  def overdue?(task)
    Sheets::FetchProjectProgress.overdue?(task)
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
    @selected_from    = nil
    @selected_to      = nil
    @summary          = { total: 0, completed: 0, incomplete: 0, overdue: 0 }
    @display_data     = {}
    @error            = message
  end

  # fetched_at 為 nil 代表快取層尚未成功寫入過（理論上不會發生於成功結果，防禦性處理）。
  # 剛從 Google Sheets API 取得（快取未命中）時 elapsed 趨近 0，一律顯示「剛剛更新」；
  # 否則以快取寫入時間換算成「X 分鐘前」，讓使用者知道畫面資料的時效。
  FRESH_THRESHOLD = 10.seconds

  def freshness_label(fetched_at)
    return nil if fetched_at.nil?

    elapsed = Time.current - fetched_at
    return "資料剛剛更新" if elapsed < FRESH_THRESHOLD

    minutes = (elapsed / 60).floor
    minutes.zero? ? "資料剛剛更新" : "資料更新於 #{minutes} 分鐘前"
  end
end
