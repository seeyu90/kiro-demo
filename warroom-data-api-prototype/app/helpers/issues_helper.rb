module IssuesHelper
  # type 欄位對應歸屬責任：Complaint（客訴）＝專案共同責任，TestingBug（測試）＝個人責任，
  # 其餘（Other）列為「其他」。邏輯與 prototype 的 attributionLabel/attributionClass 一致。
  ATTRIBUTION_LABELS = { "Complaint" => "專案共同責任", "TestingBug" => "個人責任" }.freeze
  ATTRIBUTION_CLASSES = { "Complaint" => "attribution-shared", "TestingBug" => "attribution-individual" }.freeze

  def attribution_label(type)
    ATTRIBUTION_LABELS[type] || "其他"
  end

  def attribution_class(type)
    ATTRIBUTION_CLASSES[type] || "attribution-other"
  end

  TREND_CHART_WIDTH = 640
  TREND_CHART_HEIGHT = 200
  TREND_CHART_PADDING = 28

  # 邏輯移植自 docs/js/issues.js 的 renderTrendChart：X 軸等距分佈，Y 軸依 total 最大值
  # 等比例縮放。回傳每筆資料點附加 :x/:y 座標，供 view 逐點渲染 <circle> 與組 <polyline>。
  def trend_chart_points(daily_kpi)
    max = [daily_kpi.map { |r| r[:total].to_f }.max || 1, 1].max
    step_x = (TREND_CHART_WIDTH - TREND_CHART_PADDING * 2) / [daily_kpi.length - 1, 1].max.to_f

    daily_kpi.each_with_index.map do |record, i|
      x = TREND_CHART_PADDING + i * step_x
      y = TREND_CHART_HEIGHT - TREND_CHART_PADDING - (record[:total].to_f / max) * (TREND_CHART_HEIGHT - TREND_CHART_PADDING * 2)
      record.merge(x: x.round(2), y: y.round(2))
    end
  end

  def trend_chart_polyline(points)
    points.map { |p| "#{p[:x]},#{p[:y]}" }.join(" ")
  end
end
