(function () {
  "use strict";

  // ── 模擬資料 ──────────────────────────────────────────────
  // 結構比照 307 試算表（307_專案人時燃盡追蹤）：專案、議題、人員、議題ID、開案日期、
  // 完成日期、預估人時、每週人時。與 Rails `/burndown` 端各自獨立實作，不共用程式碼
  // （本頁純靜態展示，週資料直接以完整 ISO 日期陣列存放，不需要模擬 Rails 端「MM/DD 表頭＋
  // 跨年推算」這個步驟）。至少涵蓋一筆「落後於理想線」與一筆「優於理想線」的範例（見下方註解）。

  var BURNDOWN_ISSUES = [
    // 落後範例：預估 40 小時，但每週實際登記工時很少，剩餘人時遠高於理想線。
    {
      project: "AG 亞炬", issue_id: "B-1001", issue_title: "API 效能優化", assignee: "王贊勛",
      start_date: "2026-07-01", due_date: "2026-08-15", estimated_hours: 40,
      weekly_actual: [
        { date: "2026-07-08", hours: 2 }, { date: "2026-07-15", hours: 3 },
        { date: "2026-07-22", hours: 2 }, { date: "2026-07-29", hours: 1 },
        { date: "2026-08-05", hours: 2 }, { date: "2026-08-12", hours: 1 }
      ]
    },
    // 超前範例：預估 30 小時，每週實際登記工時較多，剩餘人時遠低於理想線。
    {
      project: "AG 亞炬", issue_id: "B-1002", issue_title: "報表匯出功能", assignee: "蔡秉逸",
      start_date: "2026-07-01", due_date: "2026-08-15", estimated_hours: 30,
      weekly_actual: [
        { date: "2026-07-08", hours: 8 }, { date: "2026-07-15", hours: 7 },
        { date: "2026-07-22", hours: 6 }, { date: "2026-07-29", hours: 5 },
        { date: "2026-08-05", hours: 3 }, { date: "2026-08-12", hours: 1 }
      ]
    },
    // 大致貼齊理想線的範例。
    {
      project: "Virtuous HRM", issue_id: "B-2001", issue_title: "排班衝突偵測", assignee: "黃靖益",
      start_date: "2026-07-05", due_date: "2026-08-20", estimated_hours: 25,
      weekly_actual: [
        { date: "2026-07-08", hours: 3 }, { date: "2026-07-15", hours: 4 },
        { date: "2026-07-22", hours: 3 }, { date: "2026-07-29", hours: 2 },
        { date: "2026-08-05", hours: 3 }, { date: "2026-08-12", hours: 2 }
      ]
    }
  ];

  // ── 理想／實際序列計算 ────────────────────────────────────
  // 邏輯與 design.md「Sheets::FetchProjectBurndown」段落的 Ruby 版本一致（線性比例分攤、
  // 依日期累加），但兩邊各自獨立實作。

  function computeIdealSeries(issue) {
    var start = new Date(issue.start_date);
    var due = new Date(issue.due_date);
    if (isNaN(start.getTime()) || isNaN(due.getTime()) || due <= start) return [];

    var totalSpan = due.getTime() - start.getTime();
    return issue.weekly_actual.map(function (week) {
      var weekDate = new Date(week.date);
      var ratio = (weekDate.getTime() - start.getTime()) / totalSpan;
      ratio = Math.max(0, Math.min(1, ratio));
      return { date: week.date, hours: round2(issue.estimated_hours * (1 - ratio)) };
    });
  }

  function computeActualSeries(issue) {
    var cumulative = 0;
    return issue.weekly_actual.map(function (week) {
      cumulative += week.hours;
      return { date: week.date, hours: round2(issue.estimated_hours - cumulative) };
    });
  }

  function round2(value) {
    return Math.round(value * 100) / 100;
  }

  // 依專案將所有議題的理想／實際剩餘人時序列，依日期逐週加總；議題若無理想序列（起訖日缺失
  // 或不合法）則不貢獻該議題的理想線加總，不視為 0（與 Rails Actor 版本邏輯一致）。
  function sumProjectSeries(issues) {
    var byProject = {};
    issues.forEach(function (issue) {
      var key = issue.project;
      if (!byProject[key]) byProject[key] = { actual: [], ideal: [] };
      byProject[key].actual.push(computeActualSeries(issue));
      byProject[key].ideal.push(computeIdealSeries(issue));
    });

    var result = {};
    Object.keys(byProject).forEach(function (project) {
      result[project] = {
        actual_series: sumSeriesList(byProject[project].actual),
        ideal_series: sumSeriesList(byProject[project].ideal)
      };
    });
    return result;
  }

  function sumSeriesList(seriesList) {
    var totals = {};
    var order = [];
    seriesList.forEach(function (series) {
      series.forEach(function (point) {
        if (!(point.date in totals)) {
          totals[point.date] = 0;
          order.push(point.date);
        }
        totals[point.date] += point.hours;
      });
    });
    order.sort();
    return order.map(function (date) { return { date: date, hours: round2(totals[date]) }; });
  }

  // ── 篩選狀態 ──────────────────────────────────────────────

  var state = { project: null, assignee: null };

  function uniqueValues(records, key) {
    var values = [];
    records.forEach(function (r) {
      if (values.indexOf(r[key]) === -1) values.push(r[key]);
    });
    return values;
  }

  function filterIssues() {
    return BURNDOWN_ISSUES.filter(function (issue) {
      if (state.project && issue.project !== state.project) return false;
      if (state.assignee && issue.assignee !== state.assignee) return false;
      return true;
    });
  }

  function initFilters() {
    var projectSelect = document.getElementById("burndown-project");
    var assigneeSelect = document.getElementById("burndown-assignee");

    var allProject = document.createElement("option");
    allProject.value = "";
    allProject.textContent = "全部專案";
    projectSelect.appendChild(allProject);
    uniqueValues(BURNDOWN_ISSUES, "project").forEach(function (project) {
      var option = document.createElement("option");
      option.value = project;
      option.textContent = project;
      projectSelect.appendChild(option);
    });

    var allAssignee = document.createElement("option");
    allAssignee.value = "";
    allAssignee.textContent = "全部人員";
    assigneeSelect.appendChild(allAssignee);
    uniqueValues(BURNDOWN_ISSUES, "assignee").forEach(function (assignee) {
      var option = document.createElement("option");
      option.value = assignee;
      option.textContent = assignee;
      assigneeSelect.appendChild(option);
    });

    projectSelect.addEventListener("change", function () {
      state.project = projectSelect.value || null;
      renderAll();
    });
    assigneeSelect.addEventListener("change", function () {
      state.assignee = assigneeSelect.value || null;
      renderAll();
    });
  }

  // ── 渲染 ──────────────────────────────────────────────────

  function renderAll() {
    renderProjectSeries();
    renderIssueSeries();
  }

  // 專案彙總圖僅受專案篩選影響，不受人員篩選影響（比照 Rails 端需求 4.3）；
  // 未選專案時顯示全部專案的彙總圖。
  function renderProjectSeries() {
    var container = document.getElementById("project-series");
    container.innerHTML = "";

    var allSeries = sumProjectSeries(BURNDOWN_ISSUES);
    var projects = state.project ? [state.project] : Object.keys(allSeries);

    if (projects.length === 0) {
      appendEmptyState(container, "無專案彙總資料");
      return;
    }

    projects.forEach(function (project) {
      var series = allSeries[project];
      renderBurndownChart(container, project, series.actual_series, series.ideal_series);
    });
  }

  // 議題燃盡圖：專案與人員篩選同時存在時取交集（比照 Rails 端需求 4.4）。
  function renderIssueSeries() {
    var container = document.getElementById("issue-series");
    container.innerHTML = "";

    var filtered = filterIssues();
    if (filtered.length === 0) {
      appendEmptyState(container, "目前無符合條件的議題");
      return;
    }

    filtered.forEach(function (issue) {
      var title = issue.project + "／" + issue.issue_title + "（" + issue.assignee + "）";
      renderBurndownChart(container, title, computeActualSeries(issue), computeIdealSeries(issue));
    });
  }

  function appendEmptyState(container, text) {
    var empty = document.createElement("p");
    empty.className = "empty-state";
    empty.textContent = text;
    container.appendChild(empty);
  }

  // ── 燃盡圖（手刻 SVG 雙折線圖，比照 renderTrendChart 的做法，新增理想線虛線樣式） ──

  var CHART_WIDTH = 640;
  var CHART_HEIGHT = 250;
  var CHART_PADDING_LEFT = 40;
  var CHART_PADDING_RIGHT = 12;
  var CHART_PADDING_TOP = 16;
  var CHART_PADDING_BOTTOM = 55;
  var CHART_Y_TICKS = 3;

  function shortDate(dateStr) {
    var parts = String(dateStr).split("-");
    return parts.length === 3 ? parts[1] + "/" + parts[2] : dateStr;
  }

  function renderBurndownChart(container, title, actualSeries, idealSeries) {
    var block = document.createElement("div");
    block.className = "burndown-chart-block";

    var heading = document.createElement("h3");
    heading.textContent = title;
    block.appendChild(heading);

    if (actualSeries.length === 0) {
      var empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent = "無燃盡資料";
      block.appendChild(empty);
      container.appendChild(block);
      return;
    }

    var max = Math.max.apply(null, actualSeries.concat(idealSeries).map(function (p) { return p.hours; }).concat([1]));
    var plotWidth = CHART_WIDTH - CHART_PADDING_LEFT - CHART_PADDING_RIGHT;
    var plotHeight = CHART_HEIGHT - CHART_PADDING_TOP - CHART_PADDING_BOTTOM;
    var stepX = plotWidth / Math.max(actualSeries.length - 1, 1);

    function xAt(i) { return CHART_PADDING_LEFT + i * stepX; }
    function yAt(value) { return CHART_HEIGHT - CHART_PADDING_BOTTOM - (value / max) * plotHeight; }

    var svgNS = "http://www.w3.org/2000/svg";
    var svg = document.createElementNS(svgNS, "svg");
    svg.setAttribute("viewBox", "0 0 " + CHART_WIDTH + " " + CHART_HEIGHT);
    svg.setAttribute("class", "trend-svg");
    svg.setAttribute("role", "img");
    svg.setAttribute("aria-label", title + " 燃盡圖");

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

    for (var t = 0; t < CHART_Y_TICKS; t++) {
      var value = Math.round((max / (CHART_Y_TICKS - 1)) * t);
      var y = yAt(value);
      var gridline = document.createElementNS(svgNS, "line");
      gridline.setAttribute("x1", CHART_PADDING_LEFT);
      gridline.setAttribute("x2", CHART_WIDTH - CHART_PADDING_RIGHT);
      gridline.setAttribute("y1", y);
      gridline.setAttribute("y2", y);
      gridline.setAttribute("class", "trend-gridline");
      svg.appendChild(gridline);
      addText(CHART_PADDING_LEFT - 8, y + 3, String(value), "end", "trend-y-label");
    }

    actualSeries.forEach(function (point, i) {
      addText(xAt(i), CHART_HEIGHT - CHART_PADDING_BOTTOM + 18, shortDate(point.date), "end", "trend-x-label", -45);
    });

    if (idealSeries.length > 0) {
      var idealPoints = idealSeries.map(function (p, i) { return xAt(i) + "," + yAt(p.hours); }).join(" ");
      var idealLine = document.createElementNS(svgNS, "polyline");
      idealLine.setAttribute("points", idealPoints);
      idealLine.setAttribute("class", "burndown-ideal-line");
      svg.appendChild(idealLine);
    }

    var actualPoints = actualSeries.map(function (p, i) { return xAt(i) + "," + yAt(p.hours); }).join(" ");
    var actualLine = document.createElementNS(svgNS, "polyline");
    actualLine.setAttribute("points", actualPoints);
    actualLine.setAttribute("class", "burndown-actual-line");
    svg.appendChild(actualLine);

    actualSeries.forEach(function (point, i) {
      var circle = document.createElementNS(svgNS, "circle");
      circle.setAttribute("cx", xAt(i));
      circle.setAttribute("cy", yAt(point.hours));
      circle.setAttribute("r", 4);
      circle.setAttribute("class", "burndown-actual-point");
      circle.setAttribute("tabindex", "0");

      var titleEl = document.createElementNS(svgNS, "title");
      titleEl.textContent = point.date + " ｜ 實際剩餘 " + point.hours + " 小時";
      circle.appendChild(titleEl);

      svg.appendChild(circle);
    });

    block.appendChild(svg);
    container.appendChild(block);
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
    initFilters();
    renderAll();

    applyThemeToggleLabel(getCurrentTheme());
    var themeToggle = document.getElementById("theme-toggle");
    if (themeToggle) themeToggle.addEventListener("click", toggleTheme);
  });
})();
