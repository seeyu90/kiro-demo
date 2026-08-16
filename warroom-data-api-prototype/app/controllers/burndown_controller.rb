class BurndownController < ApplicationController
  def index
    result = Sheets::FetchProjectBurndown.result(
      project: params[:project].presence,
      assignee: params[:assignee].presence,
      status: params[:status].presence || "in_progress"
    )
    if result.success?
      build_success(result)
    else
      build_failure(result.message)
    end
  end

  private

  def build_success(result)
    @projects = result.projects
    @assignees = result.assignees
    @selected_project = params[:project].presence
    @selected_assignee = params[:assignee].presence
    @selected_status = params[:status].presence || "in_progress"
    @filtered_issues = BurndownIssueBlueprint.render_as_hash(result.issues)
    @error = nil
  end

  def build_failure(message)
    @projects = []
    @assignees = []
    @selected_project = nil
    @selected_assignee = nil
    @selected_status = "in_progress"
    @filtered_issues = []
    @error = message
  end
end
