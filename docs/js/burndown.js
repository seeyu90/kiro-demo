(function () {
  "use strict";

  // ── 模擬資料 ──────────────────────────────────────────────
  // 結構比照 307 試算表（307_專案人時燃盡追蹤）目前欄位：專案、議題、人員、議題ID、開案日期、
  // 完成日期、狀態、預估人時、每週人時。與 Rails `/burndown` 端各自獨立實作，不共用程式碼
  // （本頁純靜態展示，週資料直接以完整 ISO 日期陣列存放，不需要模擬 Rails 端「MM/DD 表頭＋
  // 跨年推算」這個步驟）。
  //
  // 比照真實試算表：同一議題（同 issue_id）可能拆給多位人員分別填一列（見 B-2001），故資料
  // 以「原始列」（BURNDOWN_ROWS）存放，渲染前先依 issue_id 合併（見 mergeRows）。
  // 至少涵蓋一筆「落後於理想線」（B-1001）、一筆「超前且超支（剩餘人時為負）」（B-1002，
  // 示範 Y 軸負值支援）、一筆「多人合併＋堆疊圖」（B-2001）的範例。

  var BURNDOWN_ROWS = [
    // 落後範例：預估 40 小時，但每週實際登記工時很少，剩餘人時遠高於理想線。
    // due_date（08/22）晚於目前最後一週資料（08/12），示範理想線補完成錨點、畫到底。
    {
      project: "AG 亞炬", issue_id: "B-1001", issue_title: "API 效能優化", assignee: "王贊勛",
      start_date: "2026-07-08", due_date: "2026-08-22", status: "執行中", estimated_hours: 40,
      weekly_actual: [
        { date: "2026-07-08", hours: 2 }, { date: "2026-07-15", hours: 3 },
        { date: "2026-07-22", hours: 2 }, { date: "2026-07-29", hours: 1 },
        { date: "2026-08-05", hours: 2 }, { date: "2026-08-12", hours: 1 }
      ]
    },
    // 超前且超支範例：預估 30 小時，實際登記工時總計 37 小時，剩餘人時變成負數（-7），
    // 示範 Y 軸支援負值、固定畫出「剩餘 = 0」參考線。due_date（08/01）早於最後一週資料，
    // 示範「完成日期之後」的理想線 clamp 為 0。
    {
      project: "AG 亞炬", issue_id: "B-1002", issue_title: "報表匯出功能", assignee: "蔡秉逸",
      start_date: "2026-07-08", due_date: "2026-08-01", status: "已完成", estimated_hours: 30,
      weekly_actual: [
        { date: "2026-07-08", hours: 8 }, { date: "2026-07-15", hours: 7 },
        { date: "2026-07-22", hours: 6 }, { date: "2026-07-29", hours: 5 },
        { date: "2026-08-05", hours: 6 }, { date: "2026-08-12", hours: 5 }
      ]
    },
    // 多人合併範例：同一議題（B-2001）拆給兩位人員分別填一列，合併後預估人時＝15+10＝25、
    // 週人時逐週加總；狀態「執行中」＋「未開始」合併後仍視為進行中（見 mergeStatus）；
    // 卡片下方會顯示兩人各自累積消耗人時的堆疊圖。
    {
      project: "Virtuous HRM", issue_id: "B-2001", issue_title: "排班衝突偵測", assignee: "黃靖益",
      start_date: "2026-07-08", due_date: "2026-08-24", status: "執行中", estimated_hours: 15,
      weekly_actual: [
        { date: "2026-07-08", hours: 2 }, { date: "2026-07-15", hours: 2 },
        { date: "2026-07-22", hours: 1 }, { date: "2026-07-29", hours: 1 },
        { date: "2026-08-05", hours: 1 }, { date: "2026-08-12", hours: 1 }
      ]
    },
    {
      project: "Virtuous HRM", issue_id: "B-2001", issue_title: "排班衝突偵測", assignee: "陳筱涵",
      start_date: "2026-07-08", due_date: "2026-08-24", status: "未開始", estimated_hours: 10,
      weekly_actual: [
        { date: "2026-07-08", hours: 1 }, { date: "2026-07-15", hours: 1 },
        { date: "2026-07-22", hours: 1 }, { date: "2026-07-29", hours: 0 },
        { date: "2026-08-05", hours: 1 }, { date: "2026-08-12", hours: 0 }
      ]
    }
  ];

  var VALID_STATUSES = ["未開始", "執行中", "已完成"];

  // ── 依 issue_id 合併同議題的多列（比照 Rails Sheets::FetchProjectBurndown#merge_rows，
  // 各自獨立實作）──────────────────────────────────────────

  function mergeRows(rows) {
    var byIssueId = {};
    var order = [];
    rows.forEach(function (row) {
      if (!(row.issue_id in byIssueId)) {
        byIssueId[row.issue_id] = [];
        order.push(row.issue_id);
      }
      byIssueId[row.issue_id].push(row);
    });

    return order.map(function (issueId) {
      var group = byIssueId[issueId];
      var first = group[0];
      var estimatedHours = group.reduce(function (sum, r) { return sum + r.estimated_hours; }, 0);
      var weeklyActual = sumWeeklyByDate(group.map(function (r) { return r.weekly_actual; }));
      var assignees = group.map(function (r) { return r.assignee; });

      var merged = {
        project: first.project,
        issue_id: issueId,
        issue_title: first.issue_title,
        assignees: assignees,
        start_date: first.start_date,
        due_date: first.due_date,
        status: mergeStatus(group),
        estimated_hours: estimatedHours,
        weekly_actual: weeklyActual
      };
      merged.per_assignee = group.map(function (r) {
        return { assignee: r.assignee, estimated_hours: r.estimated_hours, cumulative_series: computeCumulativeSeries(r.weekly_actual) };
      });
      return merged;
    });
  }

  // 任一列為「未開始」或「執行中」即代表議題整體尚未完成；全部合法列皆為「已完成」才回傳
  // "done"；沒有任何一列是合法值時回傳 null。
  function mergeStatus(group) {
    var valid = group.map(function (r) { return r.status; }).filter(function (s) {
      return VALID_STATUSES.indexOf(s) !== -1;
    });
    if (valid.length === 0) return null;
    return valid.some(function (s) { return s !== "已完成"; }) ? "in_progress" : "done";
  }

  function sumWeeklyByDate(weeklyList) {
    var totals = {};
    var order = [];
    weeklyList.forEach(function (weekly) {
      weekly.forEach(function (point) {
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

  // ── 理想／實際／累積序列計算 ──────────────────────────────
  // 邏輯與 design.md「Sheets::FetchProjectBurndown」段落的 Ruby 版本一致（線性比例分攤、
  // 依日期累加，理想線頭尾補開案／完成錨點），但兩邊各自獨立實作。

  function computeIdealSeries(issue) {
    var start = new Date(issue.start_date);
    var due = new Date(issue.due_date);
    if (isNaN(start.getTime()) || isNaN(due.getTime()) || due <= start) return [];

    var totalSpan = due.getTime() - start.getTime();
    var points = issue.weekly_actual.map(function (week) {
      var weekDate = new Date(week.date);
      var ratio = (weekDate.getTime() - start.getTime()) / totalSpan;
      ratio = Math.max(0, Math.min(1, ratio));
      return { date: week.date, hours: round2(issue.estimated_hours * (1 - ratio)) };
    });

    // 開案／完成兩端補上錨點：模擬資料的週欄位不一定剛好涵蓋到開案週或完成週，若只依現有
    // 週欄位畫線，理想線會在資料範圍邊界處被截斷。確保理想線一定包含「開案＝滿額」
    // 「完成＝歸零」這兩個端點，即使超出目前週欄位範圍，讓斜線完整畫到底。
    var byDate = {};
    points.forEach(function (p) { byDate[p.date] = p; });
    if (!(issue.start_date in byDate)) points.push({ date: issue.start_date, hours: round2(issue.estimated_hours) });
    if (!(issue.due_date in byDate)) points.push({ date: issue.due_date, hours: 0 });
    points.sort(function (a, b) { return a.date < b.date ? -1 : a.date > b.date ? 1 : 0; });
    return points;
  }

  function computeActualSeries(issue) {
    var cumulative = 0;
    return issue.weekly_actual.map(function (week) {
      cumulative += week.hours;
      return { date: week.date, hours: round2(issue.estimated_hours - cumulative) };
    });
  }

  // 累積消耗人時（由 0 往上累加，不是剩餘人時）：供堆疊圖使用。
  function computeCumulativeSeries(weeklyActual) {
    var cumulative = 0;
    return weeklyActual.map(function (week) {
      cumulative += week.hours;
      return { date: week.date, hours: round2(cumulative) };
    });
  }

  function round2(value) {
    return Math.round(value * 100) / 100;
  }

  // ── 篩選狀態 ──────────────────────────────────────────────
  // 預設只顯示進行中議題（比照 Rails 端），避免所有議題（含已完成）都塞在同一頁。

  var state = { project: null, assignee: null, status: "in_progress" };

  function uniqueValues(records, key) {
    var values = [];
    records.forEach(function (r) {
      if (values.indexOf(r[key]) === -1) values.push(r[key]);
    });
    return values;
  }

  function uniqueAssignees(issues) {
    var values = [];
    issues.forEach(function (issue) {
      issue.assignees.forEach(function (a) {
        if (values.indexOf(a) === -1) values.push(a);
      });
    });
    return values;
  }

  // 議題是否進行中：優先採用「狀態」欄位（未開始／執行中 → 進行中，已完成 → 已完成）；
  // 狀態無法辨識（null）時退回以 due_date 與今天比較（缺漏或無法解析時一律視為進行中）。
  function issueInProgress(issue) {
    if (issue.status === "in_progress") return true;
    if (issue.status === "done") return false;

    var due = new Date(issue.due_date);
    if (isNaN(due.getTime())) return true;
    return due.getTime() > Date.now();
  }

  function statusMatches(issue) {
    if (state.status === "all") return true;
    var inProgress = issueInProgress(issue);
    return state.status === "done" ? !inProgress : inProgress;
  }

  function filterIssues(issues) {
    return issues.filter(function (issue) {
      if (state.project && issue.project !== state.project) return false;
      if (state.assignee && issue.assignees.indexOf(state.assignee) === -1) return false;
      if (!statusMatches(issue)) return false;
      return true;
    });
  }

  function initFilters(issues) {
    var projectSelect = document.getElementById("burndown-project");
    var assigneeSelect = document.getElementById("burndown-assignee");
    var statusSelect = document.getElementById("burndown-status");

    var allProject = document.createElement("option");
    allProject.value = "";
    allProject.textContent = "全部專案";
    projectSelect.appendChild(allProject);
    uniqueValues(issues, "project").forEach(function (project) {
      var option = document.createElement("option");
      option.value = project;
      option.textContent = project;
      projectSelect.appendChild(option);
    });

    var allAssignee = document.createElement("option");
    allAssignee.value = "";
    allAssignee.textContent = "全部人員";
    assigneeSelect.appendChild(allAssignee);
    uniqueAssignees(issues).forEach(function (assignee) {
      var option = document.createElement("option");
      option.value = assignee;
      option.textContent = assignee;
      assigneeSelect.appendChild(option);
    });

    [
      { value: "in_progress", text: "進行中" },
      { value: "done", text: "已完成" },
      { value: "all", text: "全部" }
    ].forEach(function (opt) {
      var option = document.createElement("option");
      option.value = opt.value;
      option.textContent = opt.text;
      if (opt.value === state.status) option.selected = true;
      statusSelect.appendChild(option);
    });

    projectSelect.addEventListener("change", function () {
      state.project = projectSelect.value || null;
      renderIssueSeries(issues);
    });
    assigneeSelect.addEventListener("change", function () {
      state.assignee = assigneeSelect.value || null;
      renderIssueSeries(issues);
    });
    statusSelect.addEventListener("change", function () {
      state.status = statusSelect.value;
      renderIssueSeries(issues);
    });
  }

  // ── 渲染 ──────────────────────────────────────────────────

  // 議題燃盡圖：專案／人員／狀態篩選同時存在時取交集（比照 Rails 端需求 4.4）。
  function renderIssueSeries(issues) {
    var container = document.getElementById("issue-series");
    container.innerHTML = "";

    var filtered = filterIssues(issues);
    if (filtered.length === 0) {
      appendEmptyState(container, "目前無符合條件的議題");
      return;
    }

    filtered.forEach(function (issue) {
      var title = issue.project + "／" + issue.issue_title + "（" + issue.assignees.join("、") + "）";
      renderBurndownChart(container, title, computeActualSeries(issue), computeIdealSeries(issue));
      if (issue.assignees.length > 1) {
        renderStackedChart(container, issue.per_assignee, issue.estimated_hours);
      }
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
  var svgNS = "http://www.w3.org/2000/svg";

  function shortDate(dateStr) {
    var parts = String(dateStr).split("-");
    return parts.length === 3 ? parts[1] + "/" + parts[2] : dateStr;
  }

  function plotWidth() { return CHART_WIDTH - CHART_PADDING_LEFT - CHART_PADDING_RIGHT; }
  function plotHeight() { return CHART_HEIGHT - CHART_PADDING_TOP - CHART_PADDING_BOTTOM; }

  function yAt(value, min, max) {
    var ratio = (value - min) / (max - min);
    return CHART_HEIGHT - CHART_PADDING_BOTTOM - ratio * plotHeight();
  }

  function addText(svg, x, y, text, anchor, extraClass, rotateDeg) {
    var el = document.createElementNS(svgNS, "text");
    el.setAttribute("x", x);
    el.setAttribute("y", y);
    el.setAttribute("text-anchor", anchor);
    el.setAttribute("class", "trend-axis-label" + (extraClass ? " " + extraClass : ""));
    if (rotateDeg) el.setAttribute("transform", "rotate(" + rotateDeg + " " + x + " " + y + ")");
    el.textContent = text;
    svg.appendChild(el);
  }

  // 均分格線 + 固定補一條「0」格線（min／max 跨越 0 時）：比照 Rails burndown_chart_y_ticks。
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

  function renderBurndownChart(container, title, actualSeries, idealSeries) {
    var block = document.createElement("div");
    block.className = "burndown-chart-block";

    var heading = document.createElement("h3");
    heading.textContent = title;
    block.appendChild(heading);

    if (actualSeries.length === 0) {
      appendEmptyState(block, "無燃盡資料");
      container.appendChild(block);
      return;
    }

    var allPoints = actualSeries.concat(idealSeries);
    var max = Math.max.apply(null, allPoints.map(function (p) { return p.hours; }).concat([1]));
    var min = Math.min.apply(null, allPoints.map(function (p) { return p.hours; }).concat([0]));

    // 實際／理想兩條序列共用同一組 X 軸日期（理想線的開案／完成錨點不一定存在於實際序列），
    // 取兩者日期聯集、依日期排序，兩條線才能對齊到同一個座標系（比照 Rails burndown_chart_dates）。
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
    svg.setAttribute("aria-label", title + " 燃盡圖");

    yTicks(min, max).forEach(function (tick) {
      var gridline = document.createElementNS(svgNS, "line");
      gridline.setAttribute("x1", CHART_PADDING_LEFT);
      gridline.setAttribute("x2", CHART_WIDTH - CHART_PADDING_RIGHT);
      gridline.setAttribute("y1", tick.y);
      gridline.setAttribute("y2", tick.y);
      gridline.setAttribute("class", "trend-gridline");
      svg.appendChild(gridline);
      addText(svg, CHART_PADDING_LEFT - 8, tick.y + 3, String(tick.value), "end", "trend-y-label");
    });

    dates.forEach(function (date, i) {
      addText(svg, xAt(i), CHART_HEIGHT - CHART_PADDING_BOTTOM + 18, shortDate(date), "end", "trend-x-label", -45);
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

    block.appendChild(svg);
    container.appendChild(block);
  }

  // ── 堆疊圖（多人議題各自累積消耗人時，比照 Rails _burndown_stacked_chart.html.erb） ──

  var STACK_COLORS = ["#60a5fa", "#f472b6", "#34d399", "#fbbf24", "#a78bfa", "#fb923c", "#38bdf8", "#f87171"];

  function renderStackedChart(container, perAssignee, estimatedHours) {
    var block = document.createElement("div");
    block.className = "burndown-chart-block";

    var heading = document.createElement("h3");
    heading.textContent = "各人員累積消耗人時（" + perAssignee.length + " 人）";
    block.appendChild(heading);

    var dates = perAssignee.length > 0 ? perAssignee[0].cumulative_series.map(function (p) { return p.date; }) : [];
    if (dates.length === 0) {
      appendEmptyState(block, "無燃盡資料");
      container.appendChild(block);
      return;
    }

    var totals = dates.map(function (_, i) {
      return perAssignee.reduce(function (sum, pa) { return sum + pa.cumulative_series[i].hours; }, 0);
    });
    var max = Math.max.apply(null, totals.concat([estimatedHours, 1]));
    var stepX = plotWidth() / Math.max(dates.length - 1, 1);
    function xAt(i) { return CHART_PADDING_LEFT + i * stepX; }

    var svg = document.createElementNS(svgNS, "svg");
    svg.setAttribute("viewBox", "0 0 " + CHART_WIDTH + " " + CHART_HEIGHT);
    svg.setAttribute("class", "trend-svg");
    svg.setAttribute("role", "img");
    svg.setAttribute("aria-label", "各人員累積消耗人時堆疊圖");

    yTicks(0, max).forEach(function (tick) {
      var gridline = document.createElementNS(svgNS, "line");
      gridline.setAttribute("x1", CHART_PADDING_LEFT);
      gridline.setAttribute("x2", CHART_WIDTH - CHART_PADDING_RIGHT);
      gridline.setAttribute("y1", tick.y);
      gridline.setAttribute("y2", tick.y);
      gridline.setAttribute("class", "trend-gridline");
      svg.appendChild(gridline);
      addText(svg, CHART_PADDING_LEFT - 8, tick.y + 3, String(tick.value), "end", "trend-y-label");
    });

    dates.forEach(function (date, i) {
      addText(svg, xAt(i), CHART_HEIGHT - CHART_PADDING_BOTTOM + 18, shortDate(date), "end", "trend-x-label", -45);
    });

    // 依 per_assignee 順序，逐人算出一塊堆疊區塊：下緣＝前面所有人已疊加的累計，
    // 上緣＝加上這個人自己的累積人時之後的新高度。
    var running = dates.map(function () { return 0; });
    perAssignee.forEach(function (pa, idx) {
      var top = dates.map(function (_, i) { return running[i] + pa.cumulative_series[i].hours; });
      var bottomEdge = dates.map(function (_, i) { return xAt(i) + "," + yAt(running[i], 0, max); });
      var topEdge = dates.map(function (_, i) { return xAt(i) + "," + yAt(top[i], 0, max); }).reverse();
      var polygon = document.createElementNS(svgNS, "polygon");
      polygon.setAttribute("points", bottomEdge.concat(topEdge).join(" "));
      var color = STACK_COLORS[idx % STACK_COLORS.length];
      polygon.setAttribute("fill", color);
      polygon.setAttribute("fill-opacity", "0.75");
      polygon.setAttribute("stroke", color);
      polygon.setAttribute("stroke-width", "1");
      var titleEl = document.createElementNS(svgNS, "title");
      titleEl.textContent = pa.assignee;
      polygon.appendChild(titleEl);
      svg.appendChild(polygon);
      running = top;
    });

    var refY = yAt(estimatedHours, 0, max);
    var refLine = document.createElementNS(svgNS, "line");
    refLine.setAttribute("x1", CHART_PADDING_LEFT);
    refLine.setAttribute("x2", CHART_WIDTH - CHART_PADDING_RIGHT);
    refLine.setAttribute("y1", refY);
    refLine.setAttribute("y2", refY);
    refLine.setAttribute("class", "burndown-estimate-reference-line");
    svg.appendChild(refLine);

    block.appendChild(svg);

    var legend = document.createElement("ul");
    legend.className = "burndown-stack-legend";
    perAssignee.forEach(function (pa, idx) {
      var li = document.createElement("li");
      var swatch = document.createElement("span");
      swatch.className = "burndown-stack-swatch";
      swatch.style.backgroundColor = STACK_COLORS[idx % STACK_COLORS.length];
      li.appendChild(swatch);
      li.appendChild(document.createTextNode(pa.assignee));
      legend.appendChild(li);
    });
    var refLi = document.createElement("li");
    var refSwatch = document.createElement("span");
    refSwatch.className = "burndown-stack-swatch burndown-stack-swatch-reference";
    refLi.appendChild(refSwatch);
    refLi.appendChild(document.createTextNode("總預估人時（" + estimatedHours + "）"));
    legend.appendChild(refLi);
    block.appendChild(legend);

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
    var issues = mergeRows(BURNDOWN_ROWS);
    initFilters(issues);
    renderIssueSeries(issues);

    applyThemeToggleLabel(getCurrentTheme());
    var themeToggle = document.getElementById("theme-toggle");
    if (themeToggle) themeToggle.addEventListener("click", toggleTheme);
  });
})();
