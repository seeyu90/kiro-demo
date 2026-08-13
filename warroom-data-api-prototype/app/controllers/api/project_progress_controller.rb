module Api
  class ProjectProgressController < ApplicationController
    def index
      result = Sheets::FetchProjectProgress.result

      if result.success?
        serialized = result.grouped_data.transform_values do |tasks|
          ProjectTaskBlueprint.render_as_hash(tasks)
        end
        render json: serialized
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
        invalid_data_format: 422,
        access_denied: 403,
        internal_error: 500
      }.fetch(code, 500)
    end
  end
end
