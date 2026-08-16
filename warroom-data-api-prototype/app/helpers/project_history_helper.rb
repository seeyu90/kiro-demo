module ProjectHistoryHelper
  # 邏輯移植自 docs/js/project-history-overview.js 的 renderGanttChart：X 軸依全部任務的
  # planned_completion_date／actual_completion_date（或今日）等比例縮放，每個專案一列，
  # 每個任務一個色塊；各自獨立實作，不與 JS 版共用程式碼（同既有 305/306/307 慣例）。
  GANTT_WIDTH = 720
  GANTT_ROW_HEIGHT = 42
  GANTT_PADDING_LEFT = 140
  GANTT_PADDING_RIGHT = 16
  GANTT_PADDING_TOP = 16

  def gantt_chart_domain(rows)
    dates = rows.flat_map { |r| r[:tasks] }
                .flat_map { |t| [ t[:planned_completion_date], t[:actual_completion_date] ] }
                .filter_map { |d| parse_gantt_date(d) }
    all = dates + [ Date.current ]
    [ all.min, all.max ]
  end

  def gantt_chart_height(rows)
    GANTT_PADDING_TOP + rows.length * GANTT_ROW_HEIGHT + 30
  end

  def gantt_chart_row_y(index)
    GANTT_PADDING_TOP + index * GANTT_ROW_HEIGHT
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
