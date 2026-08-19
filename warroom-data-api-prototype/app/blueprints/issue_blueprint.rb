class IssueBlueprint < Blueprinter::Base
  identifier :issue_id

  fields :issue_id, :subject, :type, :tracker, :status, :assigned_to,
         :start_date, :due_date, :work_days, :project, :total_hours

  # 「歸屬類型」（見 IssuesHelper#attribution_label/#attribution_class）與「議題編號 Redmine 連結」
  # 皆非 Actor 輸出欄位，而是 View 依 type/issue_id 動態計算的顯示邏輯（需求 5.6、5.7、5.8），
  # 故不在此 Blueprint 中定義。
end
