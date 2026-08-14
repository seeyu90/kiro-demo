module BurndownHelper
  # 邏輯移植自 IssuesHelper 的 trend chart 座標計算（見 docs/js/issues.js 的 renderTrendChart）：
  # X 軸依序排列各週資料點，Y 軸依理想／實際兩條序列的共同最大值等比例縮放，供同一張 SVG
  # 疊合兩條折線使用。
  BURNDOWN_WIDTH = 640
  BURNDOWN_HEIGHT = 250
  BURNDOWN_PADDING_LEFT = 40
  BURNDOWN_PADDING_RIGHT = 12
  BURNDOWN_PADDING_TOP = 16
  BURNDOWN_PADDING_BOTTOM = 55
  BURNDOWN_Y_TICKS = 3

  # 理想／實際兩條序列共用同一個 Y 軸比例，取兩者數值中的最大值，避免任一條線超出繪圖區域。
  def burndown_chart_max(actual_series, ideal_series)
    values = (actual_series + ideal_series).map { |point| point[:hours].to_f }
    [ values.max || 1, 1 ].max
  end

  def burndown_chart_points(series, max)
    step_x = burndown_chart_plot_width / [ series.length - 1, 1 ].max.to_f

    series.each_with_index.map do |point, i|
      x = BURNDOWN_PADDING_LEFT + i * step_x
      y = burndown_chart_y(point[:hours], max)
      point.merge(x: x.round(2), y: y.round(2))
    end
  end

  def burndown_chart_polyline(points)
    points.map { |p| "#{p[:x]},#{p[:y]}" }.join(" ")
  end

  def burndown_chart_y_ticks(max)
    (0...BURNDOWN_Y_TICKS).map do |t|
      value = (max / (BURNDOWN_Y_TICKS - 1).to_f * t).round
      { value: value, y: burndown_chart_y(value, max).round(2) }
    end
  end

  # X 軸標籤依「實際序列」的週日期繪製：實際序列一定存在（只要有週欄位資料），理想序列可能為空
  # （起訖日缺失時），故不能用理想序列決定 X 軸。
  def burndown_chart_x_labels(series)
    step_x = burndown_chart_plot_width / [ series.length - 1, 1 ].max.to_f

    series.each_with_index.map do |point, i|
      x = BURNDOWN_PADDING_LEFT + i * step_x
      { x: x.round(2), text: burndown_chart_short_date(point[:date]) }
    end
  end

  private

  def burndown_chart_plot_width
    BURNDOWN_WIDTH - BURNDOWN_PADDING_LEFT - BURNDOWN_PADDING_RIGHT
  end

  def burndown_chart_plot_height
    BURNDOWN_HEIGHT - BURNDOWN_PADDING_TOP - BURNDOWN_PADDING_BOTTOM
  end

  def burndown_chart_y(value, max)
    BURNDOWN_HEIGHT - BURNDOWN_PADDING_BOTTOM - (value.to_f / max) * burndown_chart_plot_height
  end

  def burndown_chart_short_date(date_str)
    parts = date_str.to_s.split("-")
    parts.size == 3 ? "#{parts[1]}/#{parts[2]}" : date_str.to_s
  end
end
