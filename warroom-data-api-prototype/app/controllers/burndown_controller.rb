class BurndownController < ApplicationController
  def index
    result = Sheets::FetchProjectBurndown.result
    if result.success?
      build_success(result)
    else
      build_failure(result.message)
    end
  end

  private

  def build_success(result)
    all_issues = BurndownIssueBlueprint.render_as_hash(result.issues)

    @projects = all_issues.map { |i| i[:project] }.compact.uniq
    @assignees = all_issues.map { |i| i[:assignee] }.compact.uniq
    @selected_project = params[:project].presence
    @selected_assignee = params[:assignee].presence

    @filtered_issues = filter_issues(all_issues)

    # 專案彙總圖僅受專案篩選影響，不受人員篩選影響（需求 4.3）；未選專案時顯示全部專案的彙總圖。
    @project_series =
      if @selected_project
        result.project_series.slice(@selected_project)
      else
        result.project_series
      end

    @error = nil
  end

  def build_failure(message)
    @projects = []
    @assignees = []
    @selected_project = nil
    @selected_assignee = nil
    @filtered_issues = []
    @project_series = {}
    @error = message
  end

  # 專案與人員篩選同時存在時取交集（AND），僅同時符合兩者的議題會出現在議題燃盡圖清單中
  # （需求 4.4）。
  def filter_issues(issues)
    issues
      .select { |i| @selected_project.blank? || i[:project] == @selected_project }
      .select { |i| @selected_assignee.blank? || i[:assignee] == @selected_assignee }
  end
end
