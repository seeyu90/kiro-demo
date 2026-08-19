class IssuesController < ApplicationController
  DEFAULT_STATUS = "新建立".freeze
  TABS = %w[stats detail].freeze
  DEFAULT_TAB = "stats".freeze
  BREAKDOWN_SORT_KEYS = Sheets::FetchIssueDashboard::BREAKDOWN_SORT_KEYS
  BREAKDOWN_SORT_DIRS = Sheets::FetchIssueDashboard::BREAKDOWN_SORT_DIRS
  DEFAULT_BREAKDOWN_SORT_DIR = "desc".freeze
  # 「議題資料」分頁的表格分頁大小；分頁純粹是這個 Controller 的呈現方式（對 Actor 回傳的
  # 完整篩選結果做陣列切片），不是 Actor 的職責——KPI 卡片（見 build_success）需要「分頁前」
  # 的完整篩選結果才能算對總數。
  ISSUE_PAGE_SIZE = 15

  def index
    result = Sheets::FetchIssueDashboard.result(
      month: params[:month].presence,
      project: params[:project].presence,
      status: params.key?(:status) ? params[:status] : DEFAULT_STATUS,
      breakdown_sort: BREAKDOWN_SORT_KEYS.include?(params[:breakdown_sort]) ? params[:breakdown_sort] : nil,
      breakdown_dir: BREAKDOWN_SORT_DIRS.include?(params[:breakdown_dir]) ? params[:breakdown_dir] : DEFAULT_BREAKDOWN_SORT_DIR,
      q: params[:q].presence,
      type: params[:type].presence
    )
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
    @available_months = result.available_months
    @selected_month = result.selected_month
    @selected_month_record = result.selected_month_record
    @selected_month_pending = result.selected_month_pending
    @daily_kpi = DailyKpiBlueprint.render_as_hash(result.daily_kpi_for_month)

    @breakdown_sort = BREAKDOWN_SORT_KEYS.include?(params[:breakdown_sort]) ? params[:breakdown_sort] : nil
    @breakdown_dir =
      BREAKDOWN_SORT_DIRS.include?(params[:breakdown_dir]) ? params[:breakdown_dir] : DEFAULT_BREAKDOWN_SORT_DIR
    @project_breakdown = ProjectBreakdownBlueprint.render_as_hash(result.month_project_breakdown)

    @projects = result.projects
    @statuses = result.statuses
    @selected_project = params[:project].presence
    @selected_status = params.key?(:status) ? params[:status] : DEFAULT_STATUS
    @selected_q = params[:q].presence
    @selected_type = params[:type].presence
    @issue_kpis = result.issue_kpis

    all_issues = IssueBlueprint.render_as_hash(result.filtered_issues)
    @total_issue_count = all_issues.size
    @total_pages = [ (@total_issue_count.to_f / ISSUE_PAGE_SIZE).ceil, 1 ].max
    @page = params[:page].to_i.clamp(1, @total_pages)
    @issues = all_issues.each_slice(ISSUE_PAGE_SIZE).to_a[@page - 1] || []
    @error = nil
  end

  def build_failure(message)
    @active_tab = DEFAULT_TAB
    @month_kpi = []
    @daily_kpi = []
    @project_breakdown = []
    @breakdown_sort = nil
    @breakdown_dir = DEFAULT_BREAKDOWN_SORT_DIR
    @available_months = []
    @selected_month = nil
    @selected_month_record = nil
    @selected_month_pending = false
    @projects = []
    @statuses = []
    @selected_project = nil
    @selected_status = DEFAULT_STATUS
    @selected_q = nil
    @selected_type = nil
    @issue_kpis = { pending: 0, urgent_complaints: 0, overdue_or_undated: 0 }
    @total_issue_count = 0
    @total_pages = 1
    @page = 1
    @issues = []
    @error = message
  end
end
