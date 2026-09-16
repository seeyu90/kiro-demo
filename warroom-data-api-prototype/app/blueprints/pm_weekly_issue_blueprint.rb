class PmWeeklyIssueBlueprint < Blueprinter::Base
  identifier :issue_id

  # PM 週報專用：`effective_due_date`（含 SLA 推算結果）與 `due_date_estimated`（是否為推算值，
  # 需求 3.5 要在畫面上標示）是本頁才需要的衍生欄位，故不加進 IssueBlueprint——那支是 306
  # 議題頁與 /api/issue_dashboard 的欄位契約，欄位不得隨意增減。
  fields :issue_id, :subject, :type, :status, :assigned_to, :project,
         :effective_due_date, :due_date_estimated
end
