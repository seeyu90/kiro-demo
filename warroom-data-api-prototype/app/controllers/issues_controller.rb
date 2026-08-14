class IssuesController < ApplicationController
  DEFAULT_STATUS = "新建立".freeze
  TABS = %w[stats detail].freeze
  DEFAULT_TAB = "stats".freeze

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
    # 「統計摘要」（月度 KPI＋每日趨勢）與「議題資料」（依專案分類＋議題明細）各自獨立的表單，
    # 各自帶一個隱藏欄位 tab= 標明來源，送出後仍停留在原本的分頁，而非固定跳回第一個分頁。
    @active_tab = TABS.include?(params[:tab]) ? params[:tab] : DEFAULT_TAB

    @month_kpi = MonthKpiBlueprint.render_as_hash(result.month_kpi)
    @daily_kpi = DailyKpiBlueprint.render_as_hash(result.daily_kpi)
    @project_breakdown = ProjectBreakdownBlueprint.render_as_hash(result.project_breakdown)

    # 月份選單納入進行中的當月（即使 month_kpi 尚無該月列，因為月結數字要等月底才產生），
    # 但預設選中仍是最新「已結算」月份，確保頁面載入時直接看到有意義的月結數字。
    current_year_month = Date.current.strftime("%Y-%m")
    @available_months = (@month_kpi.map { |m| m[:year_month] } + [current_year_month]).uniq.sort
    @selected_month = params[:month].presence || @month_kpi.map { |m| m[:year_month] }.max
    @selected_month_record = @month_kpi.find { |m| m[:year_month] == @selected_month }
    @selected_month_pending = @selected_month_record.nil? && @selected_month == current_year_month

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
    @active_tab = DEFAULT_TAB
    @month_kpi = []
    @daily_kpi = []
    @project_breakdown = []
    @available_months = []
    @selected_month = nil
    @selected_month_record = nil
    @selected_month_pending = false
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
