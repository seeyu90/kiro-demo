module ProjectHistoryHelper
  # 邏輯移植自 docs/js/project-history-overview.js 的 renderGanttChart：X 軸依全部任務的
  # planned_completion_date／actual_completion_date（或今日）等比例縮放，每個專案一列，
  # 每個任務一個色塊；各自獨立實作，不與 JS 版共用程式碼（同既有 305/306/307 慣例）。
  GANTT_WIDTH = 720
  GANTT_ROW_HEIGHT = 42
  GANTT_PADDING_LEFT = 140
  GANTT_PADDING_RIGHT = 16
  GANTT_PADDING_TOP = 16
  # 底部留白給月份時間軸標籤（旋轉呈現，比照 trend chart 既有的 -45 度做法）。
  GANTT_PADDING_BOTTOM = 40

  def gantt_chart_domain(rows)
    dates = rows.flat_map { |r| r[:tasks] }
                .flat_map { |t| [ t[:planned_completion_date], t[:actual_completion_date] ] }
                .filter_map { |d| parse_gantt_date(d) }
    all = dates + [ Date.current ]
    [ all.min, all.max ]
  end

  def gantt_chart_height(rows)
    GANTT_PADDING_TOP + rows.length * GANTT_ROW_HEIGHT + GANTT_PADDING_BOTTOM
  end

  def gantt_chart_row_y(index)
    GANTT_PADDING_TOP + index * GANTT_ROW_HEIGHT
  end

  def gantt_chart_rows_bottom(rows)
    GANTT_PADDING_TOP + rows.length * GANTT_ROW_HEIGHT
  end

  # 月份時間軸格線＋標籤：讓甘特圖有座標可以參考現在看的是哪個月份，而不是一排沒有刻度的
  # 浮動色塊。以月為單位而非週（52 週的標籤會太密擠成一團看不清楚），格線本身仍細到能看出
  # 每個色塊落在哪個時間點附近。
  def gantt_chart_month_ticks(min_date, max_date)
    ticks = []
    cursor = min_date.beginning_of_month
    while cursor <= max_date
      ticks << { x: gantt_chart_x(cursor.iso8601, min_date, max_date).round(2), label: cursor.strftime("%Y/%m") }
      cursor = cursor.next_month
    end
    ticks
  end

  # 「今天」參考線：一眼看出目前進度落在時間軸的哪個位置。
  def gantt_chart_today_x(min_date, max_date)
    gantt_chart_x(Date.current.iso8601, min_date, max_date)&.round(2)
  end

  # IssuesHelper 的 trend_chart_* 方法只依賴 record 的 :date／:total 兩個鍵；花費工時／測試問題
  # 趨勢的來源鍵名不同（:hours／:count），轉換成 :total 鍵即可直接重用該組方法，不需重寫座標計算。
  def to_trend_records(series, value_key)
    series.map { |point| { date: point[:date], total: point[value_key] } }
  end

  def gantt_chart_task_rect(task, min_date, max_date)
    x1 = gantt_chart_x(task[:planned_completion_date], min_date, max_date)
    return nil if x1.nil?

    end_date = task[:actual_completion_date].presence || Date.current.iso8601
    x2 = gantt_chart_x(end_date, min_date, max_date) || x1
    x2 = [ x2, x1 + 4 ].max

    {
      x: x1.round(2), width: (x2 - x1).round(2),
      done: task[:actual_completion_date].present?,
      title: "#{task[:task_name]}（#{task[:status]}）#{gantt_chart_short_date(task[:planned_completion_date])} ～ " \
             "#{task[:actual_completion_date].present? ? gantt_chart_short_date(task[:actual_completion_date]) : '進行中'}"
    }
  end

  private

  def gantt_chart_x(date_str, min_date, max_date)
    date = parse_gantt_date(date_str)
    return nil if date.nil?

    span = [ (max_date - min_date).to_f, 1.0 ].max
    GANTT_PADDING_LEFT + ((date - min_date).to_f / span) * gantt_chart_plot_width
  end

  def gantt_chart_plot_width
    GANTT_WIDTH - GANTT_PADDING_LEFT - GANTT_PADDING_RIGHT
  end

  def parse_gantt_date(date_str)
    return nil if date_str.blank?

    Date.parse(date_str.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def gantt_chart_short_date(date_str)
    parts = date_str.to_s.split("-")
    parts.size == 3 ? "#{parts[1]}/#{parts[2]}" : date_str.to_s
  end
end
