(function () {
  "use strict";

  var svgNS = "http://www.w3.org/2000/svg";
  var REDMINE_ISSUE_URL_BASE = HISTORY_REDMINE_ISSUE_URL_BASE;

  // ── 共用輔助 ──────────────────────────────────────────────

  function formatValue(value) {
    if (value === null || value === undefined || value === "") return "—";
    return String(value);
  }

  function shortDate(dateStr) {
    var parts = String(dateStr).split("-");
    return parts.length === 3 ? parts[1] + "/" + parts[2] : dateStr;
  }

  function appendEmptyState(container, text) {
    var empty = document.createElement("p");
    empty.className = "empty-state";
    empty.textContent = text;
    container.appendChild(empty);
  }

  // ── 專案選擇（需求 4） ──────────────────────────────────────

  function getProjectFromQuery() {
    var params = new URLSearchParams(window.location.search);
    return params.get("project");
  }

  function initProjectSelect() {
    var select = document.getElementById("project-select");
    HISTORY_PROJECTS.forEach(function (project) {
      var option = document.createElement("option");
      option.value = project.project_name;
      option.textContent = project.project_name;
      select.appendChild(option);
    });

    var fromQuery = getProjectFromQuery();
    var validNames = HISTORY_PROJECTS.map(function (p) { return p.project_name; });
    var initial = (fromQuery && validNames.indexOf(fromQuery) !== -1) ? fromQuery : HISTORY_PROJECTS[0].project_name;
    select.value = initial;

    select.addEventListener("change", function () {
      renderDetail(select.value);
    });

    return initial;
  }

  // ── 花費工時趨勢（需求 5，重用 307 燃盡議題的 weekly_actual） ──

  var TREND_WIDTH = 640;
  var TREND_HEIGHT = 250;
  var TREND_PADDING_LEFT = 40;
  var TREND_PADDING_RIGHT = 12;
  var TREND_PADDING_TOP = 16;
  var TREND_PADDING_BOTTOM = 55;
  var TREND_Y_TICKS = 3;

  // 依日期加總所選專案全部燃盡議題的週實際人時（比照 burndown.js 的 sumWeeklyByDate 手法）。
  function sumWeeklyHours(burndownIssues) {
    var totals = {};
    var order = [];
    burndownIssues.forEach(function (issue) {
      issue.weekly_actual.forEach(function (point) {
        if (!(point.date in totals)) {
          totals[point.date] = 0;
          order.push(point.date);
        }
        totals[point.date] += point.hours;
      });
    });
    order.sort();
    return order.map(function (date) { return { date: date, hours: totals[date] }; });
  }

  function renderWorkHoursTrend(burndownIssues) {
    var wrap = document.getElementById("work-hours-trend");
    wrap.innerHTML = "";

    if (burndownIssues.length === 0) {
      appendEmptyState(wrap, "所選專案無工時資料");
      return;
    }

    var series = sumWeeklyHours(burndownIssues);
    var max = Math.max.apply(null, series.map(function (p) { return p.hours; }).concat([1]));
    var plotWidth = TREND_WIDTH - TREND_PADDING_LEFT - TREND_PADDING_RIGHT;
    var plotHeight = TREND_HEIGHT - TREND_PADDING_TOP - TREND_PADDING_BOTTOM;
    var stepX = plotWidth / Math.max(series.length - 1, 1);

    function xAt(i) { return TREND_PADDING_LEFT + i * stepX; }
    function yAt(value) { return TREND_HEIGHT - TREND_PADDING_BOTTOM - (value / max) * plotHeight; }

    var svg = document.createElementNS(svgNS, "svg");
    svg.setAttribute("viewBox", "0 0 " + TREND_WIDTH + " " + TREND_HEIGHT);
    svg.setAttribute("class", "trend-svg");
    svg.setAttribute("role", "img");
    svg.setAttribute("aria-label", "花費工時趨勢圖");

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

    series.forEach(function (p, i) {
      addText(xAt(i), TREND_HEIGHT - TREND_PADDING_BOTTOM + 18, shortDate(p.date), "end", "trend-x-label", -45);
    });

    var points = series.map(function (p, i) { return xAt(i) + "," + yAt(p.hours); }).join(" ");
    var polyline = document.createElementNS(svgNS, "polyline");
    polyline.setAttribute("points", points);
    polyline.setAttribute("class", "trend-line");
    svg.appendChild(polyline);

    series.forEach(function (p, i) {
      var circle = document.createElementNS(svgNS, "circle");
      circle.setAttribute("cx", xAt(i));
      circle.setAttribute("cy", yAt(p.hours));
      circle.setAttribute("r", 4);
      circle.setAttribute("class", "trend-point");
      circle.setAttribute("tabindex", "0");

      var titleEl = document.createElementNS(svgNS, "title");
      titleEl.textContent = p.date + " ｜ 花費工時 " + p.hours + " 小時";
      circle.appendChild(titleEl);

      svg.appendChild(circle);
    });

    wrap.appendChild(svg);
  }

  // ── 每週進度達成率（需求 6，重用 307 理想／實際剩餘人時燃盡序列邏輯，
  //    邏輯與 docs/js/burndown.js 的 computeIdealSeries／computeActualSeries 一致，
  //    各自獨立實作不共用程式碼，同既有 305/306/307 慣例） ──

  function round2(value) {
    return Math.round(value * 100) / 100;
  }

  // 議題在某一天的理想剩餘人時；起訖日期不合法（含 due_date 不晚於 start_date）時回傳 null，
  // 呼叫端據此排除該議題不計入彙總的那一天（需求 6.3），而非把 0 當成有效值加進總和。
  function idealHoursAt(issue, dateStr) {
    var start = new Date(issue.start_date);
    var due = new Date(issue.due_date);
    if (isNaN(start.getTime()) || isNaN(due.getTime()) || due <= start) return null;

    var d = new Date(dateStr);
    var ratio = (d.getTime() - start.getTime()) / (due.getTime() - start.getTime());
    ratio = Math.max(0, Math.min(1, ratio));
    return round2(issue.estimated_hours * (1 - ratio));
  }

  function computeActualSeries(issue) {
    var cumulative = 0;
    return issue.weekly_actual.map(function (week) {
      cumulative += week.hours;
      return { date: week.date, hours: round2(issue.estimated_hours - cumulative) };
    });
  }

  // 依日期加總多份「實際」序列（各議題日期一致，直接加總不需要逐日計算）。
  function sumSeriesByDate(seriesList) {
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

  // 依專案彙總全部議題的理想／實際剩餘人時（需求 6.1）。理想線在「彙總後的每一個日期」對每個
  // 議題各自算一次當天的理想剩餘人時再加總，而非分別算好每個議題自己的（含起訖錨點的）序列後
  // 才相加——後者會讓不同議題各自的起訖錨點日期插進聯集，其他議題在那天沒有對應資料，加總後
  // 會在那個日期出現不該有的凹陷（例如某議題完成日剛好被算進總和，當天卻只有那一個議題的 0，
  // 其餘議題的當日進度被忽略，總和瞬間掉到只剩一小塊又彈回來）。缺少合法起訖日期的議題在任一
  // 天都回傳 null，直接被排除不計入理想線彙總（需求 6.3）。
  function computeProjectBurndown(burndownIssues) {
    var dates = [];
    var seenDate = {};
    burndownIssues.forEach(function (issue) {
      issue.weekly_actual.forEach(function (week) {
        if (!(week.date in seenDate)) { seenDate[week.date] = true; dates.push(week.date); }
      });
    });
    dates.sort();

    var idealSeries = dates.map(function (date) {
      var total = 0;
      var any = false;
      burndownIssues.forEach(function (issue) {
        var hours = idealHoursAt(issue, date);
        if (hours !== null) { total += hours; any = true; }
      });
      return any ? { date: date, hours: round2(total) } : null;
    }).filter(Boolean);

    var actualSeries = sumSeriesByDate(burndownIssues.map(computeActualSeries));
    return { idealSeries: idealSeries, actualSeries: actualSeries };
  }

  var CHART_WIDTH = 640;
  var CHART_HEIGHT = 250;
  var CHART_PADDING_LEFT = 40;
  var CHART_PADDING_RIGHT = 12;
  var CHART_PADDING_TOP = 16;
  var CHART_PADDING_BOTTOM = 55;
  var CHART_Y_TICKS = 3;

  function plotWidth() { return CHART_WIDTH - CHART_PADDING_LEFT - CHART_PADDING_RIGHT; }
  function plotHeight() { return CHART_HEIGHT - CHART_PADDING_TOP - CHART_PADDING_BOTTOM; }

  function yAt(value, min, max) {
    var ratio = (value - min) / (max - min);
    return CHART_HEIGHT - CHART_PADDING_BOTTOM - ratio * plotHeight();
  }

  function addChartText(svg, x, y, text, anchor, extraClass, rotateDeg) {
    var el = document.createElementNS(svgNS, "text");
    el.setAttribute("x", x);
    el.setAttribute("y", y);
    el.setAttribute("text-anchor", anchor);
    el.setAttribute("class", "trend-axis-label" + (extraClass ? " " + extraClass : ""));
    if (rotateDeg) el.setAttribute("transform", "rotate(" + rotateDeg + " " + x + " " + y + ")");
    el.textContent = text;
    svg.appendChild(el);
  }

  function yTicks(min, max) {
    var ticks = [];
    var seen = {};
    for (var t = 0; t < CHART_Y_TICKS; t++) {
      var value = Math.round(min + ((max - min) / (CHART_Y_TICKS - 1)) * t);
      if (!(value in seen)) {
        seen[value] = true;
        ticks.push({ value: value, y: yAt(value, min, max) });
      }
    }
    if (min < 0 && max > 0 && !(0 in seen)) {
      ticks.push({ value: 0, y: yAt(0, min, max) });
    }
    ticks.sort(function (a, b) { return a.value - b.value; });
    return ticks;
  }

  function renderBurndownChart(idealSeries, actualSeries) {
    var container = document.getElementById("burndown-chart");
    container.innerHTML = "";

    if (actualSeries.length === 0) {
      appendEmptyState(container, "所選專案無燃盡資料");
      return;
    }

    var allPoints = actualSeries.concat(idealSeries);
    var max = Math.max.apply(null, allPoints.map(function (p) { return p.hours; }).concat([1]));
    var min = Math.min.apply(null, allPoints.map(function (p) { return p.hours; }).concat([0]));

    var dates = [];
    var seenDate = {};
    allPoints.forEach(function (p) {
      if (!(p.date in seenDate)) { seenDate[p.date] = true; dates.push(p.date); }
    });
    dates.sort();
    var indexByDate = {};
    dates.forEach(function (d, i) { indexByDate[d] = i; });
    var stepX = plotWidth() / Math.max(dates.length - 1, 1);
    function xAt(i) { return CHART_PADDING_LEFT + i * stepX; }

    var svg = document.createElementNS(svgNS, "svg");
    svg.setAttribute("viewBox", "0 0 " + CHART_WIDTH + " " + CHART_HEIGHT);
    svg.setAttribute("class", "trend-svg");
    svg.setAttribute("role", "img");
    svg.setAttribute("aria-label", "每週進度達成率燃盡圖");

    yTicks(min, max).forEach(function (tick) {
      var gridline = document.createElementNS(svgNS, "line");
      gridline.setAttribute("x1", CHART_PADDING_LEFT);
      gridline.setAttribute("x2", CHART_WIDTH - CHART_PADDING_RIGHT);
      gridline.setAttribute("y1", tick.y);
      gridline.setAttribute("y2", tick.y);
      gridline.setAttribute("class", "trend-gridline");
      svg.appendChild(gridline);
      addChartText(svg, CHART_PADDING_LEFT - 8, tick.y + 3, String(tick.value), "end", "trend-y-label");
    });

    dates.forEach(function (date, i) {
      addChartText(svg, xAt(i), CHART_HEIGHT - CHART_PADDING_BOTTOM + 18, shortDate(date), "end", "trend-x-label", -45);
    });

    if (idealSeries.length > 0) {
      var idealPoints = idealSeries.map(function (p) { return xAt(indexByDate[p.date]) + "," + yAt(p.hours, min, max); }).join(" ");
      var idealLine = document.createElementNS(svgNS, "polyline");
      idealLine.setAttribute("points", idealPoints);
      idealLine.setAttribute("class", "burndown-ideal-line");
      svg.appendChild(idealLine);
    }

    var actualPoints = actualSeries.map(function (p) { return xAt(indexByDate[p.date]) + "," + yAt(p.hours, min, max); }).join(" ");
    var actualLine = document.createElementNS(svgNS, "polyline");
    actualLine.setAttribute("points", actualPoints);
    actualLine.setAttribute("class", "burndown-actual-line");
    svg.appendChild(actualLine);

    actualSeries.forEach(function (point) {
      var circle = document.createElementNS(svgNS, "circle");
      circle.setAttribute("cx", xAt(indexByDate[point.date]));
      circle.setAttribute("cy", yAt(point.hours, min, max));
      circle.setAttribute("r", 4);
      circle.setAttribute("class", "burndown-actual-point");
      circle.setAttribute("tabindex", "0");

      var titleEl = document.createElementNS(svgNS, "title");
      titleEl.textContent = point.date + " ｜ 實際剩餘 " + point.hours + " 小時";
      circle.appendChild(titleEl);

      svg.appendChild(circle);
    });

    container.appendChild(svg);
  }

  // ── 測試問題趨勢（需求 7.1） ──────────────────────────────

  // 以 ISO 週（週一為起始）分組計數，週別標籤取該週週一日期。
  function weekStart(dateStr) {
    var d = new Date(dateStr);
    var day = d.getDay();
    var diff = day === 0 ? -6 : 1 - day;
    d.setDate(d.getDate() + diff);
    return d.toISOString().slice(0, 10);
  }

  function renderTestingTrend(issues) {
    var wrap = document.getElementById("testing-trend");
    wrap.innerHTML = "";

    var testingIssues = issues.filter(function (i) { return i.type === "TestingBug"; });
    if (testingIssues.length === 0) {
      appendEmptyState(wrap, "所選專案無測試問題資料");
      return;
    }

    var counts = {};
    var order = [];
    testingIssues.forEach(function (issue) {
      var week = weekStart(issue.start_date);
      if (!(week in counts)) {
        counts[week] = 0;
        order.push(week);
      }
      counts[week] += 1;
    });
    order.sort();
    var series = order.map(function (week) { return { date: week, count: counts[week] }; });

    var max = Math.max.apply(null, series.map(function (p) { return p.count; }).concat([1]));
    var plotWidth = TREND_WIDTH - TREND_PADDING_LEFT - TREND_PADDING_RIGHT;
    var plotHeight = TREND_HEIGHT - TREND_PADDING_TOP - TREND_PADDING_BOTTOM;
    var stepX = plotWidth / Math.max(series.length - 1, 1);

    function xAt(i) { return TREND_PADDING_LEFT + i * stepX; }
    function yAt(value) { return TREND_HEIGHT - TREND_PADDING_BOTTOM - (value / max) * plotHeight; }

    var svg = document.createElementNS(svgNS, "svg");
    svg.setAttribute("viewBox", "0 0 " + TREND_WIDTH + " " + TREND_HEIGHT);
    svg.setAttribute("class", "trend-svg");
    svg.setAttribute("role", "img");
    svg.setAttribute("aria-label", "測試問題趨勢圖");

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
      addChartText(svg, TREND_PADDING_LEFT - 8, y + 3, String(value), "end", "trend-y-label");
    }

    series.forEach(function (p, i) {
      addChartText(svg, xAt(i), TREND_HEIGHT - TREND_PADDING_BOTTOM + 18, shortDate(p.date) + " 週", "end", "trend-x-label", -45);
    });

    var points = series.map(function (p, i) { return xAt(i) + "," + yAt(p.count); }).join(" ");
    var polyline = document.createElementNS(svgNS, "polyline");
    polyline.setAttribute("points", points);
    polyline.setAttribute("class", "trend-line");
    svg.appendChild(polyline);

    series.forEach(function (p, i) {
      var circle = document.createElementNS(svgNS, "circle");
      circle.setAttribute("cx", xAt(i));
      circle.setAttribute("cy", yAt(p.count));
      circle.setAttribute("r", 4);
      circle.setAttribute("class", "trend-point");
      circle.setAttribute("tabindex", "0");

      var titleEl = document.createElementNS(svgNS, "title");
      titleEl.textContent = p.date + " 這週 ｜ 測試問題 " + p.count + " 筆";
      circle.appendChild(titleEl);

      svg.appendChild(circle);
    });

    wrap.appendChild(svg);
  }

  // ── 客訴議題狀態（需求 7.2、7.3、7.4） ──────────────────────

  var RESOLVED_STATUSES = ["已結束", "已解決"];

  function computeComplaintStatus(issues) {
    var complaints = issues.filter(function (i) { return i.type === "Complaint"; });
    var resolved = complaints.filter(function (i) { return RESOLVED_STATUSES.indexOf(i.status) !== -1; });
    var unresolved = complaints.filter(function (i) { return RESOLVED_STATUSES.indexOf(i.status) === -1; });
    return { resolved_count: resolved.length, unresolved_count: unresolved.length, unresolved_list: unresolved };
  }

  function renderComplaintSummary(result) {
    var container = document.getElementById("complaint-summary");
    container.innerHTML = "";

    if (result.resolved_count === 0 && result.unresolved_count === 0) {
      appendEmptyState(container, "所選專案無客訴議題");
      return;
    }

    var summaryBar = document.createElement("div");
    summaryBar.className = "summary-bar";
    [
      { label: "已解決客訴", value: result.resolved_count },
      { label: "未解決客訴", value: result.unresolved_count, className: result.unresolved_count > 0 ? "stat-overdue" : "" }
    ].forEach(function (item) {
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
      summaryBar.appendChild(stat);
    });
    container.appendChild(summaryBar);

    if (result.unresolved_list.length === 0) return;

    var heading = document.createElement("p");
    heading.className = "breakdown-heading";
    heading.textContent = "未解決客訴清單";
    container.appendChild(heading);

    var columns = [
      { key: "issue_id", label: "議題編號", render: function (value) {
        var link = document.createElement("a");
        link.className = "issue-id-link";
        link.href = REDMINE_ISSUE_URL_BASE + value;
        link.target = "_blank";
        link.rel = "noopener noreferrer";
        link.textContent = formatValue(value);
        return link;
      } },
      { key: "subject", label: "主旨" },
      { key: "status", label: "狀態" },
      { key: "start_date", label: "建立日期" }
    ];

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
    result.unresolved_list.forEach(function (record) {
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
    container.appendChild(table);
  }

  // ── 統一入口（需求 4.3） ──────────────────────────────────

  function renderDetail(projectName) {
    document.getElementById("detail-project-name").textContent = "專案歷程 — " + projectName;

    var tasks = HISTORY_TASKS.filter(function (t) { return t.project_name === projectName; });
    var issues = HISTORY_ISSUES.filter(function (i) { return i.project === projectName; });
    var burndownIssues = HISTORY_BURNDOWN_ISSUES.filter(function (b) { return b.project === projectName; });

    renderWorkHoursTrend(burndownIssues);
    var burndown = computeProjectBurndown(burndownIssues);
    renderBurndownChart(burndown.idealSeries, burndown.actualSeries);
    renderTestingTrend(issues);
    renderComplaintSummary(computeComplaintStatus(issues));

    void tasks; // 任務明細目前僅供總覽頁甘特圖使用，本頁未另外呈現任務清單
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
    var initialProject = initProjectSelect();
    renderDetail(initialProject);

    applyThemeToggleLabel(getCurrentTheme());
    var themeToggle = document.getElementById("theme-toggle");
    if (themeToggle) themeToggle.addEventListener("click", toggleTheme);
  });
})();
