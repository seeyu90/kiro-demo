class DashboardController < ApplicationController
  include DateRangeFilterable

  SCOPES = Sheets::FetchProjectProgress::SCOPES
  DEFAULT_TASK_TYPES = Sheets::FetchProjectProgress::DEFAULT_TASK_TYPES

  helper_method :overdue?

  def index
    from, to = resolve_date_range
    result = Sheets::FetchProjectProgress.result(
      project: params[:project].presence,
      task_types: params.key?(:task_type) ? Array(params[:task_type]).reject(&:blank?) : nil,
      scope: SCOPES.include?(params[:scope]) ? params[:scope] : "due_this_week",
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
    @grouped_data     = result.grouped_data
    @project_names    = result.project_names
    @selected_project = params[:project].presence
    @task_types       = result.task_types_available
    @selected_types   = params.key?(:task_type) ? Array(params[:task_type]).reject(&:blank?) : DEFAULT_TASK_TYPES.dup
    @scope            = SCOPES.include?(params[:scope]) ? params[:scope] : "due_this_week"
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
    @grouped_data     = {}
    @project_names    = []
    @selected_project = nil
    @task_types       = []
    @selected_types   = DEFAULT_TASK_TYPES
    @scope            = "due_this_week"
    @selected_from    = nil
    @selected_to      = nil
    @summary          = { total: 0, completed: 0, incomplete: 0, overdue: 0 }
    @display_data     = {}
    @error            = message
  end
end
