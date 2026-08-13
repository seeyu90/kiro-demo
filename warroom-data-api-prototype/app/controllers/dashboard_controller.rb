class DashboardController < ApplicationController
  def index
    result = Sheets::FetchProjectProgress.result
    if result.success?
      @grouped_data     = result.grouped_data
      @project_names    = @grouped_data.keys
      @selected_project = params[:project].presence
      filtered          = @selected_project ? @grouped_data.slice(@selected_project) : @grouped_data
      @display_data     = filtered.transform_values { |tasks| ProjectTaskBlueprint.render_as_hash(tasks) }
      @error            = nil
    else
      @grouped_data     = {}
      @project_names    = []
      @selected_project = nil
      @display_data     = {}
      @error            = result.message
    end
  end
end
