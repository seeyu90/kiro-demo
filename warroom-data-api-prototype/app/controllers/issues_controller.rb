class IssuesController < ApplicationController
  include DateRangeFilterable

  DEFAULT_STATUS = "新建立".freeze
  TABS = %w[stats detail].freeze
  DEFAULT_TAB = "stats".freeze
  BREAKDOWN_SORT_KEYS = Sheets::FetchIssueDashboard::BREAKDOWN_SORT_KEYS
  BREAKDOWN_SORT_DIRS = Sheets::FetchIssueDashboard::BREAKDOWN_SORT_DIRS
  DEFAULT_BREAKDOWN_SORT_DIR = "desc".freeze
  # 「議題資料」分頁的表格分頁大小；分頁本身交給 Pagy 處理（見 build_success 的 pagy 呼叫），
  # Controller 只需要提供 limit。KPI 卡片（見 build_success）讀 result.issue_kpis，是 Actor
  # 依「分頁前」的完整篩選結果算好的，不受這裡的分頁影響。
  ISSUE_PAGE_SIZE = 15

  def index
    from, to = resolve_date_range
    result = Sheets::FetchIssueDashboard.result(
      from: from,
      to: to,
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
    @selected_from = result.selected_from
    @selected_to = result.selected_to
    @matched_month_count = result.settled_month_count
    @selected_month_record = result.selected_month_record
    @selected_month_pending = result.selected_month_pending
    @daily_kpi = DailyKpiBlueprint.render_as_hash(result.daily_kpi_for_range)

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

    # 分頁交給 Pagy 處理（Countable 直接支援 Array，不需要額外的 gem extra）：先對 Actor 回傳
    # 的原始 hash 陣列切出當頁範圍，再只對這一頁呼叫 Blueprint，避免把整批篩選結果都序列化一次
    # 卻只用其中 15 筆。
    @pagy, page_issues = pagy(:offset, result.filtered_issues, limit: ISSUE_PAGE_SIZE)
    @issues = IssueBlueprint.render_as_hash(page_issues)
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
    @selected_from = nil
    @selected_to = nil
    @matched_month_count = 0
    @selected_month_record = nil
    @selected_month_pending = false
    @projects = []
    @statuses = []
    @selected_project = nil
    @selected_status = DEFAULT_STATUS
    @selected_q = nil
    @selected_type = nil
    @issue_kpis = { pending: 0, urgent_complaints: 0, overdue_or_undated: 0, total_hours_sum: 0 }
    @pagy = nil
    @issues = []
    @error = message
  end
end
