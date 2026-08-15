class BurndownIssueBlueprint < Blueprinter::Base
  identifier :issue_id

  # reported_remaining_hours（A 欄，PM 手動填寫的剩餘人時）僅供頁面顯示參考，不參與
  # ideal_series／actual_series 的計算，也不做兩者的交叉校驗（見 design.md 說明）。
  fields :project, :issue_title, :assignees, :start_date, :due_date, :status,
         :estimated_hours, :reported_remaining_hours, :actual_series, :ideal_series, :per_assignee
end
