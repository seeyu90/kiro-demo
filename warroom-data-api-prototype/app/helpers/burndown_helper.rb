module BurndownHelper
  # 邏輯移植自 IssuesHelper 的 trend chart 座標計算（見 docs/js/issues.js 的 renderTrendChart）：
  # X 軸依序排列各週資料點，Y 軸依理想／實際兩條序列的共同最大值等比例縮放，供同一張 SVG
  # 疊合兩條折線使用。
  BURNDOWN_WIDTH = 640
  BURNDOWN_HEIGHT = 250
  BURNDOWN_PADDING_LEFT = 40
  # 單軸圖表（左軸長條用）原本的窄右邊界；組合圖表改用 burndown_combo_padding_right 依
  # 人數動態計算（每人一條自己的右軸，見下方常數與方法）。
  BURNDOWN_PADDING_RIGHT = 12
  # 組合圖表每人一條右軸，軸線正上方要放色塊標記＋最大值數字（見
  # _burndown_combo_chart.html.erb），16px 放不下「色塊、間距、數字」三層還會互相貼在一起，
  # 故留大一點的上邊界。
  BURNDOWN_PADDING_TOP = 28
  BURNDOWN_PADDING_BOTTOM = 55
  BURNDOWN_Y_TICKS = 3

  # 每人一條自己的右軸（而非全部人共用一條）：估計人時差很多時（例如 167 vs 20），共用一條
  # 線性軸會把估計少的人壓扁在底部，看不出他自己的進度細節。每條軸各自的欄寬，以及固定的
  # 右側基礎留白（軸線跟圖表最右緣的間距）。
  BURNDOWN_AXIS_COLUMN_WIDTH = 34
  BURNDOWN_PADDING_RIGHT_BASE = 14

  # 組合圖表的右邊界：依人數動態計算，人數越多、需要的軸欄位越多。
  def burndown_combo_padding_right(assignee_count)
    BURNDOWN_PADDING_RIGHT_BASE + [ assignee_count, 1 ].max * BURNDOWN_AXIS_COLUMN_WIDTH
  end

  # 實際／理想兩條序列共用同一組 X 軸日期：理想線會在頭尾補上開案／完成錨點（見
  # Sheets::FetchProjectBurndown#compute_ideal_series），這些錨點的日期不一定存在於試算表現有
  # 的週欄位（也就不一定存在於實際序列）中，若各自依自己的序列長度計算 X 座標，兩條線會對不
  # 齊、日期跟畫面上的位置也會對不上。故取兩者日期的聯集、依日期排序，做為共用的 X 軸。
  def burndown_chart_dates(actual_series, ideal_series)
    (actual_series.map { |p| p[:date] } + ideal_series.map { |p| p[:date] }).uniq.sort
  end

  def burndown_chart_points(series, dates, min, max, padding_right: BURNDOWN_PADDING_RIGHT)
    index_by_date = dates.each_with_index.to_h
    step_x = burndown_chart_plot_width(padding_right) / [ dates.length - 1, 1 ].max.to_f

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

  def burndown_chart_x_labels(dates, padding_right: BURNDOWN_PADDING_RIGHT)
    step_x = burndown_chart_plot_width(padding_right) / [ dates.length - 1, 1 ].max.to_f

    dates.each_with_index.map do |date, i|
      x = BURNDOWN_PADDING_LEFT + i * step_x
      { x: x.round(2), text: burndown_chart_short_date(date) }
    end
  end

  # 多人員週別長條（見 Sheets::FetchProjectBurndown#per_assignee_series）：固定色盤依
  # per_assignee 的順序輪流指派，人數不多（實務上議題很少超過個位數協作者），循環用色即可。
  BURNDOWN_STACK_COLORS = %w[#60a5fa #f472b6 #34d399 #fbbf24 #a78bfa #fb923c #38bdf8 #f87171].freeze

  # 長條圖＋兩條累積線疊在同一張圖，取代原本分開的燃盡折線圖（剩餘人時）跟堆疊面積圖
  # （累積消耗人時）：長條可以直接看「這週誰在做」，線則看整體累積進度對不對，不用在兩張圖
  # 之間對照日期；長條與線同一個方向（都是「消耗」，數字越大代表做得越多），比原本燃盡圖用
  # 「剩餘」的敏捷慣例更直覺。日期範圍取「各人員週別資料」與「兩條累積線」的聯集，理想線的
  # 頭尾錨點（開案／完成日）可能落在任一人員實際回報的週別之外。
  def burndown_combo_dates(issue)
    per_assignee_dates = issue[:per_assignee].flat_map { |pa| pa[:cumulative_series].map { |p| p[:date] } }
    line_dates = burndown_chart_dates(issue[:actual_series], issue[:ideal_series])
    (per_assignee_dates + line_dates).uniq.sort
  end

  # 燃盡圖原本的兩條序列是「剩餘人時」（敏捷慣例），跟長條的「消耗人時」方向相反，疊在同一張
  # 圖會很難讀（長條往上代表做得多，線往上却代表剩得多）。統一轉成「累積消耗人時」
  # （consumed = estimated_hours − remaining），兩者才會同一個方向。
  def burndown_cumulative_consumed(series, estimated_hours)
    series.map { |point| { date: point[:date], hours: (estimated_hours.to_f - point[:hours].to_f).round(2) } }
  end

  # per_assignee 的 cumulative_series 本身是累積值，長條需要的是「單週增量」，用相鄰兩筆
  # 累積值相減還原回單週數字（第一筆前面視為 0）。
  def burndown_weekly_by_assignee(per_assignee)
    per_assignee.map do |pa|
      series = pa[:cumulative_series]
      weekly = series.each_with_index.map do |point, i|
        previous = i.zero? ? 0.0 : series[i - 1][:hours].to_f
        { date: point[:date], hours: (point[:hours].to_f - previous).round(2) }
      end
      { assignee: pa[:assignee], weekly: weekly }
    end
  end

  # 每人自己的理想累積人時軌跡：起點 0 落在開案日、終點是「這個人自己的預估人時」落在完成日，
  # 跟 burndown_per_assignee_status 用同一套時間比例公式，只是這裡算出整條線（每個 X 軸日期
  # 一個點）而不是只算最新一週那一個點。三個人就有三條理想線，各自跟自己的實際累積線比較，
  # 而不是像原本一樣所有人共用同一條「議題整體」理想線——份量不同，共用一條線沒有意義。
  def burndown_per_assignee_ideal_series(per_assignee_entry, issue, dates)
    start_d = safe_parse_date(issue[:start_date])
    due_d = safe_parse_date(issue[:due_date])
    return [] if start_d.nil? || due_d.nil? || due_d <= start_d

    estimated = per_assignee_entry[:estimated_hours].to_f

    dates.filter_map do |date_str|
      d = safe_parse_date(date_str)
      next if d.nil?

      ratio = ((d - start_d).to_f / (due_d - start_d)).clamp(0.0, 1.0)
      { date: date_str, hours: (estimated * ratio).round(2) }
    end
  end

  # 長條（左軸）Y 軸最大值：長條改成「每人各自一根、並排」而不是疊加，故取單一根長條的最高
  # 單週人時即可（不用像堆疊時取加總）。
  def burndown_combo_bar_max(weekly_by_assignee, dates)
    values = dates.flat_map do |date|
      weekly_by_assignee.map { |w| w[:weekly].find { |p| p[:date] == date }&.dig(:hours).to_f || 0.0 }
    end
    [ values.max || 0.0, 1 ].max
  end

  # 線（右軸）Y 軸最大值：series_list 是多條序列（每人自己的實際／理想累積線），extra_values
  # 通常是每人自己的預估人時（理想線終點雖然理論上等於預估人時，仍額外納入避免無資料時的
  # 邊界情況）。
  def burndown_combo_line_max(series_list, extra_values = [])
    values = series_list.flatten.map { |p| p[:hours].to_f } + extra_values.map(&:to_f)
    [ values.max || 0.0, 1 ].max
  end

  # 每人各自一根長條、並排顯示在同一週的欄位內（而非疊加），才能直接比較「這週誰做得多」。
  # 單週人時理論上不會是負值，但保留 clamp 避免試算表資料修正（例如更正列）讓某週人時倒退。
  def burndown_combo_bars(weekly_by_assignee, dates, left_max, padding_right: BURNDOWN_PADDING_RIGHT)
    step_x = burndown_chart_plot_width(padding_right) / [ dates.length - 1, 1 ].max.to_f
    assignee_count = [ weekly_by_assignee.size, 1 ].max
    slot_width = [ step_x * 0.7, 60 ].min
    bar_width = slot_width / assignee_count
    plot_left = BURNDOWN_PADDING_LEFT
    plot_right = BURNDOWN_WIDTH - padding_right
    zero_y = burndown_chart_y(0, 0, left_max)

    dates.each_with_index.flat_map do |date, i|
      x_center = BURNDOWN_PADDING_LEFT + i * step_x
      # 整組並排長條（slot）以 x_center 為中心，但兩端點（第一週／最後一週）的 slot 會有一半
      # 寬度伸出繪圖區域、跟左右軸的刻度文字重疊，故整組 clamp 在繪圖區域內。
      slot_left = [ [ x_center - slot_width / 2, plot_left ].max, plot_right - slot_width ].min

      weekly_by_assignee.each_with_index.map do |w, idx|
        hours = [ w[:weekly].find { |p| p[:date] == date }&.dig(:hours).to_f || 0.0, 0.0 ].max
        y_top = burndown_chart_y(hours, 0, left_max)

        {
          assignee: w[:assignee],
          color: BURNDOWN_STACK_COLORS[idx % BURNDOWN_STACK_COLORS.length],
          x: (slot_left + idx * bar_width).round(2),
          y: y_top.round(2),
          width: bar_width.round(2),
          height: (zero_y - y_top).round(2),
          hours: hours.round(2),
          date: date
        }
      end
    end
  end

  # 右軸刻度：跟左軸共用同一段繪圖高度（burndown_chart_y 的 BURNDOWN_HEIGHT／PADDING 是同一組
  # 常數），只是帶入不同的數值範圍（0..max），這樣兩個軸才會對齊到同一個繪圖區域。
  def burndown_combo_right_ticks(max)
    (0...BURNDOWN_Y_TICKS).map do |t|
      value = (max / (BURNDOWN_Y_TICKS - 1).to_f * t).round
      { value: value, y: burndown_chart_y(value, 0, max).round(2) }
    end
  end

  # 議題狀態摘要表用的燈號：比較「最新一週實際剩餘人時」與「同一天理想線應剩餘人時」的落差，
  # 換算成佔預估人時的比例，門檻抓相對值而非絕對小時數（議題大小差異很大，絕對門檻會對小
  # 議題太嚴格、對大議題太寬鬆）。estimated_hours 為 0（未填預估）或任一序列缺資料時，落差
  # 無法計算，回傳 :unknown 交由畫面顯示「資料不足」。
  BURNDOWN_STATUS_AT_RISK_RATIO = 0.05
  BURNDOWN_STATUS_OVER_RATIO = 0.25

  def burndown_status(issue)
    actual_series = issue[:actual_series]
    ideal_series = issue[:ideal_series]
    estimated_hours = issue[:estimated_hours].to_f
    return { key: :unknown, label: "資料不足" } if actual_series.blank? || ideal_series.blank? || estimated_hours.zero?

    latest_actual = actual_series.max_by { |p| p[:date] }
    # 剩餘人時已經是負值，代表已花掉的人時超過「整份」預估人時，這本身就是超支，不論理想線
    # 落在哪裡都一樣（理想線在完成日之後固定為 0，若只比較兩者落差，負值剩餘反而會被算成
    # 「領先進度」而誤判為正常，見 spec/helpers/burndown_helper_spec.rb 的迴歸測試）。
    return { key: :over, label: "超支" } if latest_actual[:hours].to_f.negative?

    ideal_at_date = ideal_series.find { |p| p[:date] == latest_actual[:date] } ||
      ideal_series.min_by { |p| (Date.parse(p[:date]) - Date.parse(latest_actual[:date])).abs }

    delta_ratio = (latest_actual[:hours].to_f - ideal_at_date[:hours].to_f) / estimated_hours

    if delta_ratio <= BURNDOWN_STATUS_AT_RISK_RATIO
      { key: :on_track, label: "正常" }
    elsif delta_ratio <= BURNDOWN_STATUS_OVER_RATIO
      { key: :at_risk, label: "略慢" }
    else
      { key: :over, label: "超支" }
    end
  end

  # 各人員燈號：單純比較「誰花的人時多」看不出誰進度落後，因為份量本來就不一樣（負責範圍
  # 大的人本來就會花比較多人時）。改成比較「這個人自己已消耗人時」vs「這個人自己的預估人時
  # ×（議題整體時間已過的比例）」——用同一份議題的開案／完成日期換算時間進度，再乘上這個人
  # 自己的份量，才是「這個人自己」應該進度到哪。落差門檻沿用 burndown_status 同一套相對比例。
  # 個人自己的預估人時為 0、或議題缺開案／完成日期（算不出時間進度）時，回傳 :unknown。
  def burndown_per_assignee_status(per_assignee_entry, issue)
    estimated = per_assignee_entry[:estimated_hours].to_f
    cumulative_series = per_assignee_entry[:cumulative_series]
    return { key: :unknown, label: "資料不足" } if estimated.zero? || cumulative_series.blank?

    latest = cumulative_series.max_by { |p| p[:date] }
    actual_consumed = latest[:hours].to_f
    return { key: :over, label: "超支" } if actual_consumed > estimated

    start_d = safe_parse_date(issue[:start_date])
    due_d = safe_parse_date(issue[:due_date])
    return { key: :unknown, label: "資料不足" } if start_d.nil? || due_d.nil? || due_d <= start_d

    latest_date = safe_parse_date(latest[:date])
    time_ratio = ((latest_date - start_d).to_f / (due_d - start_d)).clamp(0.0, 1.0)
    ideal_consumed = estimated * time_ratio

    # 注意方向：這裡比較的是「已消耗」而不是「剩餘」，跟 burndown_status 的落差方向相反——
    # 消耗得比理想進度「少」才是落後（時間過去了、份內的人時卻還沒花，代表沒什麼進度），
    # 消耗得比理想進度多只要沒超過自己的總預估就不算落後，故落差要反過來算
    # （ideal - actual，而非 actual - ideal）才會跟 burndown_status 同一套門檻語意一致。
    delta_ratio = (ideal_consumed - actual_consumed) / estimated

    if delta_ratio <= BURNDOWN_STATUS_AT_RISK_RATIO
      { key: :on_track, label: "正常" }
    elsif delta_ratio <= BURNDOWN_STATUS_OVER_RATIO
      { key: :at_risk, label: "略慢" }
    else
      { key: :over, label: "超支" }
    end
  end

  def safe_parse_date(date_str)
    return nil if date_str.blank?

    Date.parse(date_str.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # 摘要表「剩餘人時」欄位：優先採用試算表 PM 手動填寫的 reported_remaining_hours（最貼近
  # 真實現況），沒有填寫時退回 actual_series 最新一筆算出來的剩餘人時（同 burndown_status
  # 的資料來源，兩者不一定完全一致，僅供畫面顯示參考，比照 BurndownIssueBlueprint 註解的
  # 既有取捨：reported_remaining_hours 不參與正式計算）。
  def burndown_remaining_hours(issue)
    return issue[:reported_remaining_hours] if issue[:reported_remaining_hours].present?

    issue[:actual_series].max_by { |p| p[:date] }&.dig(:hours)
  end

  def burndown_consumed_hours(issue)
    remaining = burndown_remaining_hours(issue)
    return nil if remaining.nil?

    (issue[:estimated_hours].to_f - remaining.to_f).round(1)
  end

  private

  def burndown_chart_plot_width(padding_right = BURNDOWN_PADDING_RIGHT)
    BURNDOWN_WIDTH - BURNDOWN_PADDING_LEFT - padding_right
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
