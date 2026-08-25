class PhaseTrackingCardBlueprint < Blueprinter::Base
  identifier :project

  # :stages 是巢狀的階段追蹤清單（{ stage:, primary:, history: }，見 Sheets::FetchPhaseTracking），
  # 同既有 ProjectHistoryRowBlueprint 對 :tasks 的處理慣例，Controller／View 共用同一份輸出欄位
  # 定義。:record_years 是內部篩選用欄位（Controller 已在 Actor 輸出時篩完年度），不對外呈現。
  fields :issue_id, :issue_name, :customer, :pm, :status, :planned_completion_date, :stages
end
