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

  # 「議題資料」分頁目前的篩選狀態，供快捷篩選 Tag 這類需要手動組 issues_path(...) 的連結共用
  # （分頁連結不需要這個——Pagy 直接沿用當前請求的 query params，見 index.html.erb），
  # 避免同一組 project／status／q／type／month／breakdown_sort／breakdown_dir 在多處各自重複。
  def issue_filter_params(overrides = {})
    {
      tab: "detail", project: @selected_project, status: @selected_status, q: @selected_q,
      type: @selected_type, month: @selected_month, breakdown_sort: @breakdown_sort,
      breakdown_dir: @breakdown_dir
    }.merge(overrides)
  end

  # 「是否已完成」直接引用 Actor 的 ISSUE_DONE_STATUS_PATTERN（而不是自己另外寫一份關鍵字），
  # 確保 badge 顏色、KPI 卡片、時程欄位的「是否已完成」判斷永遠是同一套規則，不會改一邊忘了
  # 改另一邊。
  def issue_done_status?(status)
    status.to_s.match?(Sheets::FetchIssueDashboard::ISSUE_DONE_STATUS_PATTERN)
  end

  # 「狀態」欄位是自由輸入的中文文字（來源是 Redmine，可能出現「新建立」「處理中」「已確認」
  # 「已解決」「已關閉」「已結束」等各種寫法），無法窮舉每一種可能值，改用關鍵字比對決定 badge
  # 顏色；純文字狀態塞進表格窄欄位、沒有 white-space:nowrap 時，中文字會逐字換行變成直排
  # （例如「新建立」被拆成三行），包成這個 badge span 就解決了。
  def issue_status_badge_class(status)
    if issue_done_status?(status)
      "issue-status-done"
    elsif status.to_s.match?(/處理|進行/)
      "issue-status-processing"
    elsif status.to_s.match?(/新建|新增/)
      "issue-status-new"
    else
      "issue-status-other"
    end
  end

  # 「開始／到期／工作天數」三個原本各自獨立的欄位合併成一個「時程與天數」欄位：日期只顯示
  # 月-日（同一頁不會橫跨太多年份，年份對這個窄欄位幫助不大，省下的寬度留給後面的天數）；
  # 沒填到期日時，議題還在進行中就顯示「進行中」（不是「未指定」——議題本來就還沒結束，
  # 不是資料缺漏，「未指定」這個詞聽起來像漏填東西，容易誤會），只有議題已完成卻沒填到期日
  # 這種真正的缺漏情況，才顯示「未指定」。有工作天數（來源試算表既有欄位）就附註「工作 N
  # 天」，避免合併欄位把原本三欄各自顯示的工作天數資料漏掉；沒填工作天數、到期日也還沒到
  # （議題仍進行中）時，才退而求其次附註「已開 N 天」（今天跟開始日期的差）。開始日期也缺就
  # 顯示 —。
  def issue_timeline_label(issue)
    start_text = issue[:start_date].presence
    return "—" if start_text.nil?

    range =
      if issue[:due_date].present?
        "#{short_date(start_text)} ~ #{short_date(issue[:due_date])}"
      else
        end_label = issue_done_status?(issue[:status]) ? "未指定" : "進行中"
        "#{short_date(start_text)} ~ #{end_label}"
      end

    note = issue_timeline_note(issue)
    note ? "#{range}（#{note}）" : range
  end

  def issue_open_days(start_date_str)
    (Date.current - Date.parse(start_date_str)).to_i
  rescue ArgumentError, TypeError
    nil
  end

  def issue_timeline_note(issue)
    return "工作 #{issue[:work_days]} 天" if issue[:work_days].present?
    return nil if issue[:due_date].present?

    days = issue_open_days(issue[:start_date])
    days ? "已開 #{days} 天" : nil
  end

  # 開始／到期日已經是 normalize_date 產出的 YYYY-MM-DD（若來源格式無法辨識則原樣保留），
  # 只在確實是這個格式時才去掉年份，非標準格式的原始字串不動，避免截錯欄位。
  def short_date(date_str)
    date_str.to_s.sub(/\A\d{4}-(\d{2}-\d{2})\z/, '\1')
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
