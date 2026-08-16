(function () {
  "use strict";

  var svgNS = "http://www.w3.org/2000/svg";

  // 三個篩選條件（狀態／客戶／PM）皆不篩選＝全部；同時選取時取交集（需求 2.3）。
  // viewMode："list" 或 "gantt"，預設清單檢視（需求 3.4）。
  var state = {
    filters: { status: null, customer: null, pm: null },
    viewMode: "list"
  };

  function uniqueValues(records, key) {
    var values = [];
    records.forEach(function (r) {
      if (values.indexOf(r[key]) === -1) values.push(r[key]);
    });
    return values;
  }

  function populateSelect(select, values, allLabel) {
    var allOption = document.createElement("option");
    allOption.value = "";
    allOption.textContent = allLabel;
    select.appendChild(allOption);
    values.forEach(function (value) {
      var option = document.createElement("option");
      option.value = value;
      option.textContent = value;
      select.appendChild(option);
    });
  }

  function initFilters() {
    var statusSelect = document.getElementById("filter-status");
    var customerSelect = document.getElementById("filter-customer");
    var pmSelect = document.getElementById("filter-pm");

    populateSelect(statusSelect, uniqueValues(HISTORY_PROJECTS, "status"), "全部狀態");
    populateSelect(customerSelect, uniqueValues(HISTORY_PROJECTS, "customer"), "全部客戶");
    populateSelect(pmSelect, uniqueValues(HISTORY_PROJECTS, "pm"), "全部 PM");

    statusSelect.addEventListener("change", function () {
      state.filters.status = statusSelect.value || null;
      renderContent();
    });
    customerSelect.addEventListener("change", function () {
      state.filters.customer = customerSelect.value || null;
      renderContent();
    });
    pmSelect.addEventListener("change", function () {
      state.filters.pm = pmSelect.value || null;
      renderContent();
    });
  }

  // 三個篩選條件同時存在時取交集（需求 2.3）。
  function applyFilters(projects) {
    return projects.filter(function (project) {
      if (state.filters.status && project.status !== state.filters.status) return false;
      if (state.filters.customer && project.customer !== state.filters.customer) return false;
      if (state.filters.pm && project.pm !== state.filters.pm) return false;
      return true;
    });
  }

  // 專案層級的預計／實際完成日期：取該專案任務中最晚的 planned_completion_date；
  // 若任一任務尚無 actual_completion_date，專案視為「進行中」（需求 3.2）。
  function projectDateSummary(projectName) {
    var tasks = HISTORY_TASKS.filter(function (t) { return t.project_name === projectName; });
    var plannedDates = tasks.map(function (t) { return t.planned_completion_date; }).filter(Boolean).sort();
    var hasOngoing = tasks.some(function (t) { return !t.actual_completion_date; });
    var actualDates = tasks.map(function (t) { return t.actual_completion_date; }).filter(Boolean).sort();
    return {
      planned: plannedDates.length > 0 ? plannedDates[plannedDates.length - 1] : null,
      actual: hasOngoing ? null : (actualDates.length > 0 ? actualDates[actualDates.length - 1] : null)
    };
  }

  function detailLink(projectName) {
    return "project-history-detail.html?project=" + encodeURIComponent(projectName);
  }

  var PROJECT_LIST_COLUMNS = [
    { key: "project_name", label: "專案", render: function (value) {
      var link = document.createElement("a");
      link.className = "project-history-link";
      link.href = detailLink(value);
      link.textContent = value;
      return link;
    } },
    { key: "customer", label: "客戶" },
    { key: "pm", label: "PM" },
    { key: "status", label: "狀態" },
    { key: "planned", label: "預計完成日期" },
    { key: "actual", label: "實際完成日期" }
  ];

  function formatValue(value) {
    if (value === null || value === undefined || value === "") return "—";
    return String(value);
  }

  function buildTable(records, columns) {
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

  function renderProjectList(projects) {
    var container = document.getElementById("history-overview-content");
    container.innerHTML = "";

    if (projects.length === 0) {
      var empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent = "目前無符合條件的專案";
      container.appendChild(empty);
      return;
    }

    var rows = projects.map(function (project) {
      var summary = projectDateSummary(project.project_name);
      return {
        project_name: project.project_name,
        customer: project.customer,
        pm: project.pm,
        status: project.status,
        planned: summary.planned,
        actual: summary.actual === null ? "進行中" : summary.actual
      };
    });

    container.appendChild(buildTable(rows, PROJECT_LIST_COLUMNS));
  }

  // ── 甘特圖（手刻 SVG，每個專案一列，每個任務一個色塊） ──

  var GANTT_ROW_HEIGHT = 42;
  var GANTT_PADDING_LEFT = 140;
  var GANTT_PADDING_RIGHT = 16;
  var GANTT_PADDING_TOP = 16;
  var GANTT_WIDTH = 720;

  function parseDate(value) {
    if (!value) return null;
    var d = new Date(value);
    return isNaN(d.getTime()) ? null : d;
  }

  function shortDate(dateStr) {
    var parts = String(dateStr).split("-");
    return parts.length === 3 ? parts[1] + "/" + parts[2] : dateStr;
  }

  function renderGanttChart(projects) {
    var container = document.getElementById("history-overview-content");
    container.innerHTML = "";

    if (projects.length === 0) {
      var empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent = "目前無符合條件的專案";
      container.appendChild(empty);
      return;
    }

    var allDates = HISTORY_TASKS.map(function (t) { return parseDate(t.planned_completion_date); })
      .concat(HISTORY_TASKS.map(function (t) { return parseDate(t.actual_completion_date); }))
      .filter(Boolean);
    var today = new Date();
    var minDate = new Date(Math.min.apply(null, allDates.concat([today]).map(function (d) { return d.getTime(); })));
    var maxDate = new Date(Math.max.apply(null, allDates.concat([today]).map(function (d) { return d.getTime(); })));
    var totalSpan = Math.max(maxDate.getTime() - minDate.getTime(), 1);

    var plotWidth = GANTT_WIDTH - GANTT_PADDING_LEFT - GANTT_PADDING_RIGHT;
    var height = GANTT_PADDING_TOP + projects.length * GANTT_ROW_HEIGHT + 30;

    function xAt(date) {
      return GANTT_PADDING_LEFT + ((date.getTime() - minDate.getTime()) / totalSpan) * plotWidth;
    }

    var svg = document.createElementNS(svgNS, "svg");
    svg.setAttribute("viewBox", "0 0 " + GANTT_WIDTH + " " + height);
    svg.setAttribute("class", "gantt-svg");
    svg.setAttribute("role", "img");
    svg.setAttribute("aria-label", "專案歷程甘特圖");

    projects.forEach(function (project, rowIndex) {
      var rowY = GANTT_PADDING_TOP + rowIndex * GANTT_ROW_HEIGHT;

      var label = document.createElementNS(svgNS, "text");
      label.setAttribute("x", GANTT_PADDING_LEFT - 8);
      label.setAttribute("y", rowY + GANTT_ROW_HEIGHT / 2 + 4);
      label.setAttribute("text-anchor", "end");
      label.setAttribute("class", "gantt-row-label");
      label.textContent = project.project_name;
      svg.appendChild(label);

      var rowLine = document.createElementNS(svgNS, "line");
      rowLine.setAttribute("x1", GANTT_PADDING_LEFT);
      rowLine.setAttribute("x2", GANTT_WIDTH - GANTT_PADDING_RIGHT);
      rowLine.setAttribute("y1", rowY + GANTT_ROW_HEIGHT / 2);
      rowLine.setAttribute("y2", rowY + GANTT_ROW_HEIGHT / 2);
      rowLine.setAttribute("class", "gantt-row-baseline");
      svg.appendChild(rowLine);

      var tasks = HISTORY_TASKS.filter(function (t) { return t.project_name === project.project_name; });
      tasks.forEach(function (task) {
        var start = parseDate(task.planned_completion_date);
        if (!start) return;
        var end = parseDate(task.actual_completion_date) || today;
        var x1 = xAt(start);
        var x2 = Math.max(xAt(end), x1 + 4);

        var rect = document.createElementNS(svgNS, "rect");
        rect.setAttribute("x", x1);
        rect.setAttribute("y", rowY + 8);
        rect.setAttribute("width", x2 - x1);
        rect.setAttribute("height", GANTT_ROW_HEIGHT - 16);
        rect.setAttribute("rx", 4);
        rect.setAttribute("class", task.actual_completion_date ? "gantt-task-done" : "gantt-task-open");

        var title = document.createElementNS(svgNS, "title");
        title.textContent = task.task_name + "（" + task.status + "）" +
          shortDate(task.planned_completion_date) + " ～ " +
          (task.actual_completion_date ? shortDate(task.actual_completion_date) : "進行中");
        rect.appendChild(title);

        svg.appendChild(rect);
      });
    });

    container.appendChild(svg);
  }

  function renderContent() {
    var filtered = applyFilters(HISTORY_PROJECTS);
    if (state.viewMode === "gantt") {
      renderGanttChart(filtered);
    } else {
      renderProjectList(filtered);
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
