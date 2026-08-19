(function () {
  "use strict";

  // ── 模擬資料 ──────────────────────────────────────────────
  // 欄位對齊真實 306 試算表（306_臭蟲議題紀錄）分頁結構：
  // month_kpi / daily_kpi / raw_2023~raw_2026（合併為 ISSUES）。
  // 試算表另有工程師負載表／專案清單表分頁，本頁面不呈現這兩者。
  // 本頁面為靜態 prototype，全部資料為模擬資料，不呼叫任何 API。

  var MONTH_KPI = [
    { year_month: "2026-06", complaint: 34, testing: 8, total_bug: 42, block_rate: 19.05, completed: 5, unresolved: 1, avg_days: 1.88, sla_rate: 11.76 },
    { year_month: "2026-07", complaint: 28, testing: 7, total_bug: 35, block_rate: 20.00, completed: 10, unresolved: 7, avg_days: 2.61, sla_rate: 10.71 },
    { year_month: "2026-08", complaint: 15, testing: 9, total_bug: 24, block_rate: 37.50, completed: 6, unresolved: 3, avg_days: 3.10, sla_rate: 25.00 }
  ];

  // type 欄位對應歸屬責任：Complaint（客訴）＝專案共同責任，TestingBug（測試）＝個人責任，
  // 其餘（Other）歸屬待釐清，暫列為「其他」。負責人（assigned_to）不作為分類主軸，
  // 專案才是本頁面統計與檢視的分類主軸。
  var ATTRIBUTION_LABELS = { Complaint: "專案共同責任", TestingBug: "個人責任" };
  var ATTRIBUTION_CLASSES = { Complaint: "attribution-shared", TestingBug: "attribution-individual" };

  function attributionLabel(type) {
    return ATTRIBUTION_LABELS[type] || "其他";
  }

  function attributionClass(type) {
    return ATTRIBUTION_CLASSES[type] || "attribution-other";
  }

  var DAILY_KPI = [
    { date: "2026-07-10", complaint: 2, testing: 1, other: 0, total: 3 },
    { date: "2026-07-22", complaint: 0, testing: 3, other: 0, total: 3 },
    { date: "2026-08-01", complaint: 0, testing: 1, other: 0, total: 1 },
    { date: "2026-08-04", complaint: 4, testing: 0, other: 0, total: 4 },
    { date: "2026-08-06", complaint: 0, testing: 2, other: 0, total: 2 },
    { date: "2026-08-08", complaint: 1, testing: 4, other: 0, total: 5 },
    { date: "2026-08-11", complaint: 0, testing: 4, other: 0, total: 4 },
    { date: "2026-08-12", complaint: 1, testing: 0, other: 0, total: 1 },
    { date: "2026-08-13", complaint: 0, testing: 0, other: 0, total: 0 }
  ];

  // 依「現在」往前推 N 天，回傳 YYYY-MM-DD：用於新增的兩筆客訴範例（見下方 B-1/B-2），
  // 讓「緊急客訴（客訴＋已逾期）」KPI 卡片跟 SLA 判斷不管什麼時候開這個靜態頁面都能正確
  // 展示出來，不像其餘固定日期的範例列會隨時間過去而逐漸「看起來過期」（沿用本檔既有的
  // currentYearMonth()／burndown.js 的 issueInProgress() 同一種取捨：這份純前端展示本來
  // 就用瀏覽器當下時間，不是固定某個時間點）。
  function daysAgoISO(n) {
    var d = new Date();
    d.setDate(d.getDate() - n);
    return d.toISOString().slice(0, 10);
  }

  // 原始資料模擬 raw_2023~raw_2026 分頁：tracker 欄位值包含「臭蟲」與「測試」，「測試」為測試性質
  // 議題（非真實缺陷），不列入品質相關統計與呈現，故載入後立即整批過濾掉，不進入本頁面任何區塊
  // （KPI 摘要、每日趨勢、依專案分類統計、議題明細清單）。total_hours（花費時間）比照真實
  // 試算表 L 欄。
  var RAW_ISSUE_ROWS = [
    { issue_id: 4547, subject: "[客訴] 未匯入 2026 行事曆", type: "Complaint", tracker: "臭蟲", status: "已結束", assigned_to: "黃靖益", start_date: "2026-01-02", due_date: "2026-01-06", work_days: 3, project: "Virtuous HRM", total_hours: 0.75 },
    { issue_id: 4884, subject: "[測試] 按離職結算，出現伺服器錯誤", type: "TestingBug", tracker: "臭蟲", status: "已結束", assigned_to: "黃靖益", start_date: "2026-05-18", due_date: null, work_days: null, project: "Virtuous HRM", total_hours: 2 },
    { issue_id: 5160, subject: "[客訴] A3原料發貨異常", type: "Complaint", tracker: "臭蟲", status: "已解決", assigned_to: "王贊勛", start_date: "2026-08-11", due_date: "2026-08-11", work_days: 0, project: "JZN 舊振南智慧工廠", total_hours: 1.5 },
    { issue_id: 5165, subject: "[測試] Cloud Admin 申請白名單 申請時間錯誤", type: "TestingBug", tracker: "臭蟲", status: "新建立", assigned_to: "蔡秉逸", start_date: "2026-08-12", due_date: null, work_days: null, project: "Virtuous HRM", total_hours: null },
    { issue_id: 3058, subject: "[PMS] 結案小工序DeadlockVictim", type: "Other", tracker: "臭蟲", status: "已暫停", assigned_to: "王贊勛", start_date: "2024-04-29", due_date: null, work_days: null, project: "AG 亞炬", total_hours: null },
    { issue_id: 4301, subject: "[客訴] QC登入後會出現無權限使用此功能的跳窗", type: "Complaint", tracker: "臭蟲", status: "已結束", assigned_to: "王贊勛", start_date: "2025-09-03", due_date: "2026-01-30", work_days: 108, project: "JieZhou 傑宙", total_hours: 14 },
    { issue_id: 5170, subject: "[測試] 測試環境資料回填驗證", type: "TestingBug", tracker: "測試", status: "新建立", assigned_to: "蔡秉逸", start_date: "2026-08-13", due_date: null, work_days: null, project: "Virtuous HRM", total_hours: null },
    // 沒填到期日的客訴：一筆超過兩天 SLA（示範「緊急客訴」判定＋逾期計入），一筆還在兩天內
    // （示範還不算緊急、時程欄位顯示「進行中」）——對應真實使用情境：使用者截圖看到好幾筆
    // 客訴開了十幾天卻「緊急客訴」顯示 0，才發現這些客訴根本沒填到期日。
    { issue_id: 5201, subject: "[客訴] 訂單同步延遲", type: "Complaint", tracker: "臭蟲", status: "處理中", assigned_to: "陳筱涵", start_date: daysAgoISO(5), due_date: null, work_days: null, project: "AG 亞炬", total_hours: 0 },
    { issue_id: 5202, subject: "[客訴] 通知信未寄出", type: "Complaint", tracker: "臭蟲", status: "新建立", assigned_to: "王贊勛", start_date: daysAgoISO(1), due_date: null, work_days: null, project: "JZN 舊振南智慧工廠", total_hours: 0 }
  ];

  var ISSUES = RAW_ISSUE_ROWS.filter(function (issue) { return issue.tracker !== "測試"; });

  // 「是否已完成」關鍵字比對，badge 顏色（issueStatusBadgeClass）與 KPI 卡片（isIssueDone）
  // 共用同一個 regex，才不會發生「這筆議題 KPI 算完成、badge 卻顯示未分類顏色」的不一致
  // （比照 Rails Sheets::FetchIssueDashboard::ISSUE_DONE_STATUS_PATTERN／
  // IssuesHelper#issue_status_badge_class 的取捨）。
  var ISSUE_DONE_STATUS_PATTERN = /完成|確認|關閉|解決|結束/;

  function isIssueDone(status) {
    return ISSUE_DONE_STATUS_PATTERN.test(String(status));
  }

  function issueStatusBadgeClass(status) {
    var text = String(status);
    if (isIssueDone(text)) return "issue-status-done";
    if (/處理|進行/.test(text)) return "issue-status-processing";
    if (/新建|新增/.test(text)) return "issue-status-new";
    return "issue-status-other";
  }

  // 開始／到期日已經是 YYYY-MM-DD，只在確實是這個格式時才去掉年份（同一頁不會橫跨太多
  // 年份，年份對這個窄欄位幫助不大）。
  function timelineShortDate(dateStrForTimeline) {
    var m = /^\d{4}-(\d{2}-\d{2})$/.exec(String(dateStrForTimeline));
    return m ? m[1] : dateStrForTimeline;
  }

  function issueOpenDays(startDateStr) {
    var start = new Date(startDateStr);
    if (isNaN(start.getTime())) return null;
    var diffMs = Date.now() - start.getTime();
    return Math.floor(diffMs / (24 * 60 * 60 * 1000));
  }

  // 「開始／到期／工作天數」合併成一欄：有工作天數（來源試算表既有欄位）就附註「工作 N
  // 天」；沒填工作天數、也還沒到期時，退而求其次附註「已開 N 天」。沒有到期日時的呈現字眼：
  // 議題還在進行中顯示「進行中」，只有議題本身已完成卻沒填到期日這種真正的資料缺漏，才
  // 顯示「未指定」（比照 Rails IssuesHelper#issue_timeline_label／#issue_done_status?）。
  function issueTimelineLabel(issue) {
    if (!issue.start_date) return "—";

    var range;
    if (issue.due_date) {
      range = timelineShortDate(issue.start_date) + " ~ " + timelineShortDate(issue.due_date);
    } else {
      range = timelineShortDate(issue.start_date) + " ~ " + (isIssueDone(issue.status) ? "未指定" : "進行中");
    }

    var note = null;
    if (issue.work_days !== null && issue.work_days !== undefined) {
      note = "工作 " + issue.work_days + " 天";
    } else if (!issue.due_date) {
      var days = issueOpenDays(issue.start_date);
      if (days !== null) note = "已開 " + days + " 天";
    }

    return note ? range + "（" + note + "）" : range;
  }

  // 沒填到期日時的內建 SLA（依 type 而定，天數是從開始日算起「最晚應完成」的期限）：客訴
  // 兩天內要完成、測試（TestingBug／個人責任）當天要完成，其餘類型沒有對應 SLA（比照 Rails
  // Sheets::FetchIssueDashboard::ISSUE_SLA_DAYS）。
  var ISSUE_SLA_DAYS = { Complaint: 2, TestingBug: 0 };

  function issueOverdue(issue) {
    // 用 "YYYY-MM-DD" 字串本身做字典序比較，不經過 Date 物件，避開 new Date(str) 以 UTC
    // 解析、但今天的日期是本地時區這種時區不一致造成的誤判空間。
    if (issue.due_date) {
      return issue.due_date < todayLocalDateString();
    }
    var slaDays = ISSUE_SLA_DAYS[issue.type];
    if (slaDays === undefined || !issue.start_date) return false;
    var deadline = addDaysToDateString(issue.start_date, slaDays);
    return deadline !== null && deadline < todayLocalDateString();
  }

  function todayLocalDateString() {
    return dateToLocalDateString(new Date());
  }

  function addDaysToDateString(dateStr, days) {
    var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(dateStr);
    if (!m) return null;
    var d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
    if (isNaN(d.getTime())) return null;
    d.setDate(d.getDate() + days);
    return dateToLocalDateString(d);
  }

  function dateToLocalDateString(d) {
    var y = d.getFullYear();
    var m = String(d.getMonth() + 1).padStart(2, "0");
    var day = String(d.getDate()).padStart(2, "0");
    return y + "-" + m + "-" + day;
  }

  // KPI 卡片：待處理議題（未完成）／緊急客訴（未完成的客訴且已逾期）／累積總花費工時
  // （不限完成與否，投入成本）／逾期或未定到期日（未完成且到期日已過，或沒填到期日、也沒有
  // 對應 SLA 可判斷）。比照 Rails Sheets::FetchIssueDashboard#compute_issue_kpis。
  function computeIssueKpis(issues) {
    var pending = issues.filter(function (i) { return !isIssueDone(i.status); });
    var urgentCount = 0;
    var overdueOrUndatedCount = 0;

    pending.forEach(function (i) {
      var overdue = issueOverdue(i);
      var undated = !i.due_date && !(i.type in ISSUE_SLA_DAYS);
      if (i.type === "Complaint" && overdue) urgentCount += 1;
      if (undated || overdue) overdueOrUndatedCount += 1;
    });

    var totalHoursSum = issues.reduce(function (sum, i) { return sum + (Number(i.total_hours) || 0); }, 0);

    return {
      pending: pending.length,
      urgent_complaints: urgentCount,
      overdue_or_undated: overdueOrUndatedCount,
      total_hours_sum: Math.round(totalHoursSum * 100) / 100
    };
  }

  // ── 篩選狀態 ──────────────────────────────────────────────

  // 預設篩選：全部專案 + 狀態「新建立」，聚焦最需要處理的新進議題。
  // breakdownSort：依專案分類表格目前的排序欄位／方向，key 為 null 時維持原始（依專案分組）順序。
  // q／type：議題資料分頁的搜尋框與快捷篩選（只看客訴）；page：表格目前頁碼（1 起算）。
  var state = {
    issueFilters: { project: null, status: "新建立", q: "", type: null },
    breakdownSort: { key: null, dir: -1 },
    page: 1
  };

  var ISSUE_PAGE_SIZE = 15;

  // ── 共用輔助 ──────────────────────────────────────────────

  function formatValue(value) {
    if (value === null || value === undefined || value === "") {
      return "—";
    }
    return String(value);
  }

  function uniqueValues(records, key) {
    var values = [];
    records.forEach(function (r) {
      if (values.indexOf(r[key]) === -1) values.push(r[key]);
    });
    return values;
  }

  // ── KPI 摘要卡片 ──────────────────────────────────────────

  // 依瀏覽器當地時間取得「今天」所屬月份（YYYY-MM），用於將進行中的當月納入月份選單，
  // 即使 MONTH_KPI（月結資料）尚未有該月份的列（見需求 2.7）。
  function currentYearMonth() {
    var d = new Date();
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0");
  }

  function populateMonthSelect() {
    var select = document.getElementById("month-select");
    var months = MONTH_KPI.map(function (m) { return m.year_month; });
    var current = currentYearMonth();
    if (months.indexOf(current) === -1) months.push(current);
    months.sort();

    months.forEach(function (yearMonth) {
      var option = document.createElement("option");
      option.value = yearMonth;
      option.textContent = yearMonth;
      select.appendChild(option);
    });
    // 預設仍選中最新「已結算」月份（MONTH_KPI 最後一筆），而非進行中的當月，
    // 確保頁面載入時直接看到有意義的月結數字（需求 2.2）。
    select.value = MONTH_KPI[MONTH_KPI.length - 1].year_month;

    select.addEventListener("change", function () {
      renderStatsTab(select.value);
    });
  }

  // 「統計摘要」分頁籤內三個區塊（月度 KPI／每日趨勢／依專案分類）皆依所選月份呈現，
  // 統一由此函式驅動，確保切換月份時三者同步更新。
  function renderStatsTab(yearMonth) {
    var monthRecord = MONTH_KPI.filter(function (m) { return m.year_month === yearMonth; })[0];
    renderKpiCards(monthRecord);
    renderTrendChart(DAILY_KPI.filter(function (r) { return sameMonth(r.date, yearMonth); }));
    renderProjectBreakdown(ISSUES.filter(function (i) { return sameMonth(i.start_date, yearMonth); }));
  }

  // 以議題／每日紀錄的日期欄位前 7 碼（YYYY-MM）判斷是否屬於所選月份。
  function sameMonth(dateStr, yearMonth) {
    return typeof dateStr === "string" && dateStr.slice(0, 7) === yearMonth;
  }

  function renderKpiCards(monthRecord) {
    var el = document.getElementById("kpi-cards");
    el.innerHTML = "";

    if (!monthRecord) {
      var pending = document.createElement("p");
      pending.className = "empty-state";
      pending.textContent = "尚未結算（本月進行中，月底才會產生統計數字）";
      el.appendChild(pending);
      return;
    }

    var items = [
      { label: "客訴", value: monthRecord.complaint },
      { label: "測試", value: monthRecord.testing },
      { label: "總Bug", value: monthRecord.total_bug },
      { label: "攔截率", value: monthRecord.block_rate + "%" },
      { label: "完成數", value: monthRecord.completed },
      { label: "未結案", value: monthRecord.unresolved, className: monthRecord.unresolved > 0 ? "stat-overdue" : "" },
      { label: "平均天數", value: monthRecord.avg_days },
      { label: "SLA達標率", value: monthRecord.sla_rate + "%" }
    ];

    items.forEach(function (item) {
      var stat = document.createElement("div");
      stat.className = "stat-item" + (item.className ? " " + item.className : "");
      var num = document.createElement("span");
      num.className = "stat-value";
      num.textContent = String(item.value);
      var label = document.createElement("span");
      label.className = "stat-label";
      label.textContent = item.label;
      stat.appendChild(num);
      stat.appendChild(label);
      el.appendChild(stat);
    });
  }

  // 依專案分類統計客訴／測試／其他數量，範圍為 start_date 落在所選月份的議題
  // （呼叫端已依 sameMonth() 過濾，這裡只負責分組計數）。
  var PROJECT_BREAKDOWN_COLUMNS = [
    { key: "project", label: "專案" },
    { key: "complaint", label: "客訴", sortable: true },
    { key: "testing", label: "測試", sortable: true },
    { key: "other", label: "其他", sortable: true },
    { key: "total", label: "總計", sortable: true }
  ];

  function computeProjectBreakdown(issues) {
    var map = {};
    issues.forEach(function (issue) {
      var key = issue.project || "未分類";
      if (!map[key]) map[key] = { project: key, complaint: 0, testing: 0, other: 0 };
      if (issue.type === "Complaint") map[key].complaint += 1;
      else if (issue.type === "TestingBug") map[key].testing += 1;
      else map[key].other += 1;
    });
    return Object.keys(map).map(function (key) {
      var row = map[key];
      row.total = row.complaint + row.testing + row.other;
      return row;
    });
  }

  // 記住最近一次渲染的月份子集，供排序欄位點擊後重新渲染使用（排序不需重新計算分組統計）。
  var currentBreakdownMonthIssues = [];

  function renderProjectBreakdown(monthIssues) {
    currentBreakdownMonthIssues = monthIssues;

    var el = document.getElementById("project-breakdown");
    el.innerHTML = "";

    var heading = document.createElement("p");
    heading.className = "breakdown-heading";
    heading.textContent = "依專案分類（客訴／測試／其他）";
    el.appendChild(heading);

    var rows = computeProjectBreakdown(monthIssues);
    if (rows.length === 0) {
      var empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent = "所選月份無議題資料";
      el.appendChild(empty);
      return;
    }

    rows = sortBreakdownRows(rows);
    el.appendChild(buildGenericTable(rows, PROJECT_BREAKDOWN_COLUMNS, state.breakdownSort, function (key) {
      toggleBreakdownSort(key);
    }));
  }

  function sortBreakdownRows(rows) {
    var key = state.breakdownSort.key;
    if (!key) return rows;

    var dir = state.breakdownSort.dir;
    return rows.slice().sort(function (a, b) { return (a[key] - b[key]) * dir; });
  }

  // 點選欄位標題排序：同一欄位再次點選時反轉方向；切換到不同欄位時預設由大到小
  // （筆數統計通常最關心「最多」的專案，故預設降冪較符合使用情境）。
  function toggleBreakdownSort(key) {
    if (state.breakdownSort.key === key) {
      state.breakdownSort.dir = state.breakdownSort.dir === 1 ? -1 : 1;
    } else {
      state.breakdownSort.key = key;
      state.breakdownSort.dir = -1;
    }
    renderProjectBreakdown(currentBreakdownMonthIssues);
  }

  // ── 每日趨勢圖（手刻 SVG 折線圖，含橫軸日期標籤／縱軸數值刻度） ──

  var TREND_WIDTH = 640;
  var TREND_HEIGHT = 250;
  var TREND_PADDING_LEFT = 40;
  var TREND_PADDING_RIGHT = 12;
  var TREND_PADDING_TOP = 16;
  var TREND_PADDING_BOTTOM = 55;
  var TREND_Y_TICKS = 3; // 0、中間值、最大值

  function shortDate(dateStr) {
    var parts = String(dateStr).split("-");
    return parts.length === 3 ? parts[1] + "/" + parts[2] : dateStr;
  }

  function renderTrendChart(records) {
    var wrap = document.getElementById("trend-chart");
    wrap.innerHTML = "";

    if (records.length === 0) {
      var empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent = "所選月份無每日趨勢資料";
      wrap.appendChild(empty);
      return;
    }

    var max = Math.max.apply(null, records.map(function (r) { return r.total; }).concat([1]));
    var plotWidth = TREND_WIDTH - TREND_PADDING_LEFT - TREND_PADDING_RIGHT;
    var plotHeight = TREND_HEIGHT - TREND_PADDING_TOP - TREND_PADDING_BOTTOM;
    var stepX = plotWidth / Math.max(records.length - 1, 1);

    function xAt(i) { return TREND_PADDING_LEFT + i * stepX; }
    function yAt(value) { return TREND_HEIGHT - TREND_PADDING_BOTTOM - (value / max) * plotHeight; }

    var svgNS = "http://www.w3.org/2000/svg";
    var svg = document.createElementNS(svgNS, "svg");
    svg.setAttribute("viewBox", "0 0 " + TREND_WIDTH + " " + TREND_HEIGHT);
    svg.setAttribute("class", "trend-svg");
    svg.setAttribute("role", "img");
    svg.setAttribute("aria-label", "每日議題總數趨勢圖");

    function addText(x, y, text, anchor, extraClass, rotateDeg) {
      var el = document.createElementNS(svgNS, "text");
      el.setAttribute("x", x);
      el.setAttribute("y", y);
      el.setAttribute("text-anchor", anchor);
      el.setAttribute("class", "trend-axis-label" + (extraClass ? " " + extraClass : ""));
      if (rotateDeg) el.setAttribute("transform", "rotate(" + rotateDeg + " " + x + " " + y + ")");
      el.textContent = text;
      svg.appendChild(el);
    }

    // 縱軸：0、中間值、最大值三條水平格線 + 數值標籤
    for (var t = 0; t < TREND_Y_TICKS; t++) {
      var value = Math.round((max / (TREND_Y_TICKS - 1)) * t);
      var y = yAt(value);
      var gridline = document.createElementNS(svgNS, "line");
      gridline.setAttribute("x1", TREND_PADDING_LEFT);
      gridline.setAttribute("x2", TREND_WIDTH - TREND_PADDING_RIGHT);
      gridline.setAttribute("y1", y);
      gridline.setAttribute("y2", y);
      gridline.setAttribute("class", "trend-gridline");
      svg.appendChild(gridline);
      addText(TREND_PADDING_LEFT - 8, y + 3, String(value), "end", "trend-y-label");
    }

    // 橫軸：每個資料點皆顯示日期標籤（不再限制數量），斜 45 度呈現避免文字彼此重疊
    records.forEach(function (r, i) {
      addText(xAt(i), TREND_HEIGHT - TREND_PADDING_BOTTOM + 18, shortDate(r.date), "end", "trend-x-label", -45);
    });

    var points = records.map(function (r, i) { return xAt(i) + "," + yAt(r.total); }).join(" ");
    var polyline = document.createElementNS(svgNS, "polyline");
    polyline.setAttribute("points", points);
    polyline.setAttribute("class", "trend-line");
    svg.appendChild(polyline);

    records.forEach(function (r, i) {
      var circle = document.createElementNS(svgNS, "circle");
      circle.setAttribute("cx", xAt(i));
      circle.setAttribute("cy", yAt(r.total));
      circle.setAttribute("r", 4);
      circle.setAttribute("class", "trend-point");
      circle.setAttribute("tabindex", "0");

      var title = document.createElementNS(svgNS, "title");
      title.textContent = r.date + " ｜ 客訴 " + r.complaint + "・測試 " + r.testing + "・其他 " + r.other + "・總計 " + r.total;
      circle.appendChild(title);

      svg.appendChild(circle);
    });

    wrap.appendChild(svg);
  }

  // ── 議題明細清單 ──────────────────────────────────────────

  function initIssueFilters() {
    var projectSelect = document.getElementById("issue-project");
    var statusSelect = document.getElementById("issue-status");
    var searchInput = document.getElementById("issue-search");
    var quickFilterBtn = document.getElementById("quick-filter-complaint");

    var allProjectOption = document.createElement("option");
    allProjectOption.value = "";
    allProjectOption.textContent = "全部專案";
    projectSelect.appendChild(allProjectOption);

    uniqueValues(ISSUES, "project").forEach(function (project) {
      var option = document.createElement("option");
      option.value = project;
      option.textContent = project;
      projectSelect.appendChild(option);
    });

    var allStatusOption = document.createElement("option");
    allStatusOption.value = "";
    allStatusOption.textContent = "全部狀態";
    statusSelect.appendChild(allStatusOption);

    uniqueValues(ISSUES, "status").forEach(function (status) {
      var option = document.createElement("option");
      option.value = status;
      option.textContent = status;
      statusSelect.appendChild(option);
    });

    projectSelect.value = state.issueFilters.project || "";
    statusSelect.value = state.issueFilters.status || "";
    if (searchInput) searchInput.value = state.issueFilters.q || "";

    projectSelect.addEventListener("change", function () {
      state.issueFilters.project = projectSelect.value || null;
      state.page = 1;
      renderIssueTable();
    });

    statusSelect.addEventListener("change", function () {
      state.issueFilters.status = statusSelect.value || null;
      state.page = 1;
      renderIssueTable();
    });

    if (searchInput) {
      searchInput.addEventListener("input", function () {
        state.issueFilters.q = searchInput.value;
        state.page = 1;
        renderIssueTable();
      });
    }

    // 「只看客訴」快捷篩選：這個頁面沒有登入／使用者身分機制，assigned_to 只是姓名字串，
    // 沒有「目前使用者是誰」的資訊來源，不做「只看我的議題」（比照 Rails 端取捨）。
    if (quickFilterBtn) {
      quickFilterBtn.addEventListener("click", function () {
        state.issueFilters.type = state.issueFilters.type === "Complaint" ? null : "Complaint";
        state.page = 1;
        renderIssueTable();
      });
    }
  }

  var REDMINE_ISSUE_URL_BASE = "https://redmine.amastek.com.tw/issues/";

  // 四捨五入到小數 2 位；JS 的 Number → String 本來就不會補多餘的 .00（跟 Ruby
  // number_with_precision 需要另外指定 strip_insignificant_zeros 不同），故只需要 round。
  function formatHours(value) {
    return String(Math.round(value * 100) / 100);
  }

  // 表格從原本 9 欄精簡為 7 欄：議題／專案合併、類別（原「歸屬類型」）、主旨截斷、狀態改
  // badge、負責人（不含頭像，使用者反饋不必要）、開始／到期／工作天數合併成「時程與天數」、
  // 花費時間（比照 Rails IssuesController 306 改版）。
  var ISSUE_COLUMNS = [
    { key: "issue_id", label: "議題／專案", render: function (value, record) {
      var frag = document.createDocumentFragment();
      var link = document.createElement("a");
      link.className = "issue-id-link";
      link.href = REDMINE_ISSUE_URL_BASE + value;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
      link.textContent = formatValue(value);
      frag.appendChild(link);
      frag.appendChild(document.createElement("br"));
      var sub = document.createElement("span");
      sub.className = "issue-project-sub";
      sub.textContent = record.project;
      frag.appendChild(sub);
      return frag;
    } },
    { key: "type", label: "類別", render: function (value) {
      var badge = document.createElement("span");
      badge.className = "attribution-badge " + attributionClass(value);
      badge.textContent = attributionLabel(value);
      return badge;
    } },
    { key: "subject", label: "主旨", render: function (value) {
      var span = document.createElement("span");
      span.className = "issue-subject-truncate";
      span.title = value;
      span.textContent = value;
      return span;
    } },
    { key: "status", label: "狀態", render: function (value) {
      var badge = document.createElement("span");
      badge.className = "status-badge " + issueStatusBadgeClass(value);
      badge.textContent = value;
      return badge;
    } },
    { key: "assigned_to", label: "負責人" },
    { key: "timeline", label: "時程與天數", render: function (value, record) {
      return document.createTextNode(issueTimelineLabel(record));
    } },
    { key: "total_hours", label: "花費時間", render: function (value) {
      var span = document.createElement("span");
      var hours = Number(value) || 0;
      if (hours === 0) {
        span.className = "total-hours-empty";
        span.textContent = "0h";
      } else {
        span.textContent = formatHours(hours) + "h";
      }
      return span;
    } }
  ];

  function issueMatchesQuery(issue, query) {
    var needle = String(query).toLowerCase();
    return [issue.subject, issue.issue_id, issue.assigned_to].some(function (value) {
      return String(value == null ? "" : value).toLowerCase().indexOf(needle) !== -1;
    });
  }

  function filterIssues() {
    return ISSUES.filter(function (issue) {
      if (state.issueFilters.project && issue.project !== state.issueFilters.project) return false;
      if (state.issueFilters.status && issue.status !== state.issueFilters.status) return false;
      if (state.issueFilters.type && issue.type !== state.issueFilters.type) return false;
      if (state.issueFilters.q && !issueMatchesQuery(issue, state.issueFilters.q)) return false;
      return true;
    });
  }

  // 簡化版的省略號分頁序列（比照 Rails 端改用 Pagy gem 產生的 series 概念，這裡資料量小，
  // 用簡單版本即可）：永遠顯示第一頁、最後一頁、目前頁前後各一頁，其餘用「…」省略。
  function pageSeries(current, total) {
    var series = [];
    for (var p = 1; p <= total; p++) {
      if (p === 1 || p === total || Math.abs(p - current) <= 1) {
        series.push(p);
      } else if (series[series.length - 1] !== "…") {
        series.push("…");
      }
    }
    return series;
  }

  function paginate(records) {
    var totalCount = records.length;
    var totalPages = Math.max(Math.ceil(totalCount / ISSUE_PAGE_SIZE), 1);
    state.page = Math.min(Math.max(state.page, 1), totalPages);
    var start = (state.page - 1) * ISSUE_PAGE_SIZE;
    return { pageItems: records.slice(start, start + ISSUE_PAGE_SIZE), totalCount: totalCount, totalPages: totalPages, page: state.page };
  }

  function renderPagination(pageInfo) {
    var container = document.getElementById("issue-pagination");
    if (!container) return;
    container.innerHTML = "";
    if (pageInfo.totalCount === 0) return;

    var summary = document.createElement("p");
    summary.className = "pagination-summary";
    var from = (pageInfo.page - 1) * ISSUE_PAGE_SIZE + 1;
    var to = Math.min(pageInfo.page * ISSUE_PAGE_SIZE, pageInfo.totalCount);
    summary.textContent = "顯示 " + from + "–" + to + " 筆，共 " + pageInfo.totalCount + " 筆";
    container.appendChild(summary);

    if (pageInfo.totalPages <= 1) return;

    var nav = document.createElement("nav");
    nav.className = "pagy series-nav";
    nav.setAttribute("aria-label", "議題分頁");

    pageSeries(pageInfo.page, pageInfo.totalPages).forEach(function (item) {
      var a = document.createElement("a");
      if (item === "…") {
        a.setAttribute("role", "separator");
        a.setAttribute("aria-disabled", "true");
        a.textContent = "…";
      } else if (item === pageInfo.page) {
        a.setAttribute("role", "link");
        a.setAttribute("aria-current", "page");
        a.textContent = String(item);
      } else {
        a.href = "#";
        a.textContent = String(item);
        a.addEventListener("click", function (e) {
          e.preventDefault();
          state.page = item;
          renderIssueTable();
        });
      }
      nav.appendChild(a);
    });
    container.appendChild(nav);
  }

  function renderIssueKpis(kpis) {
    var el = document.getElementById("issue-kpi-cards");
    if (!el) return;
    el.innerHTML = "";

    var items = [
      { label: "待處理議題", value: kpis.pending },
      { label: "緊急客訴（客訴＋已逾期）", value: kpis.urgent_complaints, className: "stat-overdue" },
      { label: "累積總花費工時", value: formatHours(kpis.total_hours_sum) + "h" },
      { label: "逾期／未定到期日", value: kpis.overdue_or_undated, className: "stat-warning" }
    ];

    items.forEach(function (item) {
      var stat = document.createElement("div");
      stat.className = "stat-item" + (item.className ? " " + item.className : "");
      var num = document.createElement("span");
      num.className = "stat-value";
      num.textContent = String(item.value);
      var label = document.createElement("span");
      label.className = "stat-label";
      label.textContent = item.label;
      stat.appendChild(num);
      stat.appendChild(label);
      el.appendChild(stat);
    });
  }

  // sortState / onSortClick 為選填：欄位定義中標記 sortable: true 時，標題渲染為可點擊按鈕，
  // 點擊後呼叫 onSortClick(key)；目前排序中的欄位標題附加 ▲／▼ 指示目前方向。
  // （議題明細清單呼叫本函式時不帶這兩個參數，欄位標題維持純文字，不受影響。）
  function buildGenericTable(records, columns, sortState, onSortClick) {
    var table = document.createElement("table");
    table.className = "project-tasks";

    var thead = document.createElement("thead");
    var headRow = document.createElement("tr");
    columns.forEach(function (column) {
      var th = document.createElement("th");
      th.scope = "col";

      if (column.sortable && onSortClick) {
        var button = document.createElement("button");
        button.type = "button";
        button.className = "sort-button";
        var active = sortState && sortState.key === column.key;
        button.textContent = column.label + (active ? (sortState.dir === 1 ? " ▲" : " ▼") : "");
        button.setAttribute("aria-label", "依「" + column.label + "」排序");
        button.addEventListener("click", function () { onSortClick(column.key); });
        th.appendChild(button);
      } else {
        th.textContent = column.label;
      }

      headRow.appendChild(th);
    });
    thead.appendChild(headRow);
    table.appendChild(thead);

    var tbody = document.createElement("tbody");
    records.forEach(function (record) {
      var row = document.createElement("tr");
      columns.forEach(function (column) {
        var td = document.createElement("td");
        td.setAttribute("data-label", column.label);
        if (column.render) {
          td.appendChild(column.render(record[column.key], record));
        } else {
          td.textContent = formatValue(record[column.key]);
        }
        row.appendChild(td);
      });
      tbody.appendChild(row);
    });
    table.appendChild(tbody);

    return table;
  }

  function renderIssueTable() {
    var filtered = filterIssues();

    // KPI 卡片依「目前篩選結果」（含搜尋／快捷篩選，分頁之前的完整結果）計算，不是分頁後
    // 那一頁的子集合（比照 Rails 端取捨）。
    renderIssueKpis(computeIssueKpis(filtered));

    var quickFilterBtn = document.getElementById("quick-filter-complaint");
    if (quickFilterBtn) quickFilterBtn.classList.toggle("is-active", state.issueFilters.type === "Complaint");

    var container = document.getElementById("issue-table");
    container.innerHTML = "";

    if (filtered.length === 0) {
      var empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent = "目前無符合條件的議題";
      container.appendChild(empty);
      renderPagination({ totalCount: 0, totalPages: 1, page: 1 });
      return;
    }

    var pageInfo = paginate(filtered);
    container.appendChild(buildGenericTable(pageInfo.pageItems, ISSUE_COLUMNS));
    renderPagination(pageInfo);
  }

  // ── 主題切換 ──────────────────────────────────────────────

  var THEME_KEY = "warroom-theme";

  function getCurrentTheme() {
    return document.documentElement.getAttribute("data-theme") === "light" ? "light" : "dark";
  }

  function applyThemeToggleLabel(theme) {
    var btn = document.getElementById("theme-toggle");
    if (!btn) return;
    if (theme === "light") {
      btn.textContent = "☀️ 淺色";
      btn.setAttribute("aria-label", "切換至深色模式");
    } else {
      btn.textContent = "🌙 深色";
      btn.setAttribute("aria-label", "切換至淺色模式");
    }
  }

  function toggleTheme() {
    var next = getCurrentTheme() === "light" ? "dark" : "light";
    if (next === "light") {
      document.documentElement.setAttribute("data-theme", "light");
    } else {
      document.documentElement.removeAttribute("data-theme");
    }
    applyThemeToggleLabel(next);
    try {
      localStorage.setItem(THEME_KEY, next);
    } catch (e) {
      // localStorage 不可用：僅本次瀏覽切換有效
    }
  }

  // ── 初始化 ────────────────────────────────────────────────

  document.addEventListener("DOMContentLoaded", function () {
    populateMonthSelect();
    renderStatsTab(MONTH_KPI[MONTH_KPI.length - 1].year_month);
    initIssueFilters();
    renderIssueTable();

    applyThemeToggleLabel(getCurrentTheme());
    var themeToggle = document.getElementById("theme-toggle");
    if (themeToggle) themeToggle.addEventListener("click", toggleTheme);
  });
})();
