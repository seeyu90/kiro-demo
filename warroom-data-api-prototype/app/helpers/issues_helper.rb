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

  # 邏輯移植自 docs/js/issues.js 的 renderTrendChart：X 軸等距分佈（超過 TREND_MAX_X_LABELS
  # 個資料點時，等距挑選含首尾的標籤索引，避免重疊），Y 軸依 total 最大值等比例縮放，繪製
  # 0／中間值／最大值三條格線。
  TREND_WIDTH = 640
  TREND_HEIGHT = 220
  TREND_PADDING_LEFT = 40
  TREND_PADDING_RIGHT = 12
  TREND_PADDING_TOP = 16
  TREND_PADDING_BOTTOM = 28
  TREND_MAX_X_LABELS = 6
  TREND_Y_TICKS = 3

  def trend_chart_points(daily_kpi)
    max = trend_chart_max(daily_kpi)
    step_x = trend_chart_plot_width / [daily_kpi.length - 1, 1].max.to_f

    daily_kpi.each_with_index.map do |record, i|
      x = TREND_PADDING_LEFT + i * step_x
      y = trend_chart_y(record[:total], max)
      record.merge(x: x.round(2), y: y.round(2))
    end
  end

  def trend_chart_polyline(points)
    points.map { |p| "#{p[:x]},#{p[:y]}" }.join(" ")
  end

  def trend_chart_y_ticks(daily_kpi)
    max = trend_chart_max(daily_kpi)

    (0...TREND_Y_TICKS).map do |t|
      value = (max / (TREND_Y_TICKS - 1).to_f * t).round
      { value: value, y: trend_chart_y(value, max).round(2) }
    end
  end

  def trend_chart_x_labels(daily_kpi)
    trend_chart_label_indices(daily_kpi.length).map do |i|
      x = TREND_PADDING_LEFT + i * (trend_chart_plot_width / [daily_kpi.length - 1, 1].max.to_f)
      { x: x.round(2), text: trend_chart_short_date(daily_kpi[i][:date]) }
    end
  end

  private

  def trend_chart_max(daily_kpi)
    [daily_kpi.map { |r| r[:total].to_f }.max || 1, 1].max
  end

  def trend_chart_plot_width
    TREND_WIDTH - TREND_PADDING_LEFT - TREND_PADDING_RIGHT
  end

  def trend_chart_plot_height
    TREND_HEIGHT - TREND_PADDING_TOP - TREND_PADDING_BOTTOM
  end

  def trend_chart_y(value, max)
    TREND_HEIGHT - TREND_PADDING_BOTTOM - (value.to_f / max) * trend_chart_plot_height
  end

  # 資料點數量超過可容納標籤數時，等距挑選索引（含首尾），避免橫軸標籤重疊。
  def trend_chart_label_indices(count)
    return [] if count.zero?
    return [0] if count == 1
    return (0...count).to_a if count <= TREND_MAX_X_LABELS

    step = (count - 1) / (TREND_MAX_X_LABELS - 1).to_f
    (0...TREND_MAX_X_LABELS).map { |k| (k * step).round }.uniq
  end

  def trend_chart_short_date(date_str)
    parts = date_str.to_s.split("-")
    parts.size == 3 ? "#{parts[1]}/#{parts[2]}" : date_str.to_s
  end
end
