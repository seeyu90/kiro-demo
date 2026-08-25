(function () {
  "use strict";

  var svgNS = "http://www.w3.org/2000/svg";

  // 完全獨立實作，不與既有專案歷程（project-history-*.js）共用程式碼（同既有慣例）。2026-08-25
  // 隨 Rails 真實資料串接（warroom-project-phase-tracking-real-source）大幅調整過設計，這份
  // 靜態展示版同步更新，邏輯對照 warroom-data-api-prototype/app/helpers/
  // project_phase_tracking_helper.rb、app/actors/sheets/fetch_phase_tracking.rb、
  // app/controllers/project_phase_tracking_controller.rb。

  // 篩選預設：狀態＝未完成、年度＝今年（比照 Rails Controller 的 resolve_status／resolve_year
  // 慣例），使用者可明確選「全部」。本頁唯讀，沒有排序選單（固定依預計完成日期排序）、沒有
  // 「只顯示未完成」勾選框（狀態下拉已經有「未完成」可選，功能重疊）。
  var state = {
    filters: { customer: null, status: "未完成", pm: null, year: String(new Date().getFullYear()) },
    query: "",
    viewMode: "list"
  };

  // ── 共用小工具 ──────────────────────────────────────────────

  function formatValue(value) {
    if (value === null || value === undefined || value === "") return "—";
    return String(value);
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
      select.appendChild(option);
    });
    select.value = selectedValue || "";
  }

  // ── 日期與完成狀態計算（清單／甘特圖共用，同 Ruby 版 ProjectPhaseTrackingHelper 不變式：
  // 兩處皆呼叫本組函式，不得各自重新實作完成狀態或差異判斷邏輯） ──────────────

  // 拆解 "YYYY-MM-DD" 年/月/日以 Date.UTC 建構，避免直接 new Date(str) 受瀏覽器時區影響。
  // 格式不合法或缺失一律回傳 null。
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
  // { completionLabel, diffDays }。
  function computeRowState(plannedDate, actualDate) {
    var hasPlanned = parseDateOnly(plannedDate) !== null;
    if (actualDate !== null) {
      return { completionLabel: "已完成", diffDays: hasPlanned ? diffDays(actualDate, plannedDate) : null };
    }
    return { completionLabel: hasPlanned ? "未完成" : "—", diffDays: null };
  }

  // ── 卡片建構：依 (project, issue_id) 分組，不是只依 project——一個 project 代碼底下有多個
  // 獨立的 issue_id 生命週期。 ──────────────────────────────────────

  var STAGE_ORDER_INDEX = {};
  STAGE_ORDER.forEach(function (stage, i) { STAGE_ORDER_INDEX[stage] = i; });

  function issueLabel(card) {
    return card.issue_name ? card.issue_name + "（" + card.issue_id + "）" : card.issue_id;
  }

  function profilesByProject() {
    var map = {};
    PROJECT_PROFILES.forEach(function (p) { map[p.project] = p; });
    return map;
  }

  // 「狀態」指議題目前所在階段的完成狀態，不是專案層級的維運狀態（PROJECT_PROFILES 沒有狀態
  // 欄位）。取 STAGE_ORDER 由後往前第一個有主要記錄的階段之 status 欄位；完全沒有任何階段
  // 記錄時回傳 null（實務上不會發生，group_by 產生的卡片一定至少有一筆記錄）。
  function computeIssueStatus(stages) {
    for (var i = stages.length - 1; i >= 0; i--) {
      if (stages[i].primary) return stages[i].primary.status;
    }
    return null;
  }

  // 沒有獨立的「專案層級預計完成日期」欄位，改用終點階段（發布）的預計完成日期近似；「發布」
  // 缺紀錄時退回所有階段裡最晚的 planned_date。
  function computePlannedCompletionDate(stages) {
    var release = stages[STAGE_ORDER_INDEX["發布"]];
    if (release.primary && release.primary.planned_date) return release.primary.planned_date;
    var dates = stages
      .filter(function (s) { return s.primary && s.primary.planned_date; })
      .map(function (s) { return s.primary.planned_date; });
    if (dates.length === 0) return null;
    return dates.reduce(function (max, d) { return d > max ? d : max; });
  }

  function buildCards() {
    var groups = {};
    var order = [];
    PHASE_RECORDS.forEach(function (record) {
      var key = record.project + "|" + record.issue_id;
      if (!Object.prototype.hasOwnProperty.call(groups, key)) {
        groups[key] = [];
        order.push(key);
      }
      groups[key].push(record);
    });

    var profiles = profilesByProject();

    return order.map(function (key) {
      var records = groups[key];
      var project = records[0].project;
      var issueId = records[0].issue_id;
      // 同一 issue_id 底下各列理論上共用同一個 issue_name，取第一筆非空值。
      var issueName = records.map(function (r) { return r.issue_name; }).filter(Boolean)[0] || "";

      var stages = STAGE_ORDER.map(function (stageName) {
        var stageRecords = records.filter(function (r) { return r.stage === stageName; });
        // history 由新到舊排列：較新的重排記錄排在較舊的上面，最舊的排在最下面。
        var history = stageRecords.slice(0, -1).reverse();
        return { stage: stageName, primary: stageRecords[stageRecords.length - 1] || null, history: history };
      });

      var profile = profiles[project] || {};
      var recordYears = records
        .map(function (r) { return parseDateOnly(r.planned_date); })
        .filter(function (ms) { return ms !== null; })
        .map(function (ms) { return String(new Date(ms).getUTCFullYear()); });

      return {
        project: project,
        issue_id: issueId,
        issue_name: issueName,
        customer: profile.customer || null,
        pm: profile.pm || null,
        status: computeIssueStatus(stages),
        planned_completion_date: computePlannedCompletionDate(stages),
        stages: stages,
        record_years: recordYears
      };
    });
  }

  // ── 篩選／排序 ──────────────────────────────────────────────

  // 議題／專案代碼搜尋：issue_id 有時是描述性名稱，有時是純 Redmine ID（這種情況 issue_name
  // 會補上人類可讀名稱），對 issue_id／issue_name／project 三欄都做不分大小寫的子字串比對，
  // 符合其一即算命中。
  function matchesQuery(card, query) {
    if (!query) return true;
    var needle = query.toLowerCase();
    return [card.issue_id, card.issue_name, card.project].some(function (v) {
      return String(v || "").toLowerCase().indexOf(needle) !== -1;
    });
  }

  function applyFilters(cards) {
    return cards.filter(function (card) {
      if (state.filters.customer && card.customer !== state.filters.customer) return false;
      if (state.filters.status && card.status !== state.filters.status) return false;
      if (state.filters.pm && card.pm !== state.filters.pm) return false;
      if (state.filters.year && card.record_years.indexOf(state.filters.year) === -1) return false;
      if (!matchesQuery(card, state.query)) return false;
      return true;
    });
  }

  // 固定依預計完成日期排序，不給使用者選。缺 planned_completion_date 的排最後；
  // Array.prototype.sort 為現代瀏覽器的穩定排序，鍵值相同時自動維持原始相對順序。
  function applySort(cards) {
    var sorted = cards.slice();
    sorted.sort(function (a, b) {
      var aKey = a.planned_completion_date || "9999-99-99";
      var bKey = b.planned_completion_date || "9999-99-99";
      if (aKey < bKey) return -1;
      if (aKey > bKey) return 1;
      return 0;
    });
    return sorted;
  }

  // ── 狀態標籤配色（三段式，見 docs/css/style.css .tag-status-*） ──────────────

  var STATUS_TAG_CLASS = {
    "完成": "tag-status-done",
    "延誤已完成": "tag-status-done",
    "延誤未完成": "tag-status-pending",
    "未完成": "tag-status-pending",
    "暫緩": "tag-status-paused"
  };

  function statusTagClass(status) {
    return STATUS_TAG_CLASS[status] || "tag-status";
  }

  // ── 篩選列初始化 ──────────────────────────────────────────────

  function initFilters(allCards) {
    var customerSelect = document.getElementById("filter-customer");
    var statusSelect = document.getElementById("filter-status");
    var pmSelect = document.getElementById("filter-pm");
    var yearSelect = document.getElementById("filter-year");
    var querySelect = document.getElementById("filter-query");

    var customers = uniqueValues(allCards, "customer");
    var statuses = uniqueValues(allCards, "status");
    var pms = uniqueValues(allCards, "pm");
    var years = uniqueSortedYears(allCards);

    populateSelect(customerSelect, customers, "全部客戶", state.filters.customer);
    populateSelect(statusSelect, statuses, "全部狀態", state.filters.status);
    populateSelect(pmSelect, pms, "全部 PM", state.filters.pm);
    populateSelect(yearSelect, years, "全部年度", state.filters.year);

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
    yearSelect.addEventListener("change", function () {
      state.filters.year = yearSelect.value || null;
      renderContent();
    });
    querySelect.addEventListener("input", function () {
      state.query = querySelect.value.trim();
      renderContent();
    });
  }

  function uniqueValues(cards, key) {
    var values = [];
    cards.forEach(function (c) {
      if (c[key] && values.indexOf(c[key]) === -1) values.push(c[key]);
    });
    return values;
  }

  // 年度下拉選單的選項固定依全部資料算出，不受目前篩選影響（同既有 project_history 慣例），
  // 新到舊排序。
  function uniqueSortedYears(cards) {
    var years = [];
    cards.forEach(function (c) {
      c.record_years.forEach(function (y) {
        if (years.indexOf(y) === -1) years.push(y);
      });
    });
    return years.sort().reverse();
  }

  // ── 清單檢視（卡片原地展開，<details>/<summary>） ──────────────────

  function diffCell(diffDaysValue) {
    var td = document.createElement("td");
    td.setAttribute("data-label", "差異");
    if (diffDaysValue === null) {
      td.textContent = "—";
    } else if (diffDaysValue > 0) {
      td.textContent = "+" + diffDaysValue;
      td.className = "delay-positive";
    } else if (diffDaysValue < 0) {
      td.textContent = String(diffDaysValue);
      td.className = "delay-negative";
    } else {
      td.textContent = "0";
    }
    return td;
  }

  function appendReasonRow(tbody, reason, historyClass) {
    if (!reason) return;
    var reasonTr = document.createElement("tr");
    reasonTr.className = historyClass ? "phase-history-row phase-reason-row" : "phase-reason-row";
    var reasonTd = document.createElement("td");
    reasonTd.colSpan = 5;
    reasonTd.className = "phase-reason";
    reasonTd.textContent = "備註：" + reason;
    reasonTr.appendChild(reasonTd);
    tbody.appendChild(reasonTr);
  }

  function appendStageRow(tbody, stageName, record, historyClass) {
    var tr = document.createElement("tr");
    if (historyClass) tr.className = "phase-history-row";

    var stageTd = document.createElement("td");
    stageTd.setAttribute("data-label", "階段");
    stageTd.textContent = historyClass ? "↳ " + stageName + "（曾經延誤的舊排程）" : stageName;
    tr.appendChild(stageTd);

    var plannedTd = document.createElement("td");
    plannedTd.setAttribute("data-label", "預計完成日期");
    plannedTd.textContent = record ? formatValue(record.planned_date) : "—";
    tr.appendChild(plannedTd);

    var actualTd = document.createElement("td");
    actualTd.setAttribute("data-label", "實際完成日期");
    actualTd.textContent = record ? formatValue(record.actual_date) : "—";
    tr.appendChild(actualTd);

    var rowState = record ? computeRowState(record.planned_date, record.actual_date) : { completionLabel: "—", diffDays: null };
    tr.appendChild(diffCell(rowState.diffDays));

    var statusTd = document.createElement("td");
    statusTd.setAttribute("data-label", "完成狀態");
    statusTd.textContent = rowState.completionLabel;
    tr.appendChild(statusTd);

    tbody.appendChild(tr);
    if (record) appendReasonRow(tbody, record.reason, historyClass);
  }

  function buildStageTable(card) {
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
    card.stages.forEach(function (stage) {
      appendStageRow(tbody, stage.stage, stage.primary, false);
      stage.history.forEach(function (record) {
        appendStageRow(tbody, stage.stage, record, true);
      });
    });
    table.appendChild(tbody);

    return table;
  }

  function buildProjectCard(card) {
    var details = document.createElement("details");
    details.className = "project-card";

    var summary = document.createElement("summary");
    summary.className = "project-card-summary";

    var name = document.createElement("span");
    name.className = "project-card-name";
    name.textContent = card.project + " — " + issueLabel(card);
    summary.appendChild(name);

    var tags = document.createElement("span");
    tags.className = "project-card-tags";
    [
      [null, formatValue(card.customer)],
      [null, formatValue(card.pm)],
      [statusTagClass(card.status), formatValue(card.status)],
      [null, "預計完成：" + formatValue(card.planned_completion_date)]
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
    body.appendChild(buildStageTable(card));
    details.appendChild(body);

    return details;
  }

  function renderProjectCards(cards) {
    var container = document.getElementById("phase-tracking-content");
    container.innerHTML = "";

    if (cards.length === 0) {
      var empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent = "目前無符合條件的專案";
      container.appendChild(empty);
      return;
    }

    var list = document.createElement("div");
    list.className = "project-card-list";
    cards.forEach(function (card) { list.appendChild(buildProjectCard(card)); });
    container.appendChild(list);
  }

  // ── 甘特圖：雙軌設計（上面是預計時程、下面是實際時程）──────────────────
  //
  // 上軌＝純粹按「預計」時程排：從上一個有資料階段的 planned_date 銜接到這個階段自己的
  // planned_date，只要有 planned_date 就畫（不論完成與否），每個階段固定配色，色塊上不印文字
  // （對照圖例辨識，hover 才顯示階段名稱）。下軌＝純粹按「實際」時程排：從上一個有 actual_date
  // 階段的 actual_date 銜接到這個階段自己的 actual_date，只在這個階段已有 actual_date 時才畫，
  // 顏色依準時／延誤決定。

  var GANTT_ROW_HEIGHT = 42;
  var GANTT_LABEL_WIDTH = 152;
  var GANTT_PADDING_LEFT = 12;
  var GANTT_PADDING_RIGHT = 16;
  var GANTT_PADDING_TOP = 28;
  var GANTT_PADDING_BOTTOM = 8;
  var GANTT_MIN_WIDTH = 900;
  var GANTT_PIXELS_PER_DAY = 8;
  var GANTT_PLANNED_BAR_HEIGHT = 18;
  var GANTT_BAR_GAP = 3;
  var GANTT_ACTUAL_BAR_HEIGHT = 8;
  // 零工期色塊（例如開案當天就完成）clamp 後的最小寬度：2px 配上 1px stroke（置中畫在邊界上，
  // 兩側各吃掉 0.5px）幾乎把填色吃光，視覺上完全看不出色塊存在。
  var GANTT_MIN_SEGMENT_WIDTH = 6;

  var STAGE_BLOCK_CLASS = {
    "需求確認": "gantt-stage-requirement",
    "開案": "gantt-stage-kickoff",
    "開發": "gantt-stage-development",
    "測試": "gantt-stage-testing",
    "發布": "gantt-stage-release"
  };

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

  // minMs＝全體有效 planned_date 最小值；maxMs＝（全體有效 actual_date 最大值、今日、minMs）
  // 三者取最大值，兩端再各外推一個月，避免資料緊貼圖表邊界看不出前後還有沒有更早／更晚的東西。
  function ganttDomain(cards) {
    var plannedMsList = [];
    var actualMsList = [];
    cards.forEach(function (card) {
      card.stages.forEach(function (stage) {
        if (!stage.primary) return;
        var plannedMs = parseDateOnly(stage.primary.planned_date);
        if (plannedMs !== null) plannedMsList.push(plannedMs);
        var actualMs = parseDateOnly(stage.primary.actual_date);
        if (actualMs !== null) actualMsList.push(actualMs);
      });
    });
    if (plannedMsList.length === 0) return null;
    var minMs = Math.min.apply(null, plannedMsList);
    var maxMs = Math.max.apply(null, actualMsList.concat([todayUtcMs(), minMs]));
    return { minMs: addMonthsUtc(minMs, -1), maxMs: addMonthsUtc(maxMs, 1) };
  }

  function addMonthsUtc(ms, months) {
    var d = new Date(ms);
    return Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + months, d.getUTCDate());
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

  // 由 stageIndex 往前找上一個「有主要記錄、且 dateKey 這個日期欄位有值」的階段，回傳該日期
  // （中間跳過的階段視為不存在，不當作邊界）；一路往前都找不到時回傳 null（呼叫端退回用自己的
  // 日期，色塊寬度為 0，clamp 成最小可視寬度）。
  function previousBoundary(stages, stageIndex, dateKey) {
    for (var i = stageIndex - 1; i >= 0; i--) {
      var record = stages[i].primary;
      if (!record) continue;
      var ms = parseDateOnly(record[dateKey]);
      if (ms !== null) return ms;
    }
    return null;
  }

  function plannedSegment(stages, stageIndex, domain, width) {
    var record = stages[stageIndex].primary;
    if (!record) return null;
    var plannedMs = parseDateOnly(record.planned_date);
    if (plannedMs === null) return null;

    var startMs = previousBoundary(stages, stageIndex, "planned_date");
    if (startMs === null) startMs = plannedMs;
    var x1 = xAt(startMs, domain, width);
    var x2 = Math.max(xAt(plannedMs, domain, width), x1 + GANTT_MIN_SEGMENT_WIDTH);

    return { x: x1, width: x2 - x1, stage: stages[stageIndex].stage };
  }

  function actualSegment(stages, stageIndex, domain, width) {
    var record = stages[stageIndex].primary;
    if (!record || record.actual_date === null) return null;
    var actualMs = parseDateOnly(record.actual_date);
    if (actualMs === null) return null;

    var startMs = previousBoundary(stages, stageIndex, "actual_date");
    if (startMs === null) startMs = actualMs;
    var x1 = xAt(startMs, domain, width);
    var x2 = Math.max(xAt(actualMs, domain, width), x1 + GANTT_MIN_SEGMENT_WIDTH);

    // 圖例寫的是「準時／提前完成」＝綠色、「延誤完成」＝紅色：準時（diffDays === 0）跟提前一樣
    // 算綠色。不能用 `< 0` 判斷，diffDays 剛好等於 0 會被標成紅色，跟圖例文字自相矛盾。
    var rowState = computeRowState(record.planned_date, record.actual_date);
    var variant = rowState.diffDays !== null && rowState.diffDays <= 0 ? "early" : "delayed";
    var diffText = rowState.diffDays === null
      ? ""
      : "｜差異 " + (rowState.diffDays > 0 ? "+" : "") + rowState.diffDays + " 天";
    var title = stages[stageIndex].stage + "（實際）｜" + formatValue(record.actual_date) + diffText;

    return { x: x1, width: x2 - x1, variant: variant, title: title };
  }

  function renderGanttLegend(container) {
    var legend = document.createElement("div");
    legend.className = "gantt-legend";
    legend.setAttribute("role", "note");
    legend.setAttribute("aria-label", "甘特圖圖例");

    var plannedLabel = document.createElement("span");
    plannedLabel.className = "legend-item";
    plannedLabel.textContent = "上軌＝預計時程：";
    legend.appendChild(plannedLabel);

    STAGE_ORDER.forEach(function (stageName) {
      var item = document.createElement("span");
      item.className = "legend-item";
      var swatch = document.createElement("span");
      swatch.className = "legend-swatch " + STAGE_BLOCK_CLASS[stageName];
      item.appendChild(swatch);
      item.appendChild(document.createTextNode(stageName));
      legend.appendChild(item);
    });

    var actualLabel = document.createElement("span");
    actualLabel.className = "legend-item";
    actualLabel.textContent = "下軌＝實際時程：";
    legend.appendChild(actualLabel);

    [
      ["legend-swatch-ontime", "準時／提前完成"],
      ["legend-swatch-delayed", "延誤完成"]
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

  function renderGanttChart(cards) {
    var container = document.getElementById("phase-tracking-content");
    container.innerHTML = "";

    if (cards.length === 0) {
      var emptyCards = document.createElement("p");
      emptyCards.className = "empty-state";
      emptyCards.textContent = "目前無符合條件的專案";
      container.appendChild(emptyCards);
      return;
    }

    var domain = ganttDomain(cards);
    if (!domain) {
      var emptyDomain = document.createElement("p");
      emptyDomain.className = "empty-state";
      emptyDomain.textContent = "目前無可繪製的甘特圖資料";
      container.appendChild(emptyDomain);
      return;
    }

    renderGanttLegend(container);

    var width = ganttSvgWidth(domain);
    var height = GANTT_PADDING_TOP + cards.length * GANTT_ROW_HEIGHT + GANTT_PADDING_BOTTOM;
    var rowsBottom = GANTT_PADDING_TOP + cards.length * GANTT_ROW_HEIGHT;

    var scrollWrap = document.createElement("div");
    scrollWrap.className = "gantt-scroll";

    var flex = document.createElement("div");
    flex.className = "gantt-flex";
    flex.style.width = (GANTT_LABEL_WIDTH + width) + "px";
    flex.style.height = height + "px";

    // 標籤欄：獨立於 SVG 之外，position: sticky 固定在可視區域左側。padding-top 對齊 SVG 的
    // GANTT_PADDING_TOP（上面留給月份格線／文字），不然每一列的標題會跟色塊對不上。
    var labels = document.createElement("div");
    labels.className = "gantt-labels";
    labels.style.width = GANTT_LABEL_WIDTH + "px";
    labels.style.height = height + "px";
    labels.style.paddingTop = GANTT_PADDING_TOP + "px";
    labels.style.boxSizing = "border-box";

    cards.forEach(function (card, index) {
      var row = document.createElement("div");
      row.className = "gantt-label-row" + (index % 2 === 1 ? " gantt-label-row-band" : "");
      row.style.height = GANTT_ROW_HEIGHT + "px";
      row.title = card.project + " - " + issueLabel(card);
      var textSpan = document.createElement("span");
      textSpan.className = "gantt-label-text";
      textSpan.textContent = card.project + " - " + issueLabel(card);
      row.appendChild(textSpan);
      labels.appendChild(row);
    });
    flex.appendChild(labels);

    var svg = svgEl("svg", {
      viewBox: "0 0 " + width + " " + height,
      width: width,
      height: height,
      "class": "gantt-svg",
      role: "img",
      "aria-label": "專案階段追蹤甘特圖"
    });

    // 斑馬紋列底色，跟左側 .gantt-label-row-band 用同一個 index % 2 判斷，兩邊對齊。
    cards.forEach(function (_card, index) {
      if (index % 2 === 0) return;
      var bandY = GANTT_PADDING_TOP + index * GANTT_ROW_HEIGHT;
      svg.appendChild(svgEl("rect", { x: 0, y: bandY, width: width, height: GANTT_ROW_HEIGHT, "class": "gantt-row-band" }));
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

    cards.forEach(function (card, rowIndex) {
      var rowY = GANTT_PADDING_TOP + rowIndex * GANTT_ROW_HEIGHT;

      svg.appendChild(svgEl("line", {
        x1: 0, x2: width - GANTT_PADDING_RIGHT,
        y1: rowY + GANTT_ROW_HEIGHT / 2, y2: rowY + GANTT_ROW_HEIGHT / 2, "class": "gantt-row-baseline"
      }));

      var plannedY = rowY + 6;
      var actualY = plannedY + GANTT_PLANNED_BAR_HEIGHT + GANTT_BAR_GAP;

      // 依 STAGE_ORDER 反序畫（發布→需求確認）：較早的階段（尤其開案／需求確認）常常跟下一
      // 階段的起點落在同一天，色塊寬度會被 clamp 成最小寬度，緊貼在下一階段色塊的左邊界；若照
      // 原本順序畫，晚一點畫的較寬色塊會直接蓋住細線。反序後較早、較容易變細線的階段最後畫，
      // 疊在最上層。
      for (var stageIndex = card.stages.length - 1; stageIndex >= 0; stageIndex--) {
        var stage = card.stages[stageIndex];
        if (!stage.primary) continue;

        var planned = plannedSegment(card.stages, stageIndex, domain, width);
        if (planned) {
          var stageClass = STAGE_BLOCK_CLASS[stage.stage];
          var rect = svgEl("rect", {
            x: planned.x, y: plannedY, width: planned.width, height: GANTT_PLANNED_BAR_HEIGHT, rx: 2,
            "class": "gantt-stage-block " + stageClass
          });
          // 階段名稱不印在色塊上（配色已對照上方圖例），只保留 hover 提示。
          appendTitle(rect, stage.stage + "（預計）｜" + formatValue(stage.primary.planned_date));
          svg.appendChild(rect);
        }

        var actual = actualSegment(card.stages, stageIndex, domain, width);
        if (actual) {
          var actualRect = svgEl("rect", {
            x: actual.x, y: actualY, width: actual.width, height: GANTT_ACTUAL_BAR_HEIGHT, rx: 2,
            "class": "gantt-task-actual-" + actual.variant
          });
          appendTitle(actualRect, actual.title);
          svg.appendChild(actualRect);
        }
      }
    });

    flex.appendChild(svg);
    scrollWrap.appendChild(flex);
    container.appendChild(scrollWrap);
  }

  // ── 檢視切換與初始化 ──────────────────────────────────────────

  var allCards = [];

  function renderContent() {
    var cards = applySort(applyFilters(allCards));
    if (state.viewMode === "gantt") {
      renderGanttChart(cards);
    } else {
      renderProjectCards(cards);
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
    allCards = buildCards();
    initFilters(allCards);
    initViewToggle();
    renderContent();

    applyThemeToggleLabel(getCurrentTheme());
    var themeToggle = document.getElementById("theme-toggle");
    if (themeToggle) themeToggle.addEventListener("click", toggleTheme);
  });
})();
