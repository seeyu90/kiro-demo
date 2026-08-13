# frozen_string_literal: true

module MockData
  module ProjectProgress
    RECORDS = [
      {
        project_name: "Project Alpha",
        task_name: "Initial setup",
        status: "completed",
        owner: "Alice",
        planned_completion_date: "2024/1/15",
        actual_completion_date: "2024/1/20",
        delay_days: 2
      },
      {
        project_name: "Project Alpha",
        task_name: "Design phase",
        status: "completed",
        owner: "Bob",
        planned_completion_date: "2024/01/21",
        actual_completion_date: "2024-02-05",
        delay_days: 0
      },
      {
        project_name: "Project Alpha",
        task_name: "Implementation",
        status: "completed",
        owner: "Charlie",
        planned_completion_date: "2024-02-06",
        actual_completion_date: "2024-02-20",
        delay_days: -3
      },
      {
        project_name: "Project Beta",
        task_name: "Requirements gathering",
        status: "completed",
        owner: "David",
        planned_completion_date: "2024/2/1",
        actual_completion_date: "2024/2/10",
        delay_days: 1
      },
      {
        project_name: "Project Beta",
        task_name: "Development",
        status: "in_progress",
        owner: "Eve",
        planned_completion_date: "2024/02/11",
        actual_completion_date: "2024-02-28",
        delay_days: 5
      },
      {
        project_name: "Project Beta",
        task_name: "Testing",
        status: "pending",
        owner: "Frank",
        planned_completion_date: "2024-02-29",
        actual_completion_date: nil,
        delay_days: nil
      }
    ].freeze
  end
end
