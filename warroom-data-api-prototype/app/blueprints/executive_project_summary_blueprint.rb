class ExecutiveProjectSummaryBlueprint < Blueprinter::Base
  identifier :project_name

  fields :customer, :pm, :health, :task_completion_percent,
         :overdue_task_count, :due_this_week_count, :overdue_tasks,
         :burndown_flag, :at_risk_burndown_issues, :complaint_count
end
