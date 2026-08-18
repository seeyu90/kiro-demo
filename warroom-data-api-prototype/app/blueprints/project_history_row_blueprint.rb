class ProjectHistoryRowBlueprint < Blueprinter::Base
  identifier :project_name

  # :tasks 是巢狀的議題清單（同時供甘特圖繪製區間、清單頁展開後的議題明細表格使用），非扁平
  # 顯示欄位，但比照 BurndownIssueBlueprint 納入 :actual_series／:ideal_series 等巢狀計算資料
  # 的既有慣例，一併納入本 Blueprint（View 與 Controller 共用同一份輸出欄位定義）。
  fields :customer, :pm, :status, :tasks,
         :progress_percent, :hours_estimated, :hours_consumed, :has_overdue
end
