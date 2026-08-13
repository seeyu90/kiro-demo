class ProjectTaskBlueprint < Blueprinter::Base
  identifier :task_name

  fields :project_name, :task_name, :status, :owner,
         :planned_completion_date, :actual_completion_date, :delay_days
end
