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

  # 「狀態」欄位是自由輸入的中文文字（來源是 Redmine，可能出現「新建立」「處理中」「已確認」
  # 「已解決」「已關閉」等各種寫法），無法窮舉每一種可能值，改用關鍵字比對決定 badge 顏色；
  # 純文字狀態塞進表格窄欄位、沒有 white-space:nowrap 時，中文字會逐字換行變成直排
  # （例如「新建立」被拆成三行），包成這個 badge span 就解決了。
  def issue_status_badge_class(status)
    text = status.to_s
    if text.match?(/完成|確認|關閉|解決/)
      "issue-status-done"
    elsif text.match?(/處理|進行/)
      "issue-status-processing"
    elsif text.match?(/新建|新增/)
      "issue-status-new"
    else
      "issue-status-other"
    end
  end

  # 「開始／到期／工作天數」三個原本各自獨立的欄位合併成一個「時程與天數」欄位：有到期日
  # 就顯示「開始 ~ 到期」，沒有到期日（議題還在進行、沒填預計完成日）就顯示「開始 ~
  # 未指定（已開 N 天）」，N 用今天跟開始日期的差算出來；開始日期也缺就顯示 —（比起原本
  # 三欄各自顯示「—」，這個合併欄位對「沒填日期」的情況一次講清楚，不用同時看三個空欄位）。
  def issue_timeline_label(issue)
    start_text = issue[:start_date].presence
    return "—" if start_text.nil?

    return "#{start_text} ~ #{issue[:due_date]}" if issue[:due_date].present?

    days = issue_open_days(start_text)
    days ? "#{start_text} ~ 未指定（已開 #{days} 天）" : "#{start_text} ~ 未指定"
  end

  def issue_open_days(start_date_str)
    (Date.current - Date.parse(start_date_str)).to_i
  rescue ArgumentError, TypeError
    nil
  end

  # 依專案分類表格的可排序欄位標題連結：同一欄位再次點選時反轉方向，切換到不同欄位時預設降冪
  # （筆數統計通常最關心「最多」的專案）；連結保留目前所選月份，並固定停留在「統計摘要」分頁籤。
  # 同時帶入 project／status，因為這也是一個不含這兩個 query params 的 GET 請求，若不帶入，
  # 點擊排序連結會把「議題資料」分頁目前的篩選值重設為預設值（與兩個表單各自獨立的設計意圖牴觸）。
  def breakdown_sort_link(key, label)
    active = @breakdown_sort == key.to_s
    next_dir = active && @breakdown_dir == "desc" ? "asc" : "desc"
    indicator = active ? (@breakdown_dir == "desc" ? " ▼" : " ▲") : ""

    link_to label + indicator,
             issues_path(month: @selected_month, tab: "stats", breakdown_sort: key, breakdown_dir: next_dir,
                          project: @selected_project, status: @selected_status),
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
