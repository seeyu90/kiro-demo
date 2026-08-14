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
    { date: "2026-08-01", complaint: 0, testing: 1, other: 0, total: 1 },
    { date: "2026-08-04", complaint: 4, testing: 0, other: 0, total: 4 },
    { date: "2026-08-06", complaint: 0, testing: 2, other: 0, total: 2 },
    { date: "2026-08-08", complaint: 1, testing: 4, other: 0, total: 5 },
    { date: "2026-08-11", complaint: 0, testing: 4, other: 0, total: 4 },
    { date: "2026-08-12", complaint: 1, testing: 0, other: 0, total: 1 },
    { date: "2026-08-13", complaint: 0, testing: 0, other: 0, total: 0 }
  ];

  var ISSUES = [
    { issue_id: 4547, subject: "[客訴] 未匯入 2026 行事曆", type: "Complaint", tracker: "臭蟲", status: "已結束", assigned_to: "黃靖益", start_date: "2026-01-02", due_date: "2026-01-06", work_days: 3, project: "Virtuous HRM" },
    { issue_id: 4884, subject: "[測試] 按離職結算，出現伺服器錯誤", type: "TestingBug", tracker: "臭蟲", status: "已結束", assigned_to: "黃靖益", start_date: "2026-05-18", due_date: null, work_days: null, project: "Virtuous HRM" },
    { issue_id: 5160, subject: "[客訴] A3原料發貨異常", type: "Complaint", tracker: "臭蟲", status: "已解決", assigned_to: "王贊勛", start_date: "2026-08-11", due_date: "2026-08-11", work_days: 0, project: "JZN 舊振南智慧工廠" },
    { issue_id: 5165, subject: "[測試] Cloud Admin 申請白名單 申請時間錯誤", type: "TestingBug", tracker: "臭蟲", status: "新建立", assigned_to: "蔡秉逸", start_date: "2026-08-12", due_date: null, work_days: null, project: "Virtuous HRM" },
    { issue_id: 3058, subject: "[PMS] 結案小工序DeadlockVictim", type: "Other", tracker: "臭蟲", status: "已暫停", assigned_to: "王贊勛", start_date: "2024-04-29", due_date: null, work_days: null, project: "AG 亞炬" },
    { issue_id: 4301, subject: "[客訴] QC登入後會出現無權限使用此功能的跳窗", type: "Complaint", tracker: "臭蟲", status: "已結束", assigned_to: "王贊勛", start_date: "2025-09-03", due_date: "2026-01-30", work_days: 108, project: "JieZhou 傑宙" }
  ];

  // ── 篩選狀態 ──────────────────────────────────────────────

  // 預設篩選：全部專案 + 狀態「新建立」，聚焦最需要處理的新進議題。
  var state = {
    issueFilters: { project: null, status: "新建立" }
  };

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
      var record = MONTH_KPI.filter(function (m) { return m.year_month === select.value; })[0];
      renderKpiCards(record);
    });
  }

  function renderKpiCards(monthRecord) {
    var el = document.getElementById("kpi-cards");
    el.innerHTML = "";

    if (!monthRecord) {
      var pending = document.createElement("p");
      pending.className = "empty-state";
      pending.textContent = "尚未結算（本月進行中，月底才會產生統計數字）";
      el.appendChild(pending);
      renderProjectBreakdown();
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

    renderProjectBreakdown();
  }

  // 依專案分類統計客訴／測試／其他數量（跨全部議題，非僅限所選月份 —
  // 議題明細目前無月份維度可篩選，真實資料串接時視需求決定是否依月份篩選）。
  var PROJECT_BREAKDOWN_COLUMNS = [
    { key: "project", label: "專案" },
    { key: "complaint", label: "客訴" },
    { key: "testing", label: "測試" },
    { key: "other", label: "其他" },
    { key: "total", label: "總計" }
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

  function renderProjectBreakdown() {
    var el = document.getElementById("project-breakdown");
    el.innerHTML = "";

    var heading = document.createElement("p");
    heading.className = "breakdown-heading";
    heading.textContent = "依專案分類（客訴／測試／其他）";
    el.appendChild(heading);

    el.appendChild(buildGenericTable(computeProjectBreakdown(ISSUES), PROJECT_BREAKDOWN_COLUMNS));
  }

  // ── 每日趨勢圖（手刻 SVG 折線圖，含橫軸日期標籤／縱軸數值刻度） ──

  var TREND_WIDTH = 640;
  var TREND_HEIGHT = 220;
  var TREND_PADDING_LEFT = 40;
  var TREND_PADDING_RIGHT = 12;
  var TREND_PADDING_TOP = 16;
  var TREND_PADDING_BOTTOM = 28;
  var TREND_MAX_X_LABELS = 6;
  var TREND_Y_TICKS = 3; // 0、中間值、最大值

  // 資料點數量超過可容納標籤數時，等距挑選索引（含首尾），避免橫軸標籤重疊。
  function pickLabelIndices(count, maxLabels) {
    if (count <= 1) return count === 1 ? [0] : [];
    if (count <= maxLabels) {
      var all = [];
      for (var n = 0; n < count; n++) all.push(n);
      return all;
    }
    var indices = [];
    var step = (count - 1) / (maxLabels - 1);
    for (var k = 0; k < maxLabels; k++) {
      var idx = Math.round(k * step);
      if (indices.indexOf(idx) === -1) indices.push(idx);
    }
    return indices;
  }

  function shortDate(dateStr) {
    var parts = String(dateStr).split("-");
    return parts.length === 3 ? parts[1] + "/" + parts[2] : dateStr;
  }

  function renderTrendChart(records) {
    var wrap = document.getElementById("trend-chart");
    wrap.innerHTML = "";

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

    function addText(x, y, text, anchor, extraClass) {
      var el = document.createElementNS(svgNS, "text");
      el.setAttribute("x", x);
      el.setAttribute("y", y);
      el.setAttribute("text-anchor", anchor);
      el.setAttribute("class", "trend-axis-label" + (extraClass ? " " + extraClass : ""));
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

    // 橫軸：等距挑選日期標籤（含首尾），避免資料點過多時重疊
    pickLabelIndices(records.length, TREND_MAX_X_LABELS).forEach(function (i) {
      addText(xAt(i), TREND_HEIGHT - TREND_PADDING_BOTTOM + 16, shortDate(records[i].date), "middle", "trend-x-label");
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

    projectSelect.addEventListener("change", function () {
      state.issueFilters.project = projectSelect.value || null;
      renderIssueTable();
    });

    statusSelect.addEventListener("change", function () {
      state.issueFilters.status = statusSelect.value || null;
      renderIssueTable();
    });
  }

  var REDMINE_ISSUE_URL_BASE = "https://redmine.amastek.com.tw/issues/";

  var ISSUE_COLUMNS = [
    { key: "issue_id", label: "議題編號", render: function (value) {
      var link = document.createElement("a");
      link.className = "issue-id-link";
      link.href = REDMINE_ISSUE_URL_BASE + value;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
      link.textContent = formatValue(value);
      return link;
    } },
    { key: "project", label: "專案" },
    { key: "subject", label: "主旨" },
    { key: "attribution", label: "歸屬類型", render: function (value, record) {
      var badge = document.createElement("span");
      badge.className = "attribution-badge " + attributionClass(record.type);
      badge.textContent = attributionLabel(record.type);
      return badge;
    } },
    { key: "status", label: "狀態" },
    { key: "assigned_to", label: "負責人" },
    { key: "start_date", label: "開始日期" },
    { key: "due_date", label: "到期日期" },
    { key: "work_days", label: "工作天數" }
  ];

  function filterIssues() {
    return ISSUES.filter(function (issue) {
      if (state.issueFilters.project && issue.project !== state.issueFilters.project) return false;
      if (state.issueFilters.status && issue.status !== state.issueFilters.status) return false;
      return true;
    });
  }

  function buildGenericTable(records, columns) {
    var table = document.createElement("table");
    table.className = "project-tasks";

    var thead = document.createElement("thead");
    var headRow = document.createElement("tr");
    columns.forEach(function (column) {
      var th = document.createElement("th");
      th.scope = "col";
      th.textContent = column.label;
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
    var container = document.getElementById("issue-table");
    container.innerHTML = "";

    var filtered = filterIssues();

    if (filtered.length === 0) {
      var empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent = "目前無符合條件的議題";
      container.appendChild(empty);
      return;
    }

    container.appendChild(buildGenericTable(filtered, ISSUE_COLUMNS));
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
    renderKpiCards(MONTH_KPI[MONTH_KPI.length - 1]);
    renderTrendChart(DAILY_KPI);
    initIssueFilters();
    renderIssueTable();

    applyThemeToggleLabel(getCurrentTheme());
    var themeToggle = document.getElementById("theme-toggle");
    if (themeToggle) themeToggle.addEventListener("click", toggleTheme);
  });
})();
