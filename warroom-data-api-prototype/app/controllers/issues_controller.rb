class IssuesController < ApplicationController
  DEFAULT_STATUS = "新建立".freeze

  def index
    result = Sheets::FetchIssueDashboard.result
    if result.success?
      build_success(result)
    else
      build_failure(result.message)
    end
  end

  private

  def build_success(result)
    @month_kpi = MonthKpiBlueprint.render_as_hash(result.month_kpi)
    @daily_kpi = DailyKpiBlueprint.render_as_hash(result.daily_kpi)
    @project_breakdown = ProjectBreakdownBlueprint.render_as_hash(result.project_breakdown)

    @selected_month = params[:month].presence || @month_kpi.map { |m| m[:year_month] }.max
    @selected_month_record = @month_kpi.find { |m| m[:year_month] == @selected_month }

    all_issues = IssueBlueprint.render_as_hash(result.issues)
    @projects = all_issues.map { |i| i[:project] }.compact.uniq
    @statuses = all_issues.map { |i| i[:status] }.compact.uniq
    @selected_project = params[:project].presence
    # 未帶 status 參數（首次載入）時預設「新建立」；使用者主動清空（status= 空字串）則視為不篩選。
    @selected_status = params.key?(:status) ? params[:status] : DEFAULT_STATUS

    @issues = filter_issues(all_issues)
    @error = nil
  end

  def build_failure(message)
    @month_kpi = []
    @daily_kpi = []
    @project_breakdown = []
    @selected_month = nil
    @selected_month_record = nil
    @projects = []
    @statuses = []
    @selected_project = nil
    @selected_status = DEFAULT_STATUS
    @issues = []
    @error = message
  end

  def filter_issues(issues)
    issues
      .select { |i| @selected_project.blank? || i[:project] == @selected_project }
      .select { |i| @selected_status.blank? || i[:status] == @selected_status }
  end
end
