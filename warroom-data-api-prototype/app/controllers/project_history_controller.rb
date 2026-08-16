class ProjectHistoryController < ApplicationController
  VIEWS = %w[list gantt].freeze
  DEFAULT_VIEW = "list".freeze

  def index
    result = Sheets::FetchProjectHistory.result(project: params[:project].presence)
    if result.success?
      build_success(result)
    else
      build_failure(result.message)
    end
  end

  private

  def build_success(result)
    all_rows = ProjectHistoryRowBlueprint.render_as_hash(result.overview_rows)
    @project_names = all_rows.map { |r| r[:project_name] }

    @selected_project = params[:project].presence
    @view = VIEWS.include?(params[:view]) ? params[:view] : DEFAULT_VIEW

    if @selected_project.present?
      build_detail(result)
    else
      build_overview(all_rows)
    end
    @error = nil
  end

  def build_overview(all_rows)
    @statuses = all_rows.map { |r| r[:status] }.compact.uniq
    @customers = all_rows.map { |r| r[:customer] }.compact.uniq
    @pms = all_rows.map { |r| r[:pm] }.compact.uniq

    @selected_status = params[:status].presence
    @selected_customer = params[:customer].presence
    @selected_pm = params[:pm].presence

    @rows = all_rows.select do |row|
      (@selected_status.blank? || row[:status] == @selected_status) &&
        (@selected_customer.blank? || row[:customer] == @selected_customer) &&
        (@selected_pm.blank? || row[:pm] == @selected_pm)
    end
  end

  def build_detail(result)
    detail = result.detail
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
    @statuses = []
    @customers = []
    @pms = []
    @selected_status = nil
    @selected_customer = nil
    @selected_pm = nil
    @rows = []
    @work_hours_series = []
    @ideal_series = []
    @actual_series = []
    @testing_trend = []
    @complaint_summary = { resolved_count: 0, unresolved_count: 0, unresolved_list: [] }
    @error = message
  end
end
