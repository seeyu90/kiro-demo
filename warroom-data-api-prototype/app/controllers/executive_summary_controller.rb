class ExecutiveSummaryController < ApplicationController
  def index
    result = Summary::BuildExecutiveSummary.result
    if result.success?
      build_success(result)
    else
      build_failure(result.message)
    end
  end

  private

  def build_success(result)
    @portfolio = result.portfolio
    @projects = ExecutiveProjectSummaryBlueprint.render_as_hash(result.projects)
    @phase_exceptions = result.phase_exceptions
    @phase_exceptions_by_customer = result.phase_exceptions_by_customer
    @last_week_summary = result.last_week_summary
    @roster_unavailable = result.roster_unavailable
    @burndown_unavailable = result.burndown_unavailable
    @issues_unavailable = result.issues_unavailable
    @phase_tracking_unavailable = result.phase_tracking_unavailable
    @error = nil
  end

  def build_failure(message)
    @portfolio = nil
    @projects = []
    @phase_exceptions = []
    @phase_exceptions_by_customer = []
    @last_week_summary = nil
    @error = message
  end
end
