(function () {
  "use strict";

  var svgNS = "http://www.w3.org/2000/svg";

  // 完全獨立實作，不與既有專案歷程（project-history-*.js）共用程式碼（同既有慣例）。
  // 資料來源改為 Notion（見 PROJECT_PROFILES／PHASE_RECORDS／STAGE_ORDER，project-phase-tracking-data.js）。

  // 三個篩選條件（客戶／狀態／PM）皆不篩選＝全部；同時選取時取交集。排序預設「不排序」。
  // editedActualDates：使用者互動編輯「實際完成日期」的暫存值，key 為 `${project_name}::${stage}`，
  // 與 PHASE_RECORDS 完全分離，不得寫回 PHASE_RECORDS（見需求 4.9）。
  var state = {
    filters: { customer: null, status: null, pm: null },
    sort: null,
    viewMode: "list",
    editedActualDates: {}
  };

  // ── 共用小工具 ──────────────────────────────────────────────

  function uniqueValues(records, key) {
    var values = [];
    records.forEach(function (r) {
      if (values.indexOf(r[key]) === -1) values.push(r[key]);
    });
    return values;
  }

  function populateSelect(select, values, allLabel) {
    select.innerHTML = "";
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

  function formatValue(value) {
    if (value === null || value === undefined || value === "") return "—";
    return String(value);
  }

  // ── 日期與完成狀態計算（清單／甘特圖共用，見需求 4.5、3.3 的不變式） ──────

  // 拆解 "YYYY-MM-DD" 年/月/日以 Date.UTC 建構，避免直接 new Date(str) 受瀏覽器時區影響
  // （需求 4.4）。格式不合法或缺失（含 "2026/08/20"、"2026-99-99" 等 truthy 但不合法的字串）
  // 一律回傳 null。
  function parseDateOnly(dateStr) {
    if (typeof dateStr !== "string") return null;
    var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateStr);
    if (!match) return null;
    var year = Number(match[1]);
    var month = Number(match[2]);
    var day = Number(match[3]);
    var ms = Date.UTC(year, month - 1, day);
    var check = new Date(ms);
    if (check.getUTCFullYear() !== year || check.getUTCMonth() !== month - 1 || check.getUTCDate() !== day) {
      return null;
    }
    return ms;
  }

  function diffDays(actualDate, plannedDate) {
    var actualMs = parseDateOnly(actualDate);
    var plannedMs = parseDateOnly(plannedDate);
    if (actualMs === null || plannedMs === null) return null;
    return Math.round((actualMs - plannedMs) / 86400000);
  }

  function todayUtcMs() {
    var now = new Date();
    return Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
  }

  // 依 plannedDate／actualDate 是否存在（parseDateOnly 驗證通過視為存在）的組合判斷，回傳
  // { completionLabel, diffDays }。renderStageTable／renderGanttChart 皆呼叫本函式，不得各自
  // 重新實作，避免規則修改時兩處不一致（需求 4.5）。
  function computeRowState(plannedDate, actualDate) {
    var hasPlanned = parseDateOnly(plannedDate) !== null;
    if (actualDate !== null) {
      return { completionLabel: "已完成", diffDays: hasPlanned ? diffDays(actualDate, plannedDate) : null };
    }
    return { completionLabel: hasPlanned ? "未完成" : "—", diffDays: null };
  }

  // 依 STAGE_ORDER 從 PHASE_RECORDS 找出該專案對應紀錄；找不到時回傳缺失列（需求 4.6）。
  // 若 state.editedActualDates 有對應 key，覆寫該列 actual_date（不修改 PHASE_RECORDS 本身，需求 4.9）。
  function buildStageRows(projectName) {
    return STAGE_ORDER.map(function (stage) {
      var record = null;
      for (var i = 0; i < PHASE_RECORDS.length; i++) {
        if (PHASE_RECORDS[i].project === projectName && PHASE_RECORDS[i].stage === stage) {
          record = PHASE_RECORDS[i];
          break;
        }
      }
      var row = record
        ? { stage: stage, planned_date: record.planned_date, actual_date: record.actual_date, reason: record.reason }
        : { stage: stage, planned_date: null, actual_date: null, reason: "" };

      var editKey = projectName + "::" + stage;
      if (Object.prototype.hasOwnProperty.call(state.editedActualDates, editKey)) {
        row.actual_date = state.editedActualDates[editKey];
      }
      return row;
    });
  }

  // ── 篩選／排序 ──────────────────────────────────────────────

  function initFilters() {
    var customerSelect = document.getElementById("filter-customer");
    var statusSelect = document.getElementById("filter-status");
    var pmSelect = document.getElementById("filter-pm");

    populateSelect(customerSelect, uniqueValues(PROJECT_PROFILES, "customer"), "全部客戶");
    populateSelect(statusSelect, uniqueValues(PROJECT_PROFILES, "status"), "全部狀態");
    populateSelect(pmSelect, uniqueValues(PROJECT_PROFILES, "pm"), "全部 PM");

    customerSelect.addEventListener("change", function () {
      state.filters.customer = customerSelect.value || null;
      renderContent();
    });
    statusSelect.addEventListener("change", function () {
      state.filters.status = statusSelect.value || null;
      renderContent();
    });
    pmSelect.addEventListener("change", function () {
      state.filters.pm = pmSelect.value || null;
      renderContent();
    });
  }

  function initSort() {
    var sortSelect = document.getElementById("sort-select");
    sortSelect.addEventListener("change", function () {
      state.sort = sortSelect.value || null;
      renderContent();
    });
  }

  function applyFilters(profiles) {
    return profiles.filter(function (profile) {
      if (state.filters.customer && profile.customer !== state.filters.customer) return false;
      if (state.filters.status && profile.status !== state.filters.status) return false;
      if (state.filters.pm && profile.pm !== state.filters.pm) return false;
      return true;
    });
  }

  // 依需求 2.3 表格排序；不排序時維持原始順序。Array.prototype.sort 為現代瀏覽器的穩定排序，
  // 鍵值相同時自動維持原始相對順序（需求 2.4），不需額外 index 比較。
  function applySort(profiles) {
    var sorted = profiles.slice();
    if (state.sort === "planned_date") {
      sorted.sort(function (a, b) {
        var aMs = parseDateOnly(a.planned_completion_date);
        var bMs = parseDateOnly(b.planned_completion_date);
        if (aMs === null && bMs === null) return 0;
        if (aMs === null) return 1;
        if (bMs === null) return -1;
        return aMs - bMs;
      });
    } else if (state.sort === "status") {
      sorted.sort(function (a, b) { return String(a.status).localeCompare(String(b.status), "zh-Hant"); });
    } else if (state.sort === "customer") {
      sorted.sort(function (a, b) { return String(a.customer).localeCompare(String(b.customer), "zh-Hant"); });
    }
    return sorted;
  }

  // ── 清單檢視（專案卡片原地展開，<details>/<summary>） ──────────────

  function diffCell(rowState) {
    var td = document.createElement("td");
    td.setAttribute("data-label", "差異");
    if (rowState.diffDays === null) {
      td.textContent = "—";
    } else if (rowState.diffDays > 0) {
      td.textContent = "+" + rowState.diffDays;
      td.className = "delay-positive";
    } else if (rowState.diffDays < 0) {
      td.textContent = String(rowState.diffDays);
      td.className = "delay-negative";
    } else {
      td.textContent = "0";
    }
    return td;
  }

  function renderStageRows(tbody, projectName) {
    tbody.innerHTML = "";
    buildStageRows(projectName).forEach(function (row) {
      var tr = document.createElement("tr");

      var stageTd = document.createElement("td");
      stageTd.setAttribute("data-label", "階段");
      stageTd.textContent = row.stage;
      tr.appendChild(stageTd);

      var plannedTd = document.createElement("td");
      plannedTd.setAttribute("data-label", "預計完成日期");
      plannedTd.textContent = parseDateOnly(row.planned_date) !== null ? row.planned_date : "—";
      tr.appendChild(plannedTd);

      var actualTd = document.createElement("td");
      actualTd.setAttribute("data-label", "實際完成日期");
      var input = document.createElement("input");
      input.type = "date";
      input.value = parseDateOnly(row.actual_date) !== null ? row.actual_date : "";
      input.addEventListener("change", function () {
        var key = projectName + "::" + row.stage;
        state.editedActualDates[key] = input.value || null;
        renderStageRows(tbody, projectName);
      });
      actualTd.appendChild(input);
      tr.appendChild(actualTd);

      var rowState = computeRowState(row.planned_date, row.actual_date);
      tr.appendChild(diffCell(rowState));

      var statusTd = document.createElement("td");
      statusTd.setAttribute("data-label", "完成狀態");
      statusTd.textContent = rowState.completionLabel;
      tr.appendChild(statusTd);

      tbody.appendChild(tr);

      if (row.reason) {
        var reasonTr = document.createElement("tr");
        reasonTr.className = "phase-reason-row";
        var reasonTd = document.createElement("td");
        reasonTd.colSpan = 5;
        reasonTd.className = "phase-reason";
        reasonTd.textContent = "備註：" + row.reason;
        reasonTr.appendChild(reasonTd);
        tbody.appendChild(reasonTr);
      }
    });
  }

  function buildStageTable(projectName) {
    var table = document.createElement("table");
    table.className = "project-tasks";

    var thead = document.createElement("thead");
    var headRow = document.createElement("tr");
    ["階段", "預計完成日期", "實際完成日期", "差異", "完成狀態"].forEach(function (label) {
      var th = document.createElement("th");
      th.scope = "col";
      th.textContent = label;
      headRow.appendChild(th);
    });
    thead.appendChild(headRow);
    table.appendChild(thead);

    var tbody = document.createElement("tbody");
    table.appendChild(tbody);
    renderStageRows(tbody, projectName);

    return table;
  }

  function buildProjectCard(profile) {
    var details = document.createElement("details");
    details.className = "project-card";

    var summary = document.createElement("summary");
    summary.className = "project-card-summary";

    var name = document.createElement("span");
    name.className = "project-card-name";
    name.textContent = profile.project_name;
    summary.appendChild(name);

    var tags = document.createElement("span");
    tags.className = "project-card-tags";
    [
      [null, formatValue(profile.customer)],
      [null, formatValue(profile.pm)],
      ["tag-status", formatValue(profile.status)],
      [null, "預計完成：" + formatValue(profile.planned_completion_date)]
    ].forEach(function (pair) {
      var tag = document.createElement("span");
      tag.className = "tag" + (pair[0] ? " " + pair[0] : "");
      tag.textContent = pair[1];
      tags.appendChild(tag);
    });
    summary.appendChild(tags);
    details.appendChild(summary);

    var body = document.createElement("div");
    body.className = "project-card-body";
    body.appendChild(buildStageTable(profile.project_name));
    details.appendChild(body);

    return details;
  }

  function renderProjectCards(profiles) {
    var container = document.getElementById("phase-tracking-content");
    container.innerHTML = "";

    if (profiles.length === 0) {
      var empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent = "目前無符合條件的專案";
      container.appendChild(empty);
      return;
    }

    var list = document.createElement("div");
    list.className = "project-card-list";
    profiles.forEach(function (profile) { list.appendChild(buildProjectCard(profile)); });
    container.appendChild(list);
  }

  // ── 甘特圖（階段進度差異圖：以 planned_date 為錨點，非傳統起訖排程甘特圖） ──────

  var GANTT_ROW_HEIGHT = 42;
  var GANTT_PADDING_LEFT = 152;
  var GANTT_PADDING_RIGHT = 16;
  var GANTT_PADDING_TOP = 28;
  var GANTT_PADDING_BOTTOM = 8;
  var GANTT_MIN_WIDTH = 900; // 需求 3.5：SVG 最小寬度
  var GANTT_PIXELS_PER_DAY = 24;
  var GANTT_BAR_HEIGHT = 14;

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

  // minDateMs＝全體有效 planned_date 最小值；maxDateMs＝（全體有效 actual_date 最大值、今日、
  // minDateMs）三者取最大值。找不到任何有效 planned_date 時回傳 null（需求 3.3 empty-state）。
  function ganttDomain(profiles) {
    var plannedMsList = [];
    var actualMsList = [];
    profiles.forEach(function (profile) {
      buildStageRows(profile.project_name).forEach(function (row) {
        var plannedMs = parseDateOnly(row.planned_date);
        if (plannedMs !== null) plannedMsList.push(plannedMs);
        var actualMs = parseDateOnly(row.actual_date);
        if (actualMs !== null) actualMsList.push(actualMs);
      });
    });
    if (plannedMsList.length === 0) return null;
    var minMs = Math.min.apply(null, plannedMsList);
    var maxMs = Math.max.apply(null, actualMsList.concat([todayUtcMs(), minMs]));
    return { minMs: minMs, maxMs: maxMs };
  }

  function ganttSvgWidth(domain) {
    var days = (domain.maxMs - domain.minMs) / 86400000;
    var computedWidth = GANTT_PADDING_LEFT + GANTT_PADDING_RIGHT + days * GANTT_PIXELS_PER_DAY;
    return Math.max(GANTT_MIN_WIDTH, computedWidth);
  }

  function xAt(ms, domain, width) {
    var span = Math.max(domain.maxMs - domain.minMs, 86400000);
    var plotWidth = width - GANTT_PADDING_LEFT - GANTT_PADDING_RIGHT;
    return GANTT_PADDING_LEFT + ((ms - domain.minMs) / span) * plotWidth;
  }

  function monthTicks(domain, width) {
    var ticks = [];
    var minDate = new Date(domain.minMs);
    var cursor = Date.UTC(minDate.getUTCFullYear(), minDate.getUTCMonth(), 1);
    var left = GANTT_PADDING_LEFT;
    var right = width - GANTT_PADDING_RIGHT;
    while (cursor <= domain.maxMs) {
      var x = Math.max(left, Math.min(right, xAt(cursor, domain, width)));
      var cursorDate = new Date(cursor);
      var label = cursorDate.getUTCFullYear() + "/" + String(cursorDate.getUTCMonth() + 1).padStart(2, "0");
      ticks.push({ x: x, label: label });
      cursor = Date.UTC(cursorDate.getUTCFullYear(), cursorDate.getUTCMonth() + 1, 1);
    }
    return ticks;
  }

  function barTitle(row, rowState) {
    var diffText = rowState.diffDays === null
      ? ""
      : "｜差異 " + (rowState.diffDays > 0 ? "+" : "") + rowState.diffDays + " 天";
    return row.stage + "（" + rowState.completionLabel + "）｜預計 " + formatValue(row.planned_date) +
      " → 實際 " + formatValue(row.actual_date) + diffText;
  }

  // 每個階段色塊左端點固定為 planned_date；依需求 3.3 規則決定右端點與樣式。planned_date
  // 缺失或格式不合法時無法定位左端點，不繪製色塊（回傳 null），但該階段的資料邏輯仍照常存在
  // （清單檢視仍會顯示該列「—」）。
  function stageBar(row, domain, width) {
    var plannedMs = parseDateOnly(row.planned_date);
    if (plannedMs === null) return null;

    var rowState = computeRowState(row.planned_date, row.actual_date);
    var x1 = xAt(plannedMs, domain, width);

    if (row.actual_date !== null && rowState.diffDays !== null) {
      if (rowState.diffDays >= 0) {
        var actualMs = parseDateOnly(row.actual_date);
        var x2 = Math.max(xAt(actualMs, domain, width), x1 + 2);
        return { x: x1, width: x2 - x1, variant: "delayed", title: barTitle(row, rowState) };
      }
      // 提前完成：不畫「預計→實際」的真實日期區間（那會產生反向色塊），改以提前天數的絕對值
      // 等比例延伸，代表「提前幅度」的視覺標記，並非該階段的實際完成日期區間。
      var earlyEndMs = plannedMs + Math.abs(rowState.diffDays) * 86400000;
      var earlyX2 = Math.max(xAt(earlyEndMs, domain, width), x1 + 2);
      return { x: x1, width: earlyX2 - x1, variant: "early", title: barTitle(row, rowState) };
    }

    // 未完成：延伸至今日
    var todayX = Math.max(xAt(todayUtcMs(), domain, width), x1 + 2);
    return { x: x1, width: todayX - x1, variant: "incomplete", title: barTitle(row, rowState) };
  }

  var GANTT_VARIANT_CLASS = {
    delayed: "gantt-task-actual-delayed",
    early: "gantt-task-actual-early",
    incomplete: "gantt-task-planned"
  };

  function renderGanttLegend(container) {
    var legend = document.createElement("div");
    legend.className = "gantt-legend";
    legend.setAttribute("role", "note");
    legend.setAttribute("aria-label", "甘特圖圖例");
    [
      ["legend-swatch-delayed", "已完成（延伸至實際完成日期）"],
      ["legend-swatch-ontime", "提前完成（色塊寬度＝提前天數，非真實日期區間）"],
      ["legend-swatch-planned", "未完成（延伸至今日）"]
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

  function renderGanttChart(profiles) {
    var container = document.getElementById("phase-tracking-content");
    container.innerHTML = "";

    if (profiles.length === 0) {
      var emptyProfiles = document.createElement("p");
      emptyProfiles.className = "empty-state";
      emptyProfiles.textContent = "目前無符合條件的專案";
      container.appendChild(emptyProfiles);
      return;
    }

    var domain = ganttDomain(profiles);
    if (!domain) {
      var emptyDomain = document.createElement("p");
      emptyDomain.className = "empty-state";
      emptyDomain.textContent = "目前無可繪製的甘特圖資料";
      container.appendChild(emptyDomain);
      return;
    }

    renderGanttLegend(container);

    var width = ganttSvgWidth(domain);
    var height = GANTT_PADDING_TOP + profiles.length * GANTT_ROW_HEIGHT + GANTT_PADDING_BOTTOM;
    var rowsBottom = GANTT_PADDING_TOP + profiles.length * GANTT_ROW_HEIGHT;

    var scrollWrap = document.createElement("div");
    scrollWrap.className = "gantt-scroll";

    var svg = svgEl("svg", {
      viewBox: "0 0 " + width + " " + height,
      width: width,
      height: height,
      "class": "gantt-svg",
      role: "img",
      "aria-label": "專案階段追蹤甘特圖"
    });

    monthTicks(domain, width).forEach(function (tick) {
      svg.appendChild(svgEl("line", {
        x1: tick.x, x2: tick.x, y1: GANTT_PADDING_TOP, y2: rowsBottom, "class": "gantt-month-gridline"
      }));
      var label = svgEl("text", { x: tick.x, y: 16, "text-anchor": "start", "class": "gantt-month-label" });
      label.textContent = tick.label;
      svg.appendChild(label);
    });

    var todayX = xAt(todayUtcMs(), domain, width);
    if (todayX >= GANTT_PADDING_LEFT && todayX <= width - GANTT_PADDING_RIGHT) {
      svg.appendChild(svgEl("line", {
        x1: todayX, x2: todayX, y1: GANTT_PADDING_TOP, y2: rowsBottom, "class": "gantt-today-line"
      }));
    }

    profiles.forEach(function (profile, rowIndex) {
      var rowY = GANTT_PADDING_TOP + rowIndex * GANTT_ROW_HEIGHT;

      var label = svgEl("text", {
        x: GANTT_PADDING_LEFT - 8, y: rowY + GANTT_ROW_HEIGHT / 2 + 4, "text-anchor": "end", "class": "gantt-row-label"
      });
      label.textContent = profile.project_name;
      svg.appendChild(label);

      svg.appendChild(svgEl("line", {
        x1: GANTT_PADDING_LEFT, x2: width - GANTT_PADDING_RIGHT,
        y1: rowY + GANTT_ROW_HEIGHT / 2, y2: rowY + GANTT_ROW_HEIGHT / 2, "class": "gantt-row-baseline"
      }));

      var barY = rowY + (GANTT_ROW_HEIGHT - GANTT_BAR_HEIGHT) / 2;
      buildStageRows(profile.project_name).forEach(function (row) {
        var bar = stageBar(row, domain, width);
        if (!bar) return;
        var rect = svgEl("rect", {
          x: bar.x, y: barY, width: bar.width, height: GANTT_BAR_HEIGHT, rx: 2,
          "class": GANTT_VARIANT_CLASS[bar.variant]
        });
        appendTitle(rect, bar.title);
        svg.appendChild(rect);
      });
    });

    scrollWrap.appendChild(svg);
    container.appendChild(scrollWrap);
  }

  // ── 檢視切換與初始化 ──────────────────────────────────────────

  function renderContent() {
    var profiles = applySort(applyFilters(PROJECT_PROFILES));
    if (state.viewMode === "gantt") {
      renderGanttChart(profiles);
    } else {
      renderProjectCards(profiles);
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

  // ── 主題切換（與既有頁面共用同一套慣例，非另建邏輯） ──────────────────

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

  document.addEventListener("DOMContentLoaded", function () {
    initFilters();
    initSort();
    initViewToggle();
    renderContent();

    applyThemeToggleLabel(getCurrentTheme());
    var themeToggle = document.getElementById("theme-toggle");
    if (themeToggle) themeToggle.addEventListener("click", toggleTheme);
  });
})();
