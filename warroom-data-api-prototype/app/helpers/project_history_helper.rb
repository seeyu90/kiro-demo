module ProjectHistoryHelper
  # 「已消耗 / 預估」工時顯示：整數值不顯示多餘的 .0（34.0h → 34h，43.75h 這種有意義的小數
  # 維持原樣）；用固定寬度讓數字兩端對齊、"/" 固定在同一欄，不會因為每列位數不同而東倒西歪。
  #
  # 已消耗超過預估（超支）時整組數字變成警示色——「進度」欄的百分比 clamp 在 100%，議題早已
  # 完成時看不出「其實花了預估的 3 倍工時」這種真正該被注意的資訊，只有工時欄的原始數字才藏得
  # 住這個落差，故在這裡額外標示，不同花費比例的議題不會長得一樣。
  def hours_pair(consumed, estimated)
    return "—".html_safe if consumed.nil? || estimated.nil?

    overspent = estimated.to_f.positive? && consumed.to_f > estimated.to_f
    classes = [ "hours-pair" ]
    classes << "hours-pair-overspent" if overspent

    content_tag(:span, class: classes.join(" ")) do
      content_tag(:span, "#{format_hours(consumed)}h", class: "hours-num") +
        content_tag(:span, "/", class: "hours-sep") +
        content_tag(:span, "#{format_hours(estimated)}h", class: "hours-num")
    end
  end

  def format_hours(value)
    f = value.to_f
    (f == f.to_i ? f.to_i : f).to_s
  end

  # 邏輯移植自 docs/js/project-history-overview.js 的 renderGanttChart：X 軸依全部任務的
  # planned_completion_date／actual_completion_date（或今日）等比例縮放，每個專案一列，
  # 每個任務一個色塊；各自獨立實作，不與 JS 版共用程式碼（同既有 305/306/307 慣例）。
  # 最小寬度：時間跨度短（月份少）時的下限，避免圖太窄。實際寬度依月份數量計算（見
  # gantt_chart_svg_width），月份一多就變寬、靠外層 .gantt-scroll 容器左右捲動查看，不再靠
  # CSS width:100% 把所有月份硬擠進固定寬度（那樣會讓色塊被壓到看不出寬度差異，也導致「明明
  # 內容比較寬卻滑不動」——CSS 把 SVG 強制縮放去塞滿容器，沒有東西溢出，自然沒有捲動的必要）。
  GANTT_MIN_WIDTH = 720
  GANTT_MONTH_PX = 90
  GANTT_ROW_HEIGHT = 42
  # 專案列標籤欄寬度：字級加大後（見 CSS .gantt-row-label）留寬一點，避免「亞炬 Platform」這種
  # 較長的專案名稱被壓到跟時間軸格線重疊。
  GANTT_PADDING_LEFT = 152
  GANTT_PADDING_RIGHT = 16
  # 頂部留白給月份時間軸標籤（水平呈現在第一列的正上方，使用者要求時間軸放在上方，比照參考圖
  # 的版面配置，而不是既有 trend chart 那種畫在底部、旋轉 -45 度的做法）。
  GANTT_PADDING_TOP = 28
  GANTT_PADDING_BOTTOM = 8

  # 每個任務畫成「預計」「實際」上下兩條窄條（比照使用者提供的參考圖：預計＝規劃時程，
  # 實際＝依準時／逾期上色，並疊加工時消耗比例的填色）。兩條窄條中間留小間距，合計仍在單一
  # GANTT_ROW_HEIGHT 列高的可畫區域內（列高 42、扣掉上下 8px 留白＝26px 可用，兩條窄條各 10px
  # ＋ 3px 間距＝23px，足夠）。
  GANTT_PLANNED_BAR_HEIGHT = 10
  GANTT_BAR_GAP = 3
  GANTT_ACTUAL_BAR_HEIGHT = 10

  def gantt_chart_domain(rows)
    dates = rows.flat_map { |r| r[:tasks] }
                .flat_map { |t| [ t[:start_date], t[:due_date] ] }
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

  # 每個月至少留 GANTT_MONTH_PX 寬度，月份數愈多、圖愈寬（不是硬塞進固定寬度）；
  # 至少維持 GANTT_MIN_WIDTH，避免時間跨度很短時圖太窄。只算月份數、不呼叫
  # gantt_chart_month_ticks（那個方法要靠 gantt_chart_x 算座標，而 gantt_chart_x 又要靠這個
  # 方法算出的寬度才能算座標——避免循環呼叫）。
  def gantt_chart_svg_width(min_date, max_date)
    needed = GANTT_PADDING_LEFT + GANTT_PADDING_RIGHT + gantt_chart_month_count(min_date, max_date) * GANTT_MONTH_PX
    [ GANTT_MIN_WIDTH, needed ].max
  end

  def gantt_chart_month_count(min_date, max_date)
    count = 0
    cursor = min_date.beginning_of_month
    while cursor <= max_date
      count += 1
      cursor = cursor.next_month
    end
    count
  end

  # 月份時間軸格線＋標籤：讓甘特圖有座標可以參考現在看的是哪個月份，而不是一排沒有刻度的
  # 浮動色塊。以月為單位而非週（52 週的標籤會太密擠成一團看不清楚），格線本身仍細到能看出
  # 每個色塊落在哪個時間點附近。
  #
  # min_date 通常不是當月 1 號（例如某議題 3/15 開案，min_date 就是 3/15），但這裡刻意從
  # 「min_date 所在月份的 1 號」開始畫格線，讓月份標籤對齊完整月份、不是從資料剛好開始的那天
  # 算起的畸零日期。這代表第一個刻度（該月 1 號）本身可能早於 min_date，算出來的 x 座標會
  # 小於 GANTT_PADDING_LEFT（畫布上專案列標籤欄的右邊界），沒有 clamp 的話格線與標籤會畫到
  # 標籤欄裡面、蓋住專案名稱。故 clamp 在 [GANTT_PADDING_LEFT, 右邊界] 之間，格線視覺上對齊
  # 繪圖區左緣，標籤文字內容仍是正確的月份，只是不會畫出繪圖區以外。
  def gantt_chart_month_ticks(min_date, max_date)
    left = GANTT_PADDING_LEFT
    right = gantt_chart_svg_width(min_date, max_date) - GANTT_PADDING_RIGHT

    ticks = []
    cursor = min_date.beginning_of_month
    while cursor <= max_date
      x = gantt_chart_x(cursor.iso8601, min_date, max_date).clamp(left, right)
      ticks << { x: x.round(2), label: cursor.strftime("%Y/%m") }
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

  # 「預計」條＝ start_date～due_date（規劃時程，不受完成狀態影響）。「實際」條右界：已完成用
  # due_date（307 無「實際完成日」欄位，見 design.md 決策）；未完成時取 due_date 與今日兩者較晚
  # 者——尚未到期維持顯示到 due_date，已逾期則延伸到今日呈現「拖了多久」。「實際」條依是否逾期
  # 上色（準時＝綠、逾期未完成＝紅），並疊加工時消耗比例的填色（需求 2）。
  def gantt_chart_task_rect(task, min_date, max_date)
    x1 = gantt_chart_x(task[:start_date], min_date, max_date)
    return nil if x1.nil?

    due_d = parse_gantt_date(task[:due_date])

    planned_end = task[:due_date].presence || Date.current.iso8601
    planned_x2 = [ gantt_chart_x(planned_end, min_date, max_date) || x1, x1 + 4 ].max

    overdue = !task[:done] && due_d.present? && due_d < Date.current
    actual_end =
      if task[:done] || due_d.nil?
        task[:due_date].presence || Date.current.iso8601
      else
        [ due_d, Date.current ].max.iso8601
      end
    actual_x2 = [ gantt_chart_x(actual_end, min_date, max_date) || x1, x1 + 4 ].max
    actual_width = actual_x2 - x1

    {
      x: x1.round(2),
      planned_width: (planned_x2 - x1).round(2),
      actual_width: actual_width.round(2),
      fill_width: (actual_width * duration_fill_ratio(task)).round(2),
      done: !!task[:done],
      overdue: overdue,
      title: duration_task_title(task)
    }
  end

  # 已消耗人時／預估人時 clamp 至 0~1；consumed_hours 為 nil（該議題無 actual_series 資料）或
  # estimated_hours 為 0 時回傳 0，不填色（需求 2.2）。
  def duration_fill_ratio(task)
    estimated = task[:estimated_hours].to_f
    consumed = task[:consumed_hours]
    return 0.0 if consumed.nil? || estimated <= 0

    (consumed.to_f / estimated).clamp(0.0, 1.0)
  end

  def duration_task_title(task)
    hours_note = task[:consumed_hours] ? "#{task[:consumed_hours]}h／#{task[:estimated_hours]}h" : "工時資料不足"
    "#{task[:task_name]}（#{task[:done] ? '已完成' : '進行中'}）" \
      "#{gantt_chart_short_date(task[:start_date])} ～ #{gantt_chart_short_date(task[:due_date])}｜#{hours_note}"
  end

  private

  def gantt_chart_x(date_str, min_date, max_date)
    date = parse_gantt_date(date_str)
    return nil if date.nil?

    span = [ (max_date - min_date).to_f, 1.0 ].max
    GANTT_PADDING_LEFT + ((date - min_date).to_f / span) * gantt_chart_plot_width(min_date, max_date)
  end

  def gantt_chart_plot_width(min_date, max_date)
    gantt_chart_svg_width(min_date, max_date) - GANTT_PADDING_LEFT - GANTT_PADDING_RIGHT
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
