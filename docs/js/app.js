(function () {
  "use strict";

  // ── 日期工具 ──────────────────────────────────────────────

  function startOfDay(date) {
    var d = new Date(date);
    d.setHours(0, 0, 0, 0);
    return d;
  }

  function daysFromToday(offset) {
    var d = startOfDay(new Date());
    d.setDate(d.getDate() + offset);
    return d.toISOString().slice(0, 10);
  }

  function getWeekRange(date) {
    var d = startOfDay(date);
    var day = d.getDay(); // 0=Sun ... 6=Sat
    var mondayOffset = day === 0 ? -6 : 1 - day;
    var monday = new Date(d);
    monday.setDate(d.getDate() + mondayOffset);
    var sunday = new Date(monday);
    sunday.setDate(monday.getDate() + 6);
    sunday.setHours(23, 59, 59, 999);
    return { start: monday, end: sunday };
  }

  // 挑選本週內、但相對「今天」尚未逾期的日期（今天或今天+1天，不超過本週週日），
  // 用來示範「本週到期但尚未逾期」的情境。
  function thisWeekDueSoon() {
    var today = startOfDay(new Date());
    var range = getWeekRange(today);
    var tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);
    var candidate = tomorrow.getTime() <= range.end.getTime() ? tomorrow : today;
    return candidate.toISOString().slice(0, 10);
  }

  // ── 模擬資料 ──────────────────────────────────────────────
  // task_type 對齊真實 Google Sheets 的 5 個類型分頁（功能／PR／調整／遺漏／臭蟲，
  // 見 warroom-data-api-real-source 的 SheetsApiClient::SHEET_NAMES）。
  // 部分任務的 planned_completion_date 相對「今天」動態產生，確保逾期／本週到期
  // 篩選在任何檢視時間點都能展示效果。
  var RECORDS = [
    { project_name: "Project Alpha", task_name: "Initial setup", task_type: "功能", status: "completed", owner: "Alice", planned_completion_date: "2024-01-15", actual_completion_date: "2024-01-20", delay_days: 2 },
    { project_name: "Project Alpha", task_name: "Design phase", task_type: "調整", status: "completed", owner: "Bob", planned_completion_date: "2024-01-21", actual_completion_date: "2024-02-05", delay_days: 0 },
    { project_name: "Project Alpha", task_name: "Implementation", task_type: "功能", status: "completed", owner: "Charlie", planned_completion_date: "2024-02-06", actual_completion_date: "2024-02-20", delay_days: -3 },
    { project_name: "Project Alpha", task_name: "Overdue feature review", task_type: "功能", status: "in_progress", owner: "Alice", planned_completion_date: daysFromToday(-3), actual_completion_date: null, delay_days: null },
    { project_name: "Project Alpha", task_name: "PR review backlog", task_type: "PR", status: "in_progress", owner: "Bob", planned_completion_date: thisWeekDueSoon(), actual_completion_date: null, delay_days: null },
    { project_name: "Project Beta", task_name: "Requirements gathering", task_type: "臭蟲", status: "completed", owner: "David", planned_completion_date: "2024-02-01", actual_completion_date: "2024-02-10", delay_days: 1 },
    { project_name: "Project Beta", task_name: "Development", task_type: "功能", status: "in_progress", owner: "Eve", planned_completion_date: thisWeekDueSoon(), actual_completion_date: null, delay_days: null },
    { project_name: "Project Beta", task_name: "Testing", task_type: "遺漏", status: "pending", owner: "Frank", planned_completion_date: daysFromToday(10), actual_completion_date: null, delay_days: null },
    { project_name: "Project Beta", task_name: "PR fix urgent", task_type: "PR", status: "in_progress", owner: "Eve", planned_completion_date: daysFromToday(-1), actual_completion_date: null, delay_days: null }
  ];

  var COLUMNS = [
    { key: "task_name", label: "任務名稱" },
    { key: "task_type", label: "類型" },
    { key: "status", label: "狀態" },
    { key: "owner", label: "負責人" },
    { key: "planned_completion_date", label: "預計完成日期" },
    { key: "actual_completion_date", label: "實際完成日期" },
    { key: "delay_days", label: "延誤天數" }
  ];

  var STATUS_LABELS = {
    completed: "已完成",
    in_progress: "進行中",
    pending: "待開始"
  };

  var PRIORITY_TYPES = ["功能", "PR"];

  // ── 篩選狀態 ──────────────────────────────────────────────

  var state = {
    project: null,                    // null = 全部專案（預設）
    typeFilters: PRIORITY_TYPES.slice(), // 預設多選「功能」與「PR」
    scopeFilter: "due_this_week",     // "all" | "due_this_week" | "overdue"（預設本週到期，含已逾期）
    incompleteOnly: true              // 預設開啟，畫面主要聚焦未完成／逾期任務
  };

  // ── 篩選與統計邏輯 ────────────────────────────────────────

  function groupByProject(records) {
    return records.reduce(function (groups, record) {
      var key = record.project_name;
      groups[key] = groups[key] || [];
      groups[key].push(record);
      return groups;
    }, {});
  }

  function isOverdue(task, today) {
    if (task.status === "completed" || !task.planned_completion_date) return false;
    return new Date(task.planned_completion_date) < today;
  }

  // 本週到期：預計完成日不晚於本週週日（含過去所有已逾期任務，不限於本週內），
  // 且尚未完成。與 isOverdue 的差異：isOverdue 只看「早於今天」，這裡看「不晚於本週週日」。
  function isDueByThisWeekEnd(task, weekRange) {
    if (task.status === "completed" || !task.planned_completion_date) return false;
    var d = new Date(task.planned_completion_date);
    return d <= weekRange.end;
  }

  function matchesProjectAndType(task, currentState) {
    if (currentState.project && task.project_name !== currentState.project) return false;
    if (currentState.typeFilters.length > 0 && currentState.typeFilters.indexOf(task.task_type) === -1) return false;
    return true;
  }

  function filterTasks(records, currentState, today, weekRange) {
    return records.filter(function (t) {
      if (!matchesProjectAndType(t, currentState)) return false;
      if (currentState.incompleteOnly && t.status === "completed") return false;
      if (currentState.scopeFilter === "overdue" && !isOverdue(t, today)) return false;
      if (currentState.scopeFilter === "due_this_week" && !isDueByThisWeekEnd(t, weekRange)) return false;
      return true;
    });
  }

  function computeSummary(records, currentState, today) {
    var scoped = records.filter(function (t) { return matchesProjectAndType(t, currentState); });
    return {
      total: scoped.length,
      completed: scoped.filter(function (t) { return t.status === "completed"; }).length,
      in_progress: scoped.filter(function (t) { return t.status === "in_progress"; }).length,
      pending: scoped.filter(function (t) { return t.status === "pending"; }).length,
      overdue: scoped.filter(function (t) { return isOverdue(t, today); }).length
    };
  }

  function sortOverdueFirst(tasks, today) {
    return tasks.slice().sort(function (a, b) {
      var aOverdue = isOverdue(a, today) ? 0 : 1;
      var bOverdue = isOverdue(b, today) ? 0 : 1;
      return aOverdue - bOverdue;
    });
  }

  // ── 渲染輔助 ──────────────────────────────────────────────

  function formatValue(value) {
    if (value === null || value === undefined || value === "") {
      return "—";
    }
    return String(value);
  }

  function delayClass(value) {
    if (typeof value !== "number") return "";
    if (value < 0) return "delay-negative";
    if (value > 0) return "delay-positive";
    return "";
  }

  function buildTable(tasks, today) {
    var table = document.createElement("table");
    table.className = "project-tasks";

    var thead = document.createElement("thead");
    var headRow = document.createElement("tr");
    COLUMNS.forEach(function (column) {
      var th = document.createElement("th");
      th.scope = "col";
      th.textContent = column.label;
      headRow.appendChild(th);
    });
    thead.appendChild(headRow);
    table.appendChild(thead);

    var tbody = document.createElement("tbody");
    tasks.forEach(function (task) {
      var row = document.createElement("tr");
      COLUMNS.forEach(function (column) {
        var td = document.createElement("td");
        td.setAttribute("data-label", column.label);
        var value = task[column.key];

        if (column.key === "status") {
          var badge = document.createElement("span");
          badge.className = "status-badge status-" + value;
          badge.textContent = STATUS_LABELS[value] || value;
          td.appendChild(badge);
        } else if (column.key === "task_name") {
          td.appendChild(document.createTextNode(formatValue(value)));
          if (isOverdue(task, today)) {
            var tag = document.createElement("span");
            tag.className = "overdue-tag";
            tag.textContent = "逾期";
            td.appendChild(tag);
          }
        } else {
          td.textContent = formatValue(value);
          if (column.key === "delay_days") {
            var cls = delayClass(value);
            if (cls) td.classList.add(cls);
          }
        }
        row.appendChild(td);
      });
      tbody.appendChild(row);
    });
    table.appendChild(tbody);

    return table;
  }

  function renderSummary(summary) {
    var el = document.getElementById("summary");
    el.innerHTML = "";

    var items = [
      { label: "任務總數", value: summary.total },
      { label: "已完成", value: summary.completed },
      { label: "進行中", value: summary.in_progress },
      { label: "待開始", value: summary.pending },
      { label: "逾期", value: summary.overdue, className: "stat-overdue" }
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

  function render() {
    var today = startOfDay(new Date());
    var weekRange = getWeekRange(today);

    renderSummary(computeSummary(RECORDS, state, today));

    var content = document.getElementById("content");
    content.innerHTML = "";

    // 預設專案範圍 = 全部專案；state.project 非 null 時才收斂為單一專案
    var projectScoped = RECORDS.filter(function (t) {
      return !state.project || t.project_name === state.project;
    });
    var groupedAll = groupByProject(projectScoped);
    var projectNames = Object.keys(groupedAll);

    if (projectNames.length === 0) {
      var empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent = "目前無資料";
      content.appendChild(empty);
      return;
    }

    projectNames.forEach(function (projectName) {
      var tasks = sortOverdueFirst(
        filterTasks(groupedAll[projectName], state, today, weekRange),
        today
      );

      var section = document.createElement("section");
      section.className = "project-block";

      var heading = document.createElement("h2");
      heading.textContent = projectName;
      section.appendChild(heading);

      if (tasks.length === 0) {
        var emptyBlock = document.createElement("p");
        emptyBlock.className = "empty-state";
        emptyBlock.textContent = "目前無符合條件的任務";
        section.appendChild(emptyBlock);
      } else {
        section.appendChild(buildTable(tasks, today));
      }

      content.appendChild(section);
    });
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

  // ── 控制項初始化 ──────────────────────────────────────────

  function populateProjectSelect() {
    var select = document.getElementById("project");
    var grouped = groupByProject(RECORDS);

    var allOption = document.createElement("option");
    allOption.value = "";
    allOption.textContent = "全部專案（" + RECORDS.length + "）";
    select.appendChild(allOption);

    Object.keys(grouped).forEach(function (projectName) {
      var option = document.createElement("option");
      option.value = projectName;
      option.textContent = projectName + "（" + grouped[projectName].length + "）";
      select.appendChild(option);
    });

    select.value = "";

    select.addEventListener("change", function () {
      state.project = select.value || null;
      render();
    });
  }

  function sortedTaskTypes() {
    var types = [];
    RECORDS.forEach(function (t) {
      if (types.indexOf(t.task_type) === -1) types.push(t.task_type);
    });
    types.sort(function (a, b) {
      var aPriority = PRIORITY_TYPES.indexOf(a);
      var bPriority = PRIORITY_TYPES.indexOf(b);
      if (aPriority === -1 && bPriority === -1) return 0;
      if (aPriority === -1) return 1;
      if (bPriority === -1) return -1;
      return aPriority - bPriority;
    });
    return types;
  }

  // 任務類型為多選 checkbox，預設勾選「功能」與「PR」（見 PRIORITY_TYPES）
  function initTypeFilter() {
    var container = document.getElementById("type-filter");

    sortedTaskTypes().forEach(function (type) {
      var label = document.createElement("label");
      var checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.value = type;
      checkbox.checked = state.typeFilters.indexOf(type) !== -1;
      checkbox.addEventListener("change", function () {
        var idx = state.typeFilters.indexOf(type);
        if (checkbox.checked && idx === -1) {
          state.typeFilters.push(type);
        } else if (!checkbox.checked && idx !== -1) {
          state.typeFilters.splice(idx, 1);
        }
        render();
      });
      label.appendChild(checkbox);
      label.appendChild(document.createTextNode(" " + type));
      container.appendChild(label);
    });
  }

  function initIncompleteToggle() {
    var checkbox = document.getElementById("incomplete-only");
    checkbox.checked = state.incompleteOnly;
    checkbox.addEventListener("change", function () {
      state.incompleteOnly = checkbox.checked;
      render();
    });
  }

  function initScopeFilter() {
    var radios = document.querySelectorAll('input[name="scope"]');
    radios.forEach(function (radio) {
      radio.checked = radio.value === state.scopeFilter;
      radio.addEventListener("change", function () {
        if (radio.checked) {
          state.scopeFilter = radio.value;
          render();
        }
      });
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    applyThemeToggleLabel(getCurrentTheme());
    var themeToggle = document.getElementById("theme-toggle");
    if (themeToggle) themeToggle.addEventListener("click", toggleTheme);

    var applyFilters = document.getElementById("apply-filters");
    if (applyFilters) applyFilters.addEventListener("click", render);

    populateProjectSelect();
    initTypeFilter();
    initIncompleteToggle();
    initScopeFilter();
    render();
  });
})();
