class BurndownController < ApplicationController
  include DateRangeFilterable

  def index
    from, to = resolve_date_range
    result = Sheets::FetchProjectBurndown.result(
      project: params[:project].presence,
      assignee: params[:assignee].presence,
      status: params[:status].presence || "in_progress",
      from: from,
      to: to
    )
    if result.success?
      build_success(result, from, to)
    else
      build_failure(result.message)
    end
  end

  private

  def build_success(result, from, to)
    @projects = result.projects
    @assignees = result.assignees
    @selected_project = params[:project].presence
    @selected_assignee = params[:assignee].presence
    @selected_status = params[:status].presence || "in_progress"
    @selected_from = from
    @selected_to = to
    @filtered_issues = BurndownIssueBlueprint.render_as_hash(result.issues)
    @error = nil
  end

  def build_failure(message)
    @projects = []
    @assignees = []
    @selected_project = nil
    @selected_assignee = nil
    @selected_status = "in_progress"
    @selected_from = nil
    @selected_to = nil
    @filtered_issues = []
    @error = message
  end
end
