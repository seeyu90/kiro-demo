class PmWeeklyReportController < ApplicationController
  def index
    result = Summary::BuildPmWeeklyReport.result(project: params[:project].presence)
    if result.success?
      build_success(result)
    else
      build_failure(result.message)
    end
  end

  private

  def build_success(result)
    @week_range = result.week_range
    @next_week_range = result.next_week_range
    @fetched_at = result.fetched_at

    @overdue_tasks = render_tasks(result.overdue_tasks)
    @this_week_due_tasks = render_tasks(result.this_week_due_tasks)
    @this_week_completed_tasks = render_tasks(result.this_week_completed_tasks)
    @next_week_tasks = render_tasks(result.next_week_tasks)
    @undated_tasks = render_tasks(result.undated_tasks)

    @overdue_issues = render_issues(result.overdue_issues)
    @this_week_issues = render_issues(result.this_week_issues)
    @next_week_issues = render_issues(result.next_week_issues)
    @undated_issue_count = result.undated_issue_count

    @phase_items = result.phase_items
    @project_names = result.project_names
    @selected_project = result.selected_project
    @issues_unavailable = result.issues_unavailable
    @phase_tracking_unavailable = result.phase_tracking_unavailable
    @error = nil
  end

  # 核心資料（305）失敗時仍回 200 並在頁面顯示錯誤訊息，不改 HTTP 狀態碼——沿用既有 HTML
  # 頁面的慣例（見 dashboard／executive_summary，以及 spec/requests/executive_summary_spec.rb
  # 對失敗情境同樣期待 200）。rails-standards.md 的 failure_code → HTTP 狀態對應表是給
  # JSON API 用的（見 Api::IssueDashboardController），HTML 頁面不適用。
  def build_failure(message)
    @week_range = nil
    @next_week_range = nil
    @fetched_at = nil
    @overdue_tasks = {}
    @this_week_due_tasks = {}
    @this_week_completed_tasks = {}
    @next_week_tasks = {}
    @undated_tasks = {}
    @overdue_issues = {}
    @this_week_issues = {}
    @next_week_issues = {}
    @undated_issue_count = 0
    @phase_items = []
    @project_names = []
    @selected_project = nil
    @issues_unavailable = false
    @phase_tracking_unavailable = false
    @error = message
  end

  def render_tasks(grouped)
    grouped.transform_values { |tasks| ProjectTaskBlueprint.render_as_hash(tasks) }
  end

  def render_issues(grouped)
    grouped.transform_values { |issues| PmWeeklyIssueBlueprint.render_as_hash(issues) }
  end
end
