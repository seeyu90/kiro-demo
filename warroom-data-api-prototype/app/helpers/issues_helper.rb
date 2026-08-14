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

  # 依專案分類表格的可排序欄位標題連結：同一欄位再次點選時反轉方向，切換到不同欄位時預設降冪
  # （筆數統計通常最關心「最多」的專案）；連結保留目前所選月份，並固定停留在「統計摘要」分頁籤。
  def breakdown_sort_link(key, label)
    active = @breakdown_sort == key.to_s
    next_dir = active && @breakdown_dir == "desc" ? "asc" : "desc"
    indicator = active ? (@breakdown_dir == "desc" ? " ▼" : " ▲") : ""

    link_to label + indicator, issues_path(month: @selected_month, tab: "stats", breakdown_sort: key, breakdown_dir: next_dir),
             class: "sort-button", "aria-label": "依「#{label}」排序"
  end

  # 邏輯移植自 docs/js/issues.js 的 renderTrendChart：X 軸每個資料點都顯示日期標籤（-45 度旋轉
  # 避免重疊），Y 軸依 total 最大值等比例縮放，繪製 0／中間值／最大值三條格線。
  TREND_WIDTH = 640
  TREND_HEIGHT = 250
  TREND_PADDING_LEFT = 40
  TREND_PADDING_RIGHT = 12
  TREND_PADDING_TOP = 16
  TREND_PADDING_BOTTOM = 55
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
    step_x = trend_chart_plot_width / [daily_kpi.length - 1, 1].max.to_f

    daily_kpi.each_with_index.map do |record, i|
      x = TREND_PADDING_LEFT + i * step_x
      { x: x.round(2), text: trend_chart_short_date(record[:date]) }
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

  def trend_chart_short_date(date_str)
    parts = date_str.to_s.split("-")
    parts.size == 3 ? "#{parts[1]}/#{parts[2]}" : date_str.to_s
  end
end
