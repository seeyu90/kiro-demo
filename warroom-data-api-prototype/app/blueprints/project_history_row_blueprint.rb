class ProjectHistoryRowBlueprint < Blueprinter::Base
  identifier :project_name

  # :tasks 是巢狀的任務清單（供甘特圖繪製區間用），非扁平顯示欄位，但比照
  # BurndownIssueBlueprint 納入 :actual_series／:ideal_series 等巢狀計算資料的既有慣例，
  # 一併納入本 Blueprint（View 與 Controller 共用同一份輸出欄位定義）。
  fields :customer, :pm, :status, :planned_completion_date, :actual_completion_date, :tasks
end
