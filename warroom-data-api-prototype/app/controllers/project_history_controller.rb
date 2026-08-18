class ProjectHistoryController < ApplicationController
  VIEWS = %w[list gantt].freeze
  DEFAULT_VIEW = "list".freeze

  def index
    year = resolve_year
    result = Sheets::FetchProjectHistory.result(project: params[:project].presence, year: year)
    if result.success?
      build_success(result, year)
    else
      build_failure(result.message)
    end
  end

  private

  # 縱向歷程（帶 project 參數）的年度篩選預設「全部年度」（既有行為，未帶 year 參數＝nil）；
  # 總覽的年度篩選預設「今年」，但使用者能透過下拉選單明確選「全部年度」（表單一律送出
  # year 參數，即使值是空字串，用 `params.key?` 區分「使用者選了全部年度」與「表單根本還沒
  # 送出過」這兩種情況，只有後者才套用今年當預設值）。
  def resolve_year
    return params[:year].presence if params[:project].present?
    return params[:year].presence if params.key?(:year)

    Date.current.year.to_s
  end

  def build_success(result, year)
    all_rows = ProjectHistoryRowBlueprint.render_as_hash(result.overview_rows)
    @project_names = all_rows.map { |r| r[:project_name] }

    @selected_project = params[:project].presence
    @view = VIEWS.include?(params[:view]) ? params[:view] : DEFAULT_VIEW

    if @selected_project.present?
      build_detail(result)
    else
      build_overview(all_rows, result, year)
    end
    @error = nil
  end

  def build_overview(all_rows, result, year)
    @roster_unavailable = result.roster_unavailable
    @gantt_duration_unavailable = result.gantt_duration_unavailable
    @statuses = all_rows.map { |r| r[:status] }.compact.uniq
    @customers = all_rows.map { |r| r[:customer] }.compact.uniq
    @pms = all_rows.map { |r| r[:pm] }.compact.uniq
    @available_years = result.overview_years

    @selected_status = params[:status].presence
    @selected_customer = params[:customer].presence
    @selected_pm = params[:pm].presence
    @selected_project_name = params[:project_name].presence
    @selected_year = year

    filtered = all_rows.select do |row|
      (@selected_status.blank? || row[:status] == @selected_status) &&
        (@selected_customer.blank? || row[:customer] == @selected_customer) &&
        (@selected_pm.blank? || row[:pm] == @selected_pm) &&
        (@selected_project_name.blank? || row[:project_name] == @selected_project_name)
    end
    # 含逾期未完成任務的專案排在最前面，其餘維持原本相對順序（需求 4.4）。
    @rows = filtered.sort_by { |row| row[:has_overdue] ? 0 : 1 }
  end

  def build_detail(result)
    detail = result.detail
    @available_years = detail[:available_years]
    @selected_year = detail[:selected_year]
    @work_hours_series = detail[:work_hours_series]
    @ideal_series = detail[:ideal_series]
    @actual_series = detail[:actual_series]
    @testing_trend = detail[:testing_trend]
    @complaint_summary = detail[:complaint_summary]
  end

  def build_failure(message)
    @project_names = []
    @selected_project = nil
    @view = DEFAULT_VIEW
    @roster_unavailable = false
    @gantt_duration_unavailable = false
    @statuses = []
    @customers = []
    @pms = []
    @selected_status = nil
    @selected_customer = nil
    @selected_pm = nil
    @selected_project_name = nil
    @rows = []
    @available_years = []
    @selected_year = nil
    @work_hours_series = []
    @ideal_series = []
    @actual_series = []
    @testing_trend = []
    @complaint_summary = { resolved_count: 0, unresolved_count: 0, unresolved_list: [] }
    @error = message
  end
end
