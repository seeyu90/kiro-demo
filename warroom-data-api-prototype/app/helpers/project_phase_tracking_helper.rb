# 邏輯移植自 docs/js/project-phase-tracking.js，規則已在 static prototype
# （warroom-project-phase-tracking-static-prototype）三輪審閱定案，與資料來源（Notion／Sheets）
# 無關，故可在拿到真實資料存取權前先行完成（見 warroom-project-phase-tracking-real-source
# design.md 階段 7）。完全獨立實作，不與既有 ProjectHistoryHelper 共用程式碼（同既有慣例）。
#
# 甘特圖幾何方法一律加上 phase_ 前綴（phase_gantt_chart_*），刻意避開與 ProjectHistoryHelper
# 同名但簽名不同的 gantt_chart_domain／gantt_chart_svg_width／gantt_chart_x／
# gantt_chart_month_ticks／gantt_chart_today_x——Rails 預設 include_all_helpers 會把所有
# app/helpers/*.rb 混入同一個 view/helper context，同名方法會互相覆蓋，若不加前綴會讓其中一頁
# 的甘特圖在執行期靜默壞掉或丟出參數數量錯誤。
module ProjectPhaseTrackingHelper
  GANTT_ROW_HEIGHT = 42
  # 專案／議題名稱欄寬度。2026-08-25 使用者反饋「標題無法固定嗎？而且字被切掉了」：原本標籤是
  # 用 <text> 畫在 SVG 裡面，跟色塊共用同一個水平捲動區域，橫向捲動看後面月份時標籤會跟著被
  # 捲出畫面、卡在容器邊緣被裁切。改成標籤欄移到 SVG 外面，用獨立的 HTML 側欄
  # （.gantt-labels，position: sticky; left: 0）固定在可視區域左側，橫向捲動時只有 SVG 本體
  # （月份格線／色塊）會動，見 _overview_gantt.html.erb。
  GANTT_LABEL_WIDTH = 152
  # SVG 內部左邊留白：以前這個常數同時身兼「幫標籤欄留位置」與「色塊起點前的留白」兩個用途
  # （固定 152px）；標籤欄移出 SVG 後，SVG 內部不再需要幫標籤留大空間，只留一點點左邊界即可。
  GANTT_PADDING_LEFT = 12
  GANTT_PADDING_RIGHT = 16
  GANTT_PADDING_TOP = 28
  GANTT_PADDING_BOTTOM = 8
  GANTT_MIN_WIDTH = 900 # 需求 3.5：SVG 最小寬度
  # 原本沿用 static prototype 的 24（單一專案詳細頁用，只需要看幾週）；本頁是多專案橫向總覽，
  # 常態橫跨一整年甚至「全部年度」，24px/天在可視寬度內只塞得下 1〜2 個月，要一直橫向捲動
  # 才看得到下一個月（2026-08-25 使用者反饋「不能多顯示幾個月嗎」）。改成 8，同樣可視寬度下
  # 大約可看到 4〜5 個月。
  GANTT_PIXELS_PER_DAY = 8
  # 零工期色塊（例如開案當天就完成）clamp 後的最小寬度。原本是 2px：配上 .gantt-stage-block
  # 的 1px stroke（置中畫在邊界上，兩側各吃掉 0.5px）幾乎把整條 2px 寬的填色吃光，視覺上完全
  # 看不出色塊存在（2026-08-25 使用者反饋「LXPMS 的開案怎麼不見了」，實測資料其實都在，色塊
  # 幾何也算對了，純粹是細到肉眼／stroke 一起吃掉看不見）。改成 6px，扣掉 stroke 還留有清楚
  # 可辨識的實色寬度。
  GANTT_MIN_SEGMENT_WIDTH = 6

  # 雙軌設計（2026-08-25 使用者要求，比照既有 project_history 甘特圖「上面預計、下面實際」
  # 的既有慣例，見 ProjectHistoryHelper::GANTT_PLANNED_BAR_HEIGHT 等常數）：上軌＝預計時程
  # （較高，5 階段固定配色，不印文字標籤——階段名稱改由圖例辨識，色塊上只留 hover 提示，
  # 2026-08-25 使用者要求），下軌＝實際時程（較窄，只在有 actual_date 時才畫）。
  GANTT_PLANNED_BAR_HEIGHT = 18
  GANTT_BAR_GAP = 3
  GANTT_ACTUAL_BAR_HEIGHT = 8

  # ── 日期與完成狀態計算（清單／甘特圖共用，同 JS 版不變式：兩處皆呼叫本組方法，不得各自
  # 重新實作完成狀態或差異判斷邏輯） ──────────────────────────────

  # 對應 JS 版 parseDateOnly：僅接受嚴格 "YYYY-MM-DD"。Ruby Date 物件本身無時區概念，不需要
  # 手刻 JS 版靠 Date.UTC 避開的時區偏移問題，但仍須用 Date.iso8601 嚴格解析（不得用
  # Date.parse——Date.parse 對不合法格式的容錯行為與 Date.iso8601 不同，可能誤判格式錯誤的
  # 字串為合法日期）。格式不合法或缺失一律回傳 nil。
  def parse_date_only(date_str)
    return nil if date_str.blank?

    Date.iso8601(date_str.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def diff_days(actual_date, planned_date)
    actual = parse_date_only(actual_date)
    planned = parse_date_only(planned_date)
    return nil if actual.nil? || planned.nil?

    (actual - planned).to_i
  end

  # 依 planned_date／actual_date 兩欄位是否存在（parse_date_only 驗證通過視為存在）的組合判斷，
  # 回傳 { completion_label:, diff_days: }。與 JS 版 computeRowState 邏輯一致：actual_date 存在
  # （非 nil）即視為「已完成」，即使其格式不合法（資料合約禁止空字串，僅允許合法日期字串或
  # nil，故實務上不會發生），diff_days 由 diff_days() 自行對兩端做 nil-safe 判斷。
  def compute_row_state(planned_date, actual_date)
    has_planned = parse_date_only(planned_date).present?
    if actual_date.present?
      { completion_label: "已完成", diff_days: has_planned ? diff_days(actual_date, planned_date) : nil }
    else
      { completion_label: has_planned ? "未完成" : "—", diff_days: nil }
    end
  end

  # ── 甘特圖幾何 ──────────────────────────────────────────────
  #
  # rows 參數（phase_gantt_chart_domain）：呼叫端需先跨所有專案將階段列攤平成單一陣列，每筆
  # 至少含 :planned_date／:actual_date 鍵（比照 PHASE_RECORDS／stage row 慣例，鍵名對應
  # Notion「日期」「實際完成」欄位）。domain 為 { min_date:, max_date: }（Date 物件）。

  # min_date＝全體有效 planned_date 最小值；max_date＝（全體有效 actual_date 最大值、今日、
  # min_date）三者取最大值，兩端再各外推一個月（2026-08-25 使用者要求「甘特圖能不能多畫前後
  # 一個月」——資料範圍緊貼著圖表左右邊界時，第一筆／最後一筆色塊剛好卡在邊緣，看不出前後還有
  # 沒有更早／更晚的東西，外推一個月留一點餘裕）。找不到任何有效 planned_date 時回傳 nil
  # （需求 3.3 empty-state，外推前就短路，避免對不存在的日期做月份運算）。
  def phase_gantt_chart_domain(rows)
    planned_dates = rows.filter_map { |r| parse_date_only(r[:planned_date]) }
    return nil if planned_dates.empty?

    actual_dates = rows.filter_map { |r| parse_date_only(r[:actual_date]) }
    min_date = planned_dates.min
    max_date = (actual_dates + [ Date.current, min_date ]).max
    { min_date: min_date - 1.month, max_date: max_date + 1.month }
  end

  def phase_gantt_chart_svg_width(domain)
    days = (domain[:max_date] - domain[:min_date]).to_i
    needed = GANTT_PADDING_LEFT + GANTT_PADDING_RIGHT + days * GANTT_PIXELS_PER_DAY
    [ GANTT_MIN_WIDTH, needed ].max
  end

  def phase_gantt_chart_x(date, domain, width)
    span = [ (domain[:max_date] - domain[:min_date]).to_i, 1 ].max
    plot_width = width - GANTT_PADDING_LEFT - GANTT_PADDING_RIGHT
    GANTT_PADDING_LEFT + ((date - domain[:min_date]).to_f / span) * plot_width
  end

  # 月份時間軸格線＋標籤。min_date 通常不是當月 1 號，第一個刻度（該月 1 號）算出來的 x 座標
  # 可能小於 GANTT_PADDING_LEFT，clamp 在 [左邊界, 右邊界] 避免畫進專案列標籤欄。
  def phase_gantt_chart_month_ticks(domain, width)
    left = GANTT_PADDING_LEFT
    right = width - GANTT_PADDING_RIGHT

    ticks = []
    cursor = domain[:min_date].beginning_of_month
    while cursor <= domain[:max_date]
      x = phase_gantt_chart_x(cursor, domain, width).clamp(left, right)
      ticks << { x: x.round(2), label: cursor.strftime("%Y/%m") }
      cursor = cursor.next_month
    end
    ticks
  end

  def phase_gantt_chart_today_x(domain, width)
    phase_gantt_chart_x(Date.current, domain, width).round(2)
  end

  # 每個階段的「執行時間」在甘特圖上分兩軌畫（2026-08-25 使用者明確要求：「上面是預計時程下面
  # 是實際時程」，比照既有 project_history 甘特圖「預計／實際」雙軌慣例，但這裡改成依 5 個
  # STAGE_ORDER 階段分段上色＋印階段名稱，而非單一任務一條軌）：
  #
  # - 上軌（phase_gantt_chart_planned_segment）＝純粹按「預計」時程排：從上一個有資料階段的
  #   planned_date 銜接到這個階段自己的 planned_date，只要有 planned_date 就畫（不論這個階段
  #   完成與否），每個階段固定配色＋印階段名稱，呈現「整個計畫應該長怎樣」。
  # - 下軌（phase_gantt_chart_actual_segment）＝純粹按「實際」時程排：從上一個有 actual_date
  #   階段的 actual_date 銜接到這個階段自己的 actual_date，**只在這個階段已有 actual_date 時
  #   才畫**（還沒做完的階段下軌沒有東西可畫，這是刻意的——沒發生的事沒有「實際」時程），顏色
  #   依這個階段是否準時／延誤決定（比照既有 delay/early 語意），用來標出跟預計的落差。
  #
  # stages：單一卡片的完整 STAGE_ORDER 陣列（{ stage:, primary:, history: }，見
  # Sheets::FetchPhaseTracking#build_card），index：要畫的這個階段在陣列中的位置。

  def phase_gantt_chart_planned_segment(stages, index, domain, width)
    row = stages[index][:primary]
    return nil if row.nil?

    planned = parse_date_only(row[:planned_date])
    return nil if planned.nil?

    start_date = phase_gantt_chart_previous_boundary(stages, index, :planned_date) || planned
    x1 = phase_gantt_chart_x(start_date, domain, width)
    x2 = [ phase_gantt_chart_x(planned, domain, width), x1 + GANTT_MIN_SEGMENT_WIDTH ].max

    { x: x1.round(2), width: (x2 - x1).round(2), stage: stages[index][:stage] }
  end

  def phase_gantt_chart_actual_segment(stages, index, domain, width)
    row = stages[index][:primary]
    return nil if row.nil? || row[:actual_date].blank?

    actual = parse_date_only(row[:actual_date])
    return nil if actual.nil?

    start_date = phase_gantt_chart_previous_boundary(stages, index, :actual_date) || actual
    x1 = phase_gantt_chart_x(start_date, domain, width)
    x2 = [ phase_gantt_chart_x(actual, domain, width), x1 + GANTT_MIN_SEGMENT_WIDTH ].max

    # 圖例寫的是「準時／提前完成」＝綠色、「延誤完成」＝紅色（見 _gantt_legend.html.erb），
    # 準時（diff_days == 0）理當跟提前一樣算綠色——2026-08-25 使用者發現「開案是紅色延誤完成，
    # 不是相差 0 天嗎」：原本用 `.negative?` 判斷，只有嚴格小於 0 才算 :early，diff_days
    # 剛好等於 0（真正準時，不早不晚）會落到 else 分支被標成 :delayed，跟圖例文字自相矛盾。
    # 改成「不是正數就算準時／提前」，diff_days <= 0 才是唯一正確的「沒有延誤」判斷式。
    state = compute_row_state(row[:planned_date], row[:actual_date])
    variant = state[:diff_days].present? && !state[:diff_days].positive? ? :early : :delayed

    { x: x1.round(2), width: (x2 - x1).round(2), variant: variant, diff_days: state[:diff_days] }
  end

  # 由 index 往前找上一個「有主要記錄、且 date_key 這個日期欄位有值」的階段，回傳該日期
  # （中間跳過的階段——例如沒有任何記錄的「需求確認」，或還沒有 actual_date 的階段——視為不
  # 存在，不當作邊界）；一路往前都找不到時回傳 nil（呼叫端退回用自己的日期，色塊寬度為 0，
  # clamp 成最小可視寬度）。date_key 為 :planned_date 或 :actual_date，兩條軌分別只沿用同一
  # 種日期欄位銜接，不混用（上軌不會因為前一階段已完成就改用它的 actual_date，下軌也不會因為
  # 前一階段只有 planned_date 就拿來湊數）。
  def phase_gantt_chart_previous_boundary(stages, index, date_key)
    (index - 1).downto(0) do |i|
      previous_row = stages[i][:primary]
      next if previous_row.nil?

      boundary = parse_date_only(previous_row[date_key])
      return boundary if boundary
    end
    nil
  end

  # 每個階段固定一個分類色（跟完成狀態顏色是兩套獨立語意，不能共用 STATUS_TAG_CLASS：這裡是
  # 「這是哪個階段」，STATUS_TAG_CLASS 是「這個議題目前算不算完成」）。CSS class 用英文鍵名，
  # 中文階段名稱無法安全當 CSS class 使用。
  STAGE_BLOCK_CLASS = {
    "需求確認" => "gantt-stage-requirement",
    "開案" => "gantt-stage-kickoff",
    "開發" => "gantt-stage-development",
    "測試" => "gantt-stage-testing",
    "發布" => "gantt-stage-release"
  }.freeze

  def phase_gantt_chart_stage_class(stage_name)
    STAGE_BLOCK_CLASS.fetch(stage_name, "gantt-stage-requirement")
  end

  # ── 卡片標題（清單／甘特圖列標籤共用，新增，不是 JS 版移植過來的） ──────────────
  #
  # issue_name 只在 issue_id 是純 Redmine ID 時才會填（見 Sheets::FetchPhaseTracking），有值時
  # 兩者並列（名稱在前，ID 加括號在後，方便同時搜尋兩種寫法），空白時只顯示 issue_id。
  def phase_tracking_issue_label(card)
    card[:issue_name].present? ? "#{card[:issue_name]}（#{card[:issue_id]}）" : card[:issue_id]
  end

  # 狀態標籤配色（新增，2026-08-25 使用者反饋「配色字不夠明顯」——原本 5 種狀態全部共用同一個
  # .tag-status 藍色，掃卡片列表時分不出哪些真的需要注意）。三段式：完成／延誤已完成＝已完成
  # （綠色）；延誤未完成／未完成＝還在等待處理、需要注意（紅色，且加粗）；暫緩＝刻意擱置，不是
  # 「未完成」（見 ProjectPhaseTrackingController::INCOMPLETE_STATUSES 附註），視覺上刻意跟
  # 紅色的「需要注意」區分開來，用中性灰。未知狀態值（理論上不會發生，防禦性 fallback）維持
  # 原本的 .tag-status 藍色。
  STATUS_TAG_CLASS = {
    "完成" => "tag-status-done",
    "延誤已完成" => "tag-status-done",
    "延誤未完成" => "tag-status-pending",
    "未完成" => "tag-status-pending",
    "暫緩" => "tag-status-paused"
  }.freeze

  def phase_tracking_status_class(status)
    STATUS_TAG_CLASS.fetch(status, "tag-status")
  end
end
