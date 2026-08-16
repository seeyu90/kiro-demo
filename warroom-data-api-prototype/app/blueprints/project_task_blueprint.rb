class ProjectTaskBlueprint < Blueprinter::Base
  identifier :task_name

  # 同時供 DashboardController（HTML）與 Api::ProjectProgressController（JSON API）使用，
  # 欄位是對外 API 的一部分，不可隨意增減（見 spec/requests/api/project_progress_spec.rb
  # 的欄位契約測試）；「是否逾期」只有 HTML 畫面需要，故不放在這裡，見
  # Sheets::FetchProjectProgress.overdue?（DashboardController 端委派呼叫）。
  fields :project_name, :task_name, :status, :owner,
         :planned_completion_date, :actual_completion_date, :delay_days,
         :task_type
end
