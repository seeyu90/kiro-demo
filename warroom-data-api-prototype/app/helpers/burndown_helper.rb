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

  # 理想／實際兩條序列共用同一個 Y 軸比例，取兩者數值中的最大值／最小值，避免任一條線超出
  # 繪圖區域。實際人時超支（RD 花費超過預估人時）時，剩餘人時會變成負數，故最小值不能固定為
  # 0，要一併納入計算，否則負值的線段／資料點會被畫到繪圖區域外面看不到。
  def burndown_chart_range(actual_series, ideal_series)
    values = (actual_series + ideal_series).map { |point| point[:hours].to_f }
    max = [ values.max || 1, 1 ].max
    min = [ values.min || 0, 0 ].min
    [ min, max ]
  end

  # 實際／理想兩條序列共用同一組 X 軸日期：理想線會在頭尾補上開案／完成錨點（見
  # Sheets::FetchProjectBurndown#compute_ideal_series），這些錨點的日期不一定存在於試算表現有
  # 的週欄位（也就不一定存在於實際序列）中，若各自依自己的序列長度計算 X 座標，兩條線會對不
  # 齊、日期跟畫面上的位置也會對不上。故取兩者日期的聯集、依日期排序，做為共用的 X 軸。
  def burndown_chart_dates(actual_series, ideal_series)
    (actual_series.map { |p| p[:date] } + ideal_series.map { |p| p[:date] }).uniq.sort
  end

  def burndown_chart_points(series, dates, min, max)
    index_by_date = dates.each_with_index.to_h
    step_x = burndown_chart_plot_width / [ dates.length - 1, 1 ].max.to_f

    series.map do |point|
      x = BURNDOWN_PADDING_LEFT + index_by_date.fetch(point[:date]) * step_x
      y = burndown_chart_y(point[:hours], min, max)
      point.merge(x: x.round(2), y: y.round(2))
    end
  end

  def burndown_chart_polyline(points)
    points.map { |p| "#{p[:x]},#{p[:y]}" }.join(" ")
  end

  # 均分的格線不保證剛好經過 0（例如 min 為負、max 為正時，0 通常落在兩條均分線中間）；
  # 「剩餘人時 = 0」是燃盡圖最關鍵的參考線（代表準時完成／超支的分界），一定要畫出來，
  # 故在均分格線之外，min／max 跨越 0 時額外補一條 0 的格線。
  def burndown_chart_y_ticks(min, max)
    ticks = (0...BURNDOWN_Y_TICKS).map do |t|
      value = (min + (max - min) / (BURNDOWN_Y_TICKS - 1).to_f * t).round
      { value: value, y: burndown_chart_y(value, min, max).round(2) }
    end
    ticks << { value: 0, y: burndown_chart_y(0, min, max).round(2) } if min < 0 && max > 0
    ticks.uniq { |t| t[:value] }.sort_by { |t| t[:value] }
  end

  def burndown_chart_x_labels(dates)
    step_x = burndown_chart_plot_width / [ dates.length - 1, 1 ].max.to_f

    dates.each_with_index.map do |date, i|
      x = BURNDOWN_PADDING_LEFT + i * step_x
      { x: x.round(2), text: burndown_chart_short_date(date) }
    end
  end

  private

  def burndown_chart_plot_width
    BURNDOWN_WIDTH - BURNDOWN_PADDING_LEFT - BURNDOWN_PADDING_RIGHT
  end

  def burndown_chart_plot_height
    BURNDOWN_HEIGHT - BURNDOWN_PADDING_TOP - BURNDOWN_PADDING_BOTTOM
  end

  def burndown_chart_y(value, min, max)
    ratio = (value.to_f - min) / (max - min)
    BURNDOWN_HEIGHT - BURNDOWN_PADDING_BOTTOM - ratio * burndown_chart_plot_height
  end

  def burndown_chart_short_date(date_str)
    parts = date_str.to_s.split("-")
    parts.size == 3 ? "#{parts[1]}/#{parts[2]}" : date_str.to_s
  end
end
