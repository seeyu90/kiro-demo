class IssuesController < ApplicationController
  DEFAULT_STATUS = "新建立".freeze
  TABS = %w[stats detail].freeze
  DEFAULT_TAB = "stats".freeze
  BREAKDOWN_SORT_KEYS = %w[complaint testing other total].freeze
  BREAKDOWN_SORT_DIRS = %w[asc desc].freeze
  DEFAULT_BREAKDOWN_SORT_DIR = "desc".freeze

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
    all_daily_kpi = DailyKpiBlueprint.render_as_hash(result.daily_kpi)

    # 月份選單納入進行中的當月（即使 month_kpi 尚無該月列，因為月結數字要等月底才產生），
    # 但預設選中仍是最新「已結算」月份，確保頁面載入時直接看到有意義的月結數字。
    current_year_month = Date.current.strftime("%Y-%m")
    @available_months = (@month_kpi.map { |m| m[:year_month] } + [current_year_month]).uniq.sort
    @selected_month = params[:month].presence || @month_kpi.map { |m| m[:year_month] }.max
    @selected_month_record = @month_kpi.find { |m| m[:year_month] == @selected_month }
    @selected_month_pending = @selected_month_record.nil? && @selected_month == current_year_month

    all_issues = IssueBlueprint.render_as_hash(result.issues)

    # 每日趨勢與依專案分類統計皆依所選月份呈現（使用者反映兩者與月度 KPI 同屬「統計摘要」
    # 分頁籤，理應一起隨月份切換，而非僅月度 KPI 卡片受影響）；依專案分類以議題的 start_date
    # （建立日）判斷所屬月份，議題明細本身則不受月份篩選（見需求 8）。
    @daily_kpi = all_daily_kpi.select { |d| same_month?(d[:date], @selected_month) }
    month_issues = all_issues.select { |i| same_month?(i[:start_date], @selected_month) }

    # 排序欄位／方向皆為選填 query params；未帶或帶入非法值時維持原始（依專案分組）順序。
    @breakdown_sort = params[:breakdown_sort] if BREAKDOWN_SORT_KEYS.include?(params[:breakdown_sort])
    @breakdown_dir =
      BREAKDOWN_SORT_DIRS.include?(params[:breakdown_dir]) ? params[:breakdown_dir] : DEFAULT_BREAKDOWN_SORT_DIR
    @project_breakdown = sort_project_breakdown(compute_project_breakdown(month_issues))

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
    @issues = []
    @error = message
  end

  def filter_issues(issues)
    issues
      .select { |i| @selected_project.blank? || i[:project] == @selected_project }
      .select { |i| @selected_status.blank? || i[:status] == @selected_status }
  end

  # 以日期欄位前 7 碼（YYYY-MM）判斷是否屬於指定月份，與 prototype 的 sameMonth() 邏輯一致。
  def same_month?(date_str, year_month)
    date_str.is_a?(String) && date_str[0, 7] == year_month
  end

  # 依 project 分組統計 complaint／testing／other 筆數與 total；邏輯與
  # Sheets::FetchIssueDashboard#compute_project_breakdown 相同，但這裡對「已依月份篩選的
  # 議題子集」運算（Actor 版本對全量議題運算，供 API 使用，兩者用途不同，故不共用）。
  def compute_project_breakdown(issues)
    grouped = issues.each_with_object({}) do |issue, acc|
      key = issue[:project].to_s.strip.empty? ? "未分類" : issue[:project]
      acc[key] ||= { project: key, complaint: 0, testing: 0, other: 0 }

      case issue[:type]
      when "Complaint" then acc[key][:complaint] += 1
      when "TestingBug" then acc[key][:testing] += 1
      else acc[key][:other] += 1
      end
    end

    grouped.values.map { |row| row.merge(total: row[:complaint] + row[:testing] + row[:other]) }
  end

  # @breakdown_sort 為 nil 時維持原始（依專案分組）順序，不排序。
  def sort_project_breakdown(rows)
    return rows if @breakdown_sort.nil?

    sorted = rows.sort_by { |row| row[@breakdown_sort.to_sym] }
    @breakdown_dir == "desc" ? sorted.reverse : sorted
  end
end
