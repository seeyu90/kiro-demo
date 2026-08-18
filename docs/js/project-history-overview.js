(function () {
  "use strict";

  var svgNS = "http://www.w3.org/2000/svg";

  // 各自獨立實作，不與 Rails 版（warroom-data-api-prototype）共用程式碼（同既有慣例）。
  // 邏輯對齊 Rails 版換源後的行為：甘特圖／議題明細一律用 307（HISTORY_BURNDOWN_ISSUES）
  // 的 start_date～due_date 畫真正的開發區間，不再用 305（HISTORY_TASKS）的單一完成日期。

  // 五個篩選條件（年度／狀態／客戶／PM／專案）皆不篩選＝全部；同時選取時取交集。
  // 年度預設「今年」；viewMode："list" 或 "gantt"，預設清單檢視。
  var state = {
    filters: { year: String(new Date().getFullYear()), status: null, customer: null, pm: null, project: null },
    viewMode: "list"
  };

  function uniqueValues(records, key) {
    var values = [];
    records.forEach(function (r) {
      if (values.indexOf(r[key]) === -1) values.push(r[key]);
    });
    return values;
  }

  function populateSelect(select, values, allLabel, selectedValue) {
    select.innerHTML = "";
    var allOption = document.createElement("option");
    allOption.value = "";
    allOption.textContent = allLabel;
    select.appendChild(allOption);
    values.forEach(function (value) {
      var option = document.createElement("option");
      option.value = value;
      option.textContent = value;
      if (value === selectedValue) option.selected = true;
      select.appendChild(option);
    });
  }

  function availableYears() {
    var years = [];
    HISTORY_BURNDOWN_ISSUES.forEach(function (i) {
      var year = String(i.start_date).slice(0, 4);
      if (year && years.indexOf(year) === -1) years.push(year);
    });
    return years.sort().reverse();
  }

  function initFilters() {
    var yearSelect = document.getElementById("filter-year");
    var statusSelect = document.getElementById("filter-status");
    var customerSelect = document.getElementById("filter-customer");
    var projectSelect = document.getElementById("filter-project");
    var pmSelect = document.getElementById("filter-pm");

    populateSelect(yearSelect, availableYears(), "全部年度", state.filters.year);
    populateSelect(statusSelect, uniqueValues(HISTORY_PROJECTS, "status"), "全部狀態");
    populateSelect(customerSelect, uniqueValues(HISTORY_PROJECTS, "customer"), "全部客戶");
    populateSelect(projectSelect, uniqueValues(HISTORY_PROJECTS, "project_name"), "全部專案");
    populateSelect(pmSelect, uniqueValues(HISTORY_PROJECTS, "pm"), "全部 PM");

    yearSelect.addEventListener("change", function () {
      state.filters.year = yearSelect.value || null;
      renderContent();
    });
    statusSelect.addEventListener("change", function () {
      state.filters.status = statusSelect.value || null;
      renderContent();
    });
    customerSelect.addEventListener("change", function () {
      state.filters.customer = customerSelect.value || null;
      renderContent();
    });
    projectSelect.addEventListener("change", function () {
      state.filters.project = projectSelect.value || null;
      renderContent();
    });
    pmSelect.addEventListener("change", function () {
      state.filters.pm = pmSelect.value || null;
      renderContent();
    });
  }

  // ── 資料組裝：專案 + 該年度對應到的 307 議題 ──────────────────

  function parseDate(value) {
    if (!value) return null;
    var d = new Date(value);
    return isNaN(d.getTime()) ? null : d;
  }

  function shortDate(dateStr) {
    var parts = String(dateStr).split("-");
    return parts.length === 3 ? parts[1] + "/" + parts[2] : dateStr;
  }

  function sumWeeklyHours(issue) {
    return issue.weekly_actual.reduce(function (total, point) { return total + point.hours; }, 0);
  }

  // 已消耗人時：週人時直接加總（模擬資料的 weekly_actual 本身就是「當週花費」，不像真實
  // 試算表存的是「剩餘人時」需要反推）。沒有任何週資料時視為「工時資料不足」，回傳 null，
  // 不得顯示成 0（避免誤導）。
  function consumedHoursFor(issue) {
    if (!issue.weekly_actual || issue.weekly_actual.length === 0) return null;
    return round1(sumWeeklyHours(issue));
  }

  function round1(value) { return Math.round(value * 10) / 10; }

  // JS 的 Number 本身不會保留多餘的 .0（34.0 轉字串就是 "34"，不像 Ruby Float 那樣要另外
  // 處理），這裡只需要四捨五入到小數點後兩位、轉字串即可（43.75h 這種有意義的小數維持原樣）。
  function formatHours(value) {
    return String(Math.round(value * 100) / 100);
  }

  // 「已消耗 / 預估」工時：用固定寬度讓數字兩端對齊、"/" 固定在同一欄，不會因為每列位數不同
  // （例如 13.5 vs 78.5）而讓 "/" 東倒西歪。已消耗超過預估（超支）時變警示色——「進度」已經
  // clamp 在 100%，議題早完成時看不出「其實花了預估的好幾倍工時」，只有這裡的原始數字看得出來。
  function buildHoursPair(consumed, estimated) {
    var span = document.createElement("span");
    span.className = "hours-pair" + (estimated > 0 && consumed > estimated ? " hours-pair-overspent" : "");

    var consumedEl = document.createElement("span");
    consumedEl.className = "hours-num";
    consumedEl.textContent = formatHours(consumed) + "h";

    var sepEl = document.createElement("span");
    sepEl.className = "hours-sep";
    sepEl.textContent = "/";

    var estimatedEl = document.createElement("span");
    estimatedEl.className = "hours-num";
    estimatedEl.textContent = formatHours(estimated) + "h";

    span.appendChild(consumedEl);
    span.appendChild(sepEl);
    span.appendChild(estimatedEl);
    return span;
  }

  function taskProgressPercent(estimatedHours, consumedHours) {
    if (consumedHours === null || consumedHours === undefined) return null;
    if (!estimatedHours) return null;
    var pct = Math.round((consumedHours / estimatedHours) * 100);
    return Math.max(0, Math.min(100, pct));
  }

  function durationTaskOverdue(task, today) {
    if (task.done) return false;
    var due = parseDate(task.due_date);
    return !!due && due < today;
  }

  // 307 議題沒有「實際完成日」欄位，只有 status／due_date——已完成議題的時程條右界固定用
  // due_date，不是真正的實際結案日（307 資料本身的限制）。
  function buildTasksFromBurndown(issues) {
    var today = new Date();
    return issues.map(function (issue) {
      var consumed = consumedHoursFor(issue);
      var task = {
        task_name: issue.issue_title,
        assignee: issue.assignee,
        status: issue.status,
        start_date: issue.start_date,
        due_date: issue.due_date,
        done: issue.status === "已完成",
        estimated_hours: issue.estimated_hours,
        consumed_hours: consumed,
        progress_percent: taskProgressPercent(issue.estimated_hours, consumed)
      };
      task.overdue = durationTaskOverdue(task, today);
      return task;
    });
  }

  function filterIssuesByYear(issues, year) {
    if (!year) return issues;
    return issues.filter(function (i) { return String(i.start_date).indexOf(year) === 0; });
  }

  function progressPercentFor(tasks) {
    var withHours = tasks.filter(function (t) { return t.consumed_hours !== null; });
    if (withHours.length === 0) return null;
    var totalEstimated = withHours.reduce(function (sum, t) { return sum + t.estimated_hours; }, 0);
    if (!totalEstimated) return null;
    var totalConsumed = withHours.reduce(function (sum, t) { return sum + t.consumed_hours; }, 0);
    return Math.max(0, Math.min(100, Math.round((totalConsumed / totalEstimated) * 100)));
  }

  function sumHours(tasks, key) {
    var withHours = tasks.filter(function (t) { return t.consumed_hours !== null; });
    if (withHours.length === 0) return null;
    return round1(withHours.reduce(function (sum, t) { return sum + t[key]; }, 0));
  }

  // 依 305（HISTORY_PROJECTS）為主體列出專案；每列的議題清單一律用該專案對應到的 307
  // 議題（依 year 篩選開案年度）。選定年度後，該年度沒有任何對應議題的專案直接不列出
  // （不顯示空白展開內容的卡片）。
  function buildRows(year) {
    return HISTORY_PROJECTS.map(function (project) {
      var matched = HISTORY_BURNDOWN_ISSUES.filter(function (i) { return i.project === project.project_name; });
      var matchedInYear = filterIssuesByYear(matched, year);
      var tasks = buildTasksFromBurndown(matchedInYear);
      return {
        project_name: project.project_name,
        customer: project.customer,
        pm: project.pm,
        status: project.status,
        tasks: tasks,
        progress_percent: progressPercentFor(tasks),
        hours_estimated: sumHours(tasks, "estimated_hours"),
        hours_consumed: sumHours(tasks, "consumed_hours"),
        has_overdue: tasks.some(function (t) { return t.overdue; })
      };
    }).filter(function (row) {
      return !(state.filters.year && row.tasks.length === 0);
    });
  }

  // 篩選條件同時存在時取交集；含逾期未完成任務的專案排在最前面，其餘維持原本相對順序。
  function applyFilters(rows) {
    var filtered = rows.filter(function (row) {
      if (state.filters.status && row.status !== state.filters.status) return false;
      if (state.filters.customer && row.customer !== state.filters.customer) return false;
      if (state.filters.pm && row.pm !== state.filters.pm) return false;
      if (state.filters.project && row.project_name !== state.filters.project) return false;
      return true;
    });
    return filtered.slice().sort(function (a, b) {
      if (a.has_overdue === b.has_overdue) return 0;
      return a.has_overdue ? -1 : 1;
    });
  }

  function formatValue(value) {
    if (value === null || value === undefined || value === "") return "—";
    return String(value);
  }

  function issueStatusLabel(task) {
    if (task.done) return "已完成";
    return task.overdue ? "逾期未完成" : "進行中";
  }

  // ── 清單檢視（卡片原地展開，<details>/<summary>，不需要 JS 就能展開／收合） ──

  function buildIssueTable(tasks) {
    var table = document.createElement("table");
    table.className = "project-tasks";

    var thead = document.createElement("thead");
    var headRow = document.createElement("tr");
    [ "議題", "負責人", "開案日期", "預計完成日期", "狀態", "進度", "工時" ].forEach(function (label) {
      var th = document.createElement("th");
      th.scope = "col";
      th.textContent = label;
      headRow.appendChild(th);
    });
    thead.appendChild(headRow);
    table.appendChild(thead);

    var tbody = document.createElement("tbody");
    tasks.forEach(function (task) {
      var row = document.createElement("tr");
      if (task.overdue) row.className = "row-overdue";

      var cells = [
        [ "議題", task.task_name ],
        [ "負責人", formatValue(task.assignee) ],
        [ "開案日期", formatValue(task.start_date) ],
        [ "預計完成日期", formatValue(task.due_date) ],
        [ "狀態", issueStatusLabel(task) ],
        [ "進度", task.progress_percent !== null ? task.progress_percent + "%" : "—" ]
      ];
      cells.forEach(function (pair) {
        var td = document.createElement("td");
        td.setAttribute("data-label", pair[0]);
        td.textContent = pair[1];
        row.appendChild(td);
      });

      var hoursTd = document.createElement("td");
      hoursTd.setAttribute("data-label", "工時");
      hoursTd.textContent = "";
      if (task.consumed_hours !== null) {
        hoursTd.appendChild(buildHoursPair(task.consumed_hours, task.estimated_hours));
      } else {
        hoursTd.textContent = "—";
      }
      row.appendChild(hoursTd);
      tbody.appendChild(row);
    });
    table.appendChild(tbody);
    return table;
  }

  function buildProjectCard(row) {
    var details = document.createElement("details");
    details.className = "project-card" + (row.has_overdue ? " project-card-overdue" : "");

    var summary = document.createElement("summary");
    summary.className = "project-card-summary";

    var name = document.createElement("span");
    name.className = "project-card-name";
    name.textContent = row.project_name;
    summary.appendChild(name);

    var tags = document.createElement("span");
    tags.className = "project-card-tags";
    [
      [ null, formatValue(row.customer) ],
      [ null, formatValue(row.pm) ],
      [ "tag-status", formatValue(row.status) ]
    ].forEach(function (pair) {
      var tag = document.createElement("span");
      tag.className = "tag" + (pair[0] ? " " + pair[0] : "");
      tag.textContent = pair[1];
      tags.appendChild(tag);
    });

    var hoursTag = document.createElement("span");
    hoursTag.className = "tag tag-hours";
    if (row.hours_estimated === null || row.hours_estimated === undefined) {
      hoursTag.textContent = "—";
    } else {
      hoursTag.appendChild(buildHoursPair(row.hours_consumed || 0, row.hours_estimated));
    }
    tags.appendChild(hoursTag);

    summary.appendChild(tags);
    details.appendChild(summary);

    var body = document.createElement("div");
    body.className = "project-card-body";
    if (row.tasks.length === 0) {
      var empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent = "所選年度無議題資料";
      body.appendChild(empty);
    } else {
      body.appendChild(buildIssueTable(row.tasks));
    }
    details.appendChild(body);

    return details;
  }

  function renderProjectList(rows) {
    var container = document.getElementById("history-overview-content");
    container.innerHTML = "";

    if (rows.length === 0) {
      var empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent = "目前無符合條件的專案";
      container.appendChild(empty);
      return;
    }

    var list = document.createElement("div");
    list.className = "project-card-list";
    rows.forEach(function (row) { list.appendChild(buildProjectCard(row)); });
    container.appendChild(list);
  }

  // ── 甘特圖（手刻 SVG，每個議題畫成「預計」「實際」上下兩條窄條） ──

  var GANTT_ROW_HEIGHT = 42;
  var GANTT_PADDING_LEFT = 152;
  var GANTT_PADDING_RIGHT = 16;
  var GANTT_PADDING_TOP = 28;
  var GANTT_PADDING_BOTTOM = 8;
  var GANTT_MIN_WIDTH = 720;
  var GANTT_MONTH_PX = 90;
  var GANTT_PLANNED_BAR_HEIGHT = 10;
  var GANTT_BAR_GAP = 3;
  var GANTT_ACTUAL_BAR_HEIGHT = 10;

  function ganttDomain(rows) {
    var dates = [];
    rows.forEach(function (row) {
      row.tasks.forEach(function (t) {
        var start = parseDate(t.start_date);
        var due = parseDate(t.due_date);
        if (start) dates.push(start);
        if (due) dates.push(due);
      });
    });
    dates.push(new Date());
    var min = new Date(Math.min.apply(null, dates.map(function (d) { return d.getTime(); })));
    var max = new Date(Math.max.apply(null, dates.map(function (d) { return d.getTime(); })));
    return { min: min, max: max };
  }

  function monthCount(min, max) {
    var count = 0;
    var cursor = new Date(min.getFullYear(), min.getMonth(), 1);
    while (cursor <= max) {
      count += 1;
      cursor = new Date(cursor.getFullYear(), cursor.getMonth() + 1, 1);
    }
    return count;
  }

  function ganttSvgWidth(min, max) {
    var needed = GANTT_PADDING_LEFT + GANTT_PADDING_RIGHT + monthCount(min, max) * GANTT_MONTH_PX;
    return Math.max(GANTT_MIN_WIDTH, needed);
  }

  function xAt(date, min, max, width) {
    var span = Math.max(max.getTime() - min.getTime(), 86400000);
    var plotWidth = width - GANTT_PADDING_LEFT - GANTT_PADDING_RIGHT;
    return GANTT_PADDING_LEFT + ((date.getTime() - min.getTime()) / span) * plotWidth;
  }

  function monthTicks(min, max, width) {
    var ticks = [];
    var cursor = new Date(min.getFullYear(), min.getMonth(), 1);
    var left = GANTT_PADDING_LEFT;
    var right = width - GANTT_PADDING_RIGHT;
    while (cursor <= max) {
      var x = xAt(cursor, min, max, width);
      x = Math.max(left, Math.min(right, x));
      var label = cursor.getFullYear() + "/" + String(cursor.getMonth() + 1).padStart(2, "0");
      ticks.push({ x: x, label: label });
      cursor = new Date(cursor.getFullYear(), cursor.getMonth() + 1, 1);
    }
    return ticks;
  }

  function durationFillRatio(task) {
    if (task.consumed_hours === null || !task.estimated_hours) return 0;
    return Math.max(0, Math.min(1, task.consumed_hours / task.estimated_hours));
  }

  function taskTitle(task) {
    var hoursNote = task.consumed_hours !== null
      ? formatHours(task.consumed_hours) + "h／" + formatHours(task.estimated_hours) + "h"
      : "工時資料不足";
    return task.task_name + "（" + (task.done ? "已完成" : "進行中") + "）" +
      shortDate(task.start_date) + " ～ " + shortDate(task.due_date) + "｜" + hoursNote;
  }

  function taskRect(task, min, max, width) {
    var start = parseDate(task.start_date);
    if (!start) return null;
    var due = parseDate(task.due_date);
    var today = new Date();

    var plannedEndDate = due || today;
    var plannedX2 = Math.max(xAt(plannedEndDate, min, max, width), xAt(start, min, max, width) + 4);

    var actualEndDate;
    if (task.done || !due) {
      actualEndDate = due || today;
    } else {
      actualEndDate = due > today ? due : today;
    }
    var x1 = xAt(start, min, max, width);
    var actualX2 = Math.max(xAt(actualEndDate, min, max, width), x1 + 4);
    var actualWidth = actualX2 - x1;

    return {
      x: x1,
      plannedWidth: plannedX2 - x1,
      actualWidth: actualWidth,
      fillWidth: actualWidth * durationFillRatio(task),
      done: task.done,
      overdue: task.overdue,
      title: taskTitle(task)
    };
  }

  function svgEl(tag, attrs) {
    var el = document.createElementNS(svgNS, tag);
    Object.keys(attrs || {}).forEach(function (key) { el.setAttribute(key, attrs[key]); });
    return el;
  }

  function appendTitle(el, text) {
    var title = document.createElementNS(svgNS, "title");
    title.textContent = text;
    el.appendChild(title);
  }

  function renderGanttLegend(container) {
    var legend = document.createElement("div");
    legend.className = "gantt-legend";
    legend.setAttribute("role", "note");
    legend.setAttribute("aria-label", "甘特圖圖例");
    [
      [ "legend-swatch-planned", "預計時程" ],
      [ "legend-swatch-ontime", "實際（準時，依工時消耗比例填色）" ],
      [ "legend-swatch-delayed", "實際（逾期未完成）" ]
    ].forEach(function (pair) {
      var item = document.createElement("span");
      item.className = "legend-item";
      var swatch = document.createElement("span");
      swatch.className = "legend-swatch " + pair[0];
      item.appendChild(swatch);
      item.appendChild(document.createTextNode(pair[1]));
      legend.appendChild(item);
    });
    container.appendChild(legend);
  }

  function renderGanttChart(rows) {
    var container = document.getElementById("history-overview-content");
    container.innerHTML = "";

    if (rows.length === 0) {
      var empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent = "目前無符合條件的專案";
      container.appendChild(empty);
      return;
    }

    renderGanttLegend(container);

    var domain = ganttDomain(rows);
    var width = ganttSvgWidth(domain.min, domain.max);
    var height = GANTT_PADDING_TOP + rows.length * GANTT_ROW_HEIGHT + GANTT_PADDING_BOTTOM;
    var rowsBottom = GANTT_PADDING_TOP + rows.length * GANTT_ROW_HEIGHT;

    var scrollWrap = document.createElement("div");
    scrollWrap.className = "gantt-scroll";

    var svg = svgEl("svg", {
      viewBox: "0 0 " + width + " " + height,
      width: width,
      height: height,
      "class": "gantt-svg",
      role: "img",
      "aria-label": "專案歷程甘特圖"
    });

    monthTicks(domain.min, domain.max, width).forEach(function (tick) {
      svg.appendChild(svgEl("line", {
        x1: tick.x, x2: tick.x, y1: GANTT_PADDING_TOP, y2: rowsBottom, "class": "gantt-month-gridline"
      }));
      var label = svgEl("text", { x: tick.x, y: 16, "text-anchor": "start", "class": "gantt-month-label" });
      label.textContent = tick.label;
      svg.appendChild(label);
    });

    var todayX = xAt(new Date(), domain.min, domain.max, width);
    if (todayX >= GANTT_PADDING_LEFT && todayX <= width - GANTT_PADDING_RIGHT) {
      svg.appendChild(svgEl("line", {
        x1: todayX, x2: todayX, y1: GANTT_PADDING_TOP, y2: rowsBottom, "class": "gantt-today-line"
      }));
    }

    rows.forEach(function (row, rowIndex) {
      var rowY = GANTT_PADDING_TOP + rowIndex * GANTT_ROW_HEIGHT;

      var label = svgEl("text", {
        x: GANTT_PADDING_LEFT - 8, y: rowY + GANTT_ROW_HEIGHT / 2 + 4, "text-anchor": "end", "class": "gantt-row-label"
      });
      label.textContent = row.project_name;
      svg.appendChild(label);

      svg.appendChild(svgEl("line", {
        x1: GANTT_PADDING_LEFT, x2: width - GANTT_PADDING_RIGHT,
        y1: rowY + GANTT_ROW_HEIGHT / 2, y2: rowY + GANTT_ROW_HEIGHT / 2, "class": "gantt-row-baseline"
      }));

      row.tasks.forEach(function (task) {
        var rect = taskRect(task, domain.min, domain.max, width);
        if (!rect) return;

        var statusClass = rect.overdue ? "delayed" : "ontime";
        var actualY = rowY + 8 + GANTT_PLANNED_BAR_HEIGHT + GANTT_BAR_GAP;

        var planned = svgEl("rect", {
          x: rect.x, y: rowY + 8, width: rect.plannedWidth, height: GANTT_PLANNED_BAR_HEIGHT, rx: 2, "class": "gantt-task-planned"
        });
        appendTitle(planned, rect.title);
        svg.appendChild(planned);

        var actualClass = "gantt-task-actual-track gantt-task-actual-" + statusClass + (rect.overdue ? " gantt-task-overdue" : "");
        var actual = svgEl("rect", {
          x: rect.x, y: actualY, width: rect.actualWidth, height: GANTT_ACTUAL_BAR_HEIGHT, rx: 2, "class": actualClass
        });
        appendTitle(actual, rect.title);
        svg.appendChild(actual);

        if (rect.fillWidth > 0) {
          var fill = svgEl("rect", {
            x: rect.x, y: actualY, width: rect.fillWidth, height: GANTT_ACTUAL_BAR_HEIGHT, rx: 2,
            "class": "gantt-task-actual-fill-" + statusClass
          });
          appendTitle(fill, rect.title);
          svg.appendChild(fill);
        }
      });
    });

    scrollWrap.appendChild(svg);
    container.appendChild(scrollWrap);
  }

  function renderContent() {
    var rows = applyFilters(buildRows(state.filters.year));
    if (state.viewMode === "gantt") {
      renderGanttChart(rows);
    } else {
      renderProjectList(rows);
    }
  }

  function initViewToggle() {
    var listBtn = document.getElementById("view-list-btn");
    var ganttBtn = document.getElementById("view-gantt-btn");

    listBtn.addEventListener("click", function () {
      state.viewMode = "list";
      listBtn.setAttribute("aria-pressed", "true");
      ganttBtn.setAttribute("aria-pressed", "false");
      listBtn.classList.add("active");
      ganttBtn.classList.remove("active");
      renderContent();
    });

    ganttBtn.addEventListener("click", function () {
      state.viewMode = "gantt";
      ganttBtn.setAttribute("aria-pressed", "true");
      listBtn.setAttribute("aria-pressed", "false");
      ganttBtn.classList.add("active");
      listBtn.classList.remove("active");
      renderContent();
    });

    listBtn.classList.add("active");
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
    initViewToggle();
    renderContent();

    applyThemeToggleLabel(getCurrentTheme());
    var themeToggle = document.getElementById("theme-toggle");
    if (themeToggle) themeToggle.addEventListener("click", toggleTheme);
  });
})();
