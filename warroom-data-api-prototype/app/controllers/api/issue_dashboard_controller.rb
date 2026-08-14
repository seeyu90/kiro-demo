module Api
  class IssueDashboardController < ApplicationController
    def index
      result = Sheets::FetchIssueDashboard.result

      if result.success?
        render json: {
          month_kpi: MonthKpiBlueprint.render_as_hash(result.month_kpi),
          daily_kpi: DailyKpiBlueprint.render_as_hash(result.daily_kpi),
          issues: IssueBlueprint.render_as_hash(result.issues),
          project_breakdown: ProjectBreakdownBlueprint.render_as_hash(result.project_breakdown)
        }
      else
        render json: {
          error: {
            code: result.failure_code,
            message: result.message
          }
        }, status: error_status(result.failure_code)
      end
    end

    private

    def error_status(code)
      {
        sheet_not_found: 404,
        access_denied: 403,
        internal_error: 500
      }.fetch(code, 500)
    end
  end
end
