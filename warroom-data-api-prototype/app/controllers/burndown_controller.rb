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
    @assignees = all_issues.flat_map { |i| i[:assignees] }.compact.uniq
    @selected_project = params[:project].presence
    @selected_assignee = params[:assignee].presence
    @selected_status = params[:status].presence || "in_progress"

    @filtered_issues = filter_issues(all_issues)

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

  # 專案／人員／狀態篩選同時存在時取交集（AND），僅同時符合三者的議題會出現在議題燃盡圖清單中
  # （需求 4.4）。
  def filter_issues(issues)
    issues
      .select { |i| @selected_project.blank? || i[:project] == @selected_project }
      .select { |i| @selected_assignee.blank? || i[:assignees].include?(@selected_assignee) }
      .select { |i| status_matches?(i) }
  end

  def status_matches?(issue)
    return true if @selected_status == "all"

    in_progress = issue_in_progress?(issue)
    @selected_status == "done" ? !in_progress : in_progress
  end

  # 優先採用試算表「狀態」欄位（Sheets::FetchProjectBurndown 已篩掉無法辨識的髒值，只會是
  # "in_progress"／"done"／nil）；狀態無法辨識（nil）時，退回以 due_date 與今天比較推斷：
  # due_date 晚於今天視為進行中，缺漏或無法解析時無法確認已完成，一律視為進行中（避免資料
  # 不全的議題被誤藏）。
  def issue_in_progress?(issue)
    return issue[:status] == "in_progress" if issue[:status].present?

    due_date = issue[:due_date]
    return true if due_date.blank?

    Date.parse(due_date) > Date.current
  rescue ArgumentError
    true
  end
end
