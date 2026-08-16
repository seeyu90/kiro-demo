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

  # 多人員累積消耗人時堆疊圖（見 Sheets::FetchProjectBurndown#per_assignee_series）：固定色盤依
  # per_assignee 的順序輪流指派，人數不多（實務上議題很少超過個位數協作者），循環用色即可。
  BURNDOWN_STACK_COLORS = %w[#60a5fa #f472b6 #34d399 #fbbf24 #a78bfa #fb923c #38bdf8 #f87171].freeze

  # Y 軸最大值取「疊加後某週的最高累積人時」與「總預估人時」兩者較大者：後者是參考線一定要
  # 落在繪圖範圍內，前者則是實際超支（疊加總量超過預估）時，柱狀／面積不能被裁掉看不到。
  def burndown_stacked_chart_max(per_assignee, estimated_hours)
    top = burndown_stacked_totals(per_assignee).max || 0.0
    [ top, estimated_hours.to_f, 1 ].max
  end

  # 每一週「所有人員疊加後」的累積人時總和：等同該週的議題整體累積消耗（每人各自累積人時
  # 加總），用來判斷 Y 軸最大值是否要因超支而放大於總預估人時。
  def burndown_stacked_totals(per_assignee)
    return [] if per_assignee.blank?

    dates = burndown_stacked_chart_dates(per_assignee)
    dates.each_index.map { |i| per_assignee.sum { |pa| pa[:cumulative_series][i][:hours].to_f } }
  end

  def burndown_stacked_chart_dates(per_assignee)
    per_assignee.first&.dig(:cumulative_series)&.map { |p| p[:date] } || []
  end

  # 依 per_assignee 順序，逐人算出一塊堆疊區塊（SVG polygon）：下緣＝前面所有人已疊加的累計，
  # 上緣＝加上這個人自己的累積人時之後的新高度，兩條邊界依日期前進、再折返，組成封閉多邊形。
  def burndown_stacked_chart_polygons(per_assignee, dates, max)
    step_x = burndown_chart_plot_width / [ dates.length - 1, 1 ].max.to_f
    running = Array.new(dates.length, 0.0)

    per_assignee.each_with_index.map do |pa, idx|
      values = pa[:cumulative_series].map { |p| p[:hours].to_f }
      top = running.each_index.map { |i| running[i] + values[i] }

      bottom_edge = dates.each_index.map { |i| [ BURNDOWN_PADDING_LEFT + i * step_x, burndown_chart_y(running[i], 0, max) ] }
      top_edge = dates.each_index.map { |i| [ BURNDOWN_PADDING_LEFT + i * step_x, burndown_chart_y(top[i], 0, max) ] }
      polygon = (bottom_edge + top_edge.reverse).map { |x, y| "#{x.round(2)},#{y.round(2)}" }.join(" ")

      running = top
      { assignee: pa[:assignee], color: BURNDOWN_STACK_COLORS[idx % BURNDOWN_STACK_COLORS.length], points: polygon }
    end
  end

  def burndown_stacked_chart_reference_y(estimated_hours, max)
    burndown_chart_y(estimated_hours, 0, max).round(2)
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
