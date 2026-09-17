class IssuesController < ApplicationController
  include DateRangeFilterable

  DEFAULT_STATUSES = Sheets::FetchIssueDashboard::DEFAULT_STATUSES
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
      # 狀態／類型改成多選（比照 305 的 task_type[] 慣例）：params.key? 判斷「這次請求有沒有
      # 帶這個 query param」，沒帶（使用者還沒送出過篩選表單）傳 nil 讓 Actor 套預設值；有帶
      # （即使全部取消勾選、值是空陣列）就照實傳陣列，交給 Actor 判斷是否要套用預設值。
      status: params.key?(:status) ? Array(params[:status]).reject(&:blank?) : nil,
      breakdown_sort: BREAKDOWN_SORT_KEYS.include?(params[:breakdown_sort]) ? params[:breakdown_sort] : nil,
      breakdown_dir: BREAKDOWN_SORT_DIRS.include?(params[:breakdown_dir]) ? params[:breakdown_dir] : DEFAULT_BREAKDOWN_SORT_DIR,
      q: params[:q].presence,
      type: params.key?(:type) ? Array(params[:type]).reject(&:blank?) : nil
    )
    if result.success?
      build_success(result)
    else
      build_failure(result.message)
    end
  end

  private

  def build_success(result)
    # 「統計摘要」（議題 KPI＋每日趨勢）與「議題資料」（依專案分類＋議題明細）各自獨立的表單，
    # 各自帶一個隱藏欄位 tab= 標明來源，送出後仍停留在原本的分頁，而非固定跳回第一個分頁。
    @active_tab = TABS.include?(params[:tab]) ? params[:tab] : DEFAULT_TAB

    @month_kpi = MonthKpiBlueprint.render_as_hash(result.month_kpi)
    @available_months = result.available_months
    @selected_from = result.selected_from
    @selected_to = result.selected_to
    @selected_month_record = result.selected_month_record
    @daily_kpi = DailyKpiBlueprint.render_as_hash(result.daily_kpi_for_range)

    @breakdown_sort = BREAKDOWN_SORT_KEYS.include?(params[:breakdown_sort]) ? params[:breakdown_sort] : nil
    @breakdown_dir =
      BREAKDOWN_SORT_DIRS.include?(params[:breakdown_dir]) ? params[:breakdown_dir] : DEFAULT_BREAKDOWN_SORT_DIR
    @project_breakdown = ProjectBreakdownBlueprint.render_as_hash(result.month_project_breakdown)

    @projects = result.projects
    @statuses = result.statuses
    @types = result.types
    @selected_project = params[:project].presence
    @selected_status = params.key?(:status) ? Array(params[:status]).reject(&:blank?) : DEFAULT_STATUSES.dup
    @selected_q = params[:q].presence
    @selected_type = params.key?(:type) ? Array(params[:type]).reject(&:blank?) : []
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
    @selected_month_record = nil
    @projects = []
    @statuses = []
    @types = []
    @selected_project = nil
    @selected_status = DEFAULT_STATUSES.dup
    @selected_q = nil
    @selected_type = []
    @issue_kpis = { pending: 0, urgent_complaints: 0, total_hours_sum: 0 }
    @pagy = nil
    @issues = []
    @error = message
  end
end
