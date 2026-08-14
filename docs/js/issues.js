(function () {
  "use strict";

  // ── 模擬資料 ──────────────────────────────────────────────
  // 欄位對齊真實 306 試算表（306_臭蟲議題紀錄）分頁結構：
  // month_kpi / daily_kpi / raw_2023~raw_2026（合併為 ISSUES）/ 工程師負載表 / 專案清單表。
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

  var ENGINEER_LOAD = [
    { name: "黃紹鈞", project: "RAG", allocation_pct: 40, effective_month: "2026/05", expire_month: "2026/12", total_pct: 115 },
    { name: "陳謹皓", project: "客服支援", allocation_pct: 15, effective_month: "2026/01", expire_month: null, total_pct: 15 }
  ];

  var PROJECT_LIST = [
    { name: "KKY - 地瓜生產管理系統", abbr: "瓜瓜園 KKPMS", status: "維護", allocation_pct: 20, effective_month: "2026/01", expire_month: "2026/12", owner_rd: "周詩御,呂俐禛,楊采維(5%)" }
  ];

  // ── 篩選狀態 ──────────────────────────────────────────────

  var state = {
    issueFilters: { project: null, status: null }
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

  function populateMonthSelect() {
    var select = document.getElementById("month-select");
    MONTH_KPI.forEach(function (m) {
      var option = document.createElement("option");
      option.value = m.year_month;
      option.textContent = m.year_month;
      select.appendChild(option);
    });
    select.value = MONTH_KPI[MONTH_KPI.length - 1].year_month;

    select.addEventListener("change", function () {
      var record = MONTH_KPI.filter(function (m) { return m.year_month === select.value; })[0];
      renderKpiCards(record);
    });
  }

  function renderKpiCards(monthRecord) {
    var el = document.getElementById("kpi-cards");
    el.innerHTML = "";

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

  // ── 每日趨勢圖（手刻 SVG 折線圖） ──────────────────────────

  function renderTrendChart(records) {
    var wrap = document.getElementById("trend-chart");
    wrap.innerHTML = "";

    var width = 640;
    var height = 200;
    var padding = 28;
    var max = Math.max.apply(null, records.map(function (r) { return r.total; }).concat([1]));

    var stepX = (width - padding * 2) / Math.max(records.length - 1, 1);

    function xAt(i) { return padding + i * stepX; }
    function yAt(value) { return height - padding - (value / max) * (height - padding * 2); }

    var svgNS = "http://www.w3.org/2000/svg";
    var svg = document.createElementNS(svgNS, "svg");
    svg.setAttribute("viewBox", "0 0 " + width + " " + height);
    svg.setAttribute("class", "trend-svg");
    svg.setAttribute("role", "img");
    svg.setAttribute("aria-label", "每日議題總數趨勢圖");

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

    projectSelect.addEventListener("change", function () {
      state.issueFilters.project = projectSelect.value || null;
      renderIssueTable();
    });

    statusSelect.addEventListener("change", function () {
      state.issueFilters.status = statusSelect.value || null;
      renderIssueTable();
    });
  }

  var ISSUE_COLUMNS = [
    { key: "issue_id", label: "議題編號" },
    { key: "subject", label: "主旨" },
    { key: "project", label: "專案" },
    { key: "attribution", label: "歸屬類型", render: function (value, record) {
      var badge = document.createElement("span");
      badge.className = "attribution-badge " + attributionClass(record.type);
      badge.textContent = attributionLabel(record.type);
      return badge;
    } },
    { key: "type", label: "類型" },
    { key: "tracker", label: "追蹤標籤" },
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

  // ── 工程師負載／專案清單表 ────────────────────────────────

  var ENGINEER_LOAD_COLUMNS = [
    { key: "name", label: "工程師姓名" },
    { key: "project", label: "負責專案" },
    { key: "allocation_pct", label: "配置比例(%)" },
    { key: "effective_month", label: "生效月份" },
    { key: "expire_month", label: "失效月份" },
    { key: "total_pct", label: "當月配置總佔比合計" }
  ];

  var PROJECT_LIST_COLUMNS = [
    { key: "name", label: "專案" },
    { key: "abbr", label: "專案縮寫" },
    { key: "status", label: "狀態" },
    { key: "allocation_pct", label: "比例" },
    { key: "effective_month", label: "生效月份" },
    { key: "expire_month", label: "失效月份" },
    { key: "owner_rd", label: "負責RD" }
  ];

  function renderEngineerLoadTable() {
    var container = document.getElementById("engineer-load-table");
    container.appendChild(buildGenericTable(ENGINEER_LOAD, ENGINEER_LOAD_COLUMNS));
  }

  function renderProjectListTable() {
    var container = document.getElementById("project-list-table");
    container.appendChild(buildGenericTable(PROJECT_LIST, PROJECT_LIST_COLUMNS));
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
    renderEngineerLoadTable();
    renderProjectListTable();

    applyThemeToggleLabel(getCurrentTheme());
    var themeToggle = document.getElementById("theme-toggle");
    if (themeToggle) themeToggle.addEventListener("click", toggleTheme);
  });
})();
