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
  // 示範 Y 軸負值支援）、一筆「多人合併＋各自並排長條與右軸」（B-2001）的範例。

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
    // 估計人時差很多（15 vs 10，這裡差距不大，主要示範每人各自並排長條＋各自右軸的排版）。
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

      // 同一人若拆成多列（例如更正列），先依人員名稱分組合併，長條／折線才不會把同一人畫成
      // 兩份（比照 Ruby Actor 版本 per_assignee_series 的合併邏輯）。
      var byAssignee = {};
      var assigneeOrder = [];
      group.forEach(function (r) {
        if (!(r.assignee in byAssignee)) {
          byAssignee[r.assignee] = [];
          assigneeOrder.push(r.assignee);
        }
        byAssignee[r.assignee].push(r);
      });

      var merged = {
        project: first.project,
        issue_id: issueId,
        issue_title: first.issue_title,
        assignees: assigneeOrder,
        start_date: first.start_date,
        due_date: first.due_date,
        status: mergeStatus(group),
        estimated_hours: estimatedHours,
        weekly_actual: weeklyActual
      };
      // per_assignee 同時保留 weekly（每週增量，長條圖用）與 cumulative_series（累積消耗，
      // 折線圖與狀態燈號用）：直接在合併當下算好兩種形態，比 Rails 端「只存累積、圖表要用
      // 每週增量時再用相鄰兩筆累積值相減還原」（見 burndown_helper.rb 的
      // burndown_weekly_by_assignee）簡單一點，效果相同。
      merged.per_assignee = assigneeOrder.map(function (assignee) {
        var assigneeRows = byAssignee[assignee];
        var estimated = assigneeRows.reduce(function (sum, r) { return sum + r.estimated_hours; }, 0);
        var weekly = sumWeeklyByDate(assigneeRows.map(function (r) { return r.weekly_actual; }));
        return { assignee: assignee, estimated_hours: estimated, weekly: weekly, cumulative_series: computeCumulativeSeries(weekly) };
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

  // 「剩餘人時」理想線（供狀態燈號使用，見 burndownStatus）：由滿額往 0 線性遞減。
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

  // 「剩餘人時」實際線（供狀態燈號使用）：估計人時 − 累積消耗。
  function computeActualSeries(issue) {
    var cumulative = 0;
    return issue.weekly_actual.map(function (week) {
      cumulative += week.hours;
      return { date: week.date, hours: round2(issue.estimated_hours - cumulative) };
    });
  }

  // 每人自己的理想「累積消耗」人時軌跡（供組合圖表使用，方向跟上面兩個「剩餘」序列相反）：
  // 起點 0 落在開案日、終點是「這個人自己的預估人時」落在完成日，跟 burndownPerAssigneeStatus
  // 用同一套時間比例公式，只是這裡算出整條線（每個 X 軸日期一個點）而不是只算最新一點
  // （比照 Rails burndown_per_assignee_ideal_series）。
  function computePerAssigneeIdealSeries(paEntry, issue, dates) {
    var start = new Date(issue.start_date);
    var due = new Date(issue.due_date);
    if (isNaN(start.getTime()) || isNaN(due.getTime()) || due <= start) return [];

    var estimated = paEntry.estimated_hours;
    var totalSpan = due.getTime() - start.getTime();
    var points = [];
    dates.forEach(function (dateStr) {
      var d = new Date(dateStr);
      if (isNaN(d.getTime())) return;
      var ratio = Math.max(0, Math.min(1, (d.getTime() - start.getTime()) / totalSpan));
      points.push({ date: dateStr, hours: round2(estimated * ratio) });
    });
    return points;
  }

  // 累積消耗人時（由 0 往上累加，不是剩餘人時）：組合圖表的折線／長條都是這個方向。
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

  // ── 議題燃盡狀態燈號（比照 Rails BurndownHelper#burndown_status／#burndown_per_assignee_status）
  // ──────────────────────────────────────────────────────────

  var STATUS_AT_RISK_RATIO = 0.05;
  var STATUS_OVER_RATIO = 0.25;
  var STATUS_LABELS = { on_track: "正常", at_risk: "略慢", over: "超支", unknown: "資料不足" };

  function findByOrNearestDate(series, dateStr) {
    var exact = series.filter(function (p) { return p.date === dateStr; })[0];
    if (exact) return exact;
    var target = new Date(dateStr).getTime();
    return series.reduce(function (best, p) {
      var diff = Math.abs(new Date(p.date).getTime() - target);
      return diff < best.diff ? { point: p, diff: diff } : best;
    }, { point: null, diff: Infinity }).point;
  }

  // 議題整體燈號：比較「最新一週實際剩餘人時」與「同一天理想線應剩餘人時」的落差，換算成
  // 佔預估人時的比例（相對值而非絕對小時數）。剩餘人時已經是負值（花費超過整份預估）時，
  // 一律強制判定超支，不論理想線落在哪裡（負值剩餘若只看落差方向，反而會被誤判成領先進度）。
  function burndownStatus(issue) {
    var actualSeries = computeActualSeries(issue);
    var idealSeries = computeIdealSeries(issue);
    var estimatedHours = issue.estimated_hours;
    if (actualSeries.length === 0 || idealSeries.length === 0 || !estimatedHours) {
      return { key: "unknown", label: STATUS_LABELS.unknown };
    }

    var latestActual = actualSeries.reduce(function (a, b) { return a.date > b.date ? a : b; });
    if (latestActual.hours < 0) return { key: "over", label: STATUS_LABELS.over };

    var idealAtDate = findByOrNearestDate(idealSeries, latestActual.date);
    var deltaRatio = (latestActual.hours - idealAtDate.hours) / estimatedHours;
    return statusFromDeltaRatio(deltaRatio);
  }

  // 各人員燈號：比較「這個人自己已消耗人時」vs「這個人自己的預估人時 ×（議題整體時間已過的
  // 比例）」，落差方向跟 burndownStatus 相反（這裡比較的是「已消耗」不是「剩餘」：消耗得比
  // 理想進度少才是落後）。
  function burndownPerAssigneeStatus(paEntry, issue) {
    var estimated = paEntry.estimated_hours;
    var cumulativeSeries = paEntry.cumulative_series;
    if (!estimated || cumulativeSeries.length === 0) return { key: "unknown", label: STATUS_LABELS.unknown };

    var latest = cumulativeSeries.reduce(function (a, b) { return a.date > b.date ? a : b; });
    var actualConsumed = latest.hours;
    if (actualConsumed > estimated) return { key: "over", label: STATUS_LABELS.over };

    var start = new Date(issue.start_date);
    var due = new Date(issue.due_date);
    if (isNaN(start.getTime()) || isNaN(due.getTime()) || due <= start) return { key: "unknown", label: STATUS_LABELS.unknown };

    var latestDate = new Date(latest.date);
    var timeRatio = Math.max(0, Math.min(1, (latestDate.getTime() - start.getTime()) / (due.getTime() - start.getTime())));
    var idealConsumed = estimated * timeRatio;
    var deltaRatio = (idealConsumed - actualConsumed) / estimated;
    return statusFromDeltaRatio(deltaRatio);
  }

  function statusFromDeltaRatio(deltaRatio) {
    if (deltaRatio <= STATUS_AT_RISK_RATIO) return { key: "on_track", label: STATUS_LABELS.on_track };
    if (deltaRatio <= STATUS_OVER_RATIO) return { key: "at_risk", label: STATUS_LABELS.at_risk };
    return { key: "over", label: STATUS_LABELS.over };
  }

  function burndownRemainingHours(issue) {
    var actualSeries = computeActualSeries(issue);
    if (actualSeries.length === 0) return null;
    return actualSeries.reduce(function (a, b) { return a.date > b.date ? a : b; }).hours;
  }

  function burndownConsumedHours(issue) {
    var remaining = burndownRemainingHours(issue);
    if (remaining === null) return null;
    return round2(issue.estimated_hours - remaining);
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

  // ── 渲染：狀態摘要表（點列原地展開燃盡圖，比照 Rails burndown/index.html.erb） ──────

  function appendEmptyState(container, text) {
    var empty = document.createElement("p");
    empty.className = "empty-state";
    empty.textContent = text;
    container.appendChild(empty);
  }

  function renderIssueSeries(issues) {
    var container = document.getElementById("issue-series");
    container.innerHTML = "";

    var filtered = filterIssues(issues);
    if (filtered.length === 0) {
      appendEmptyState(container, "目前無符合條件的議題");
      return;
    }

    var table = document.createElement("div");
    table.className = "burndown-status-table";

    var header = document.createElement("div");
    header.className = "burndown-status-row burndown-status-header";
    ["議題", "負責人", "預估人時", "已消耗", "剩餘", "狀態"].forEach(function (label) {
      var span = document.createElement("span");
      span.textContent = label;
      header.appendChild(span);
    });
    table.appendChild(header);

    filtered.forEach(function (issue) {
      table.appendChild(renderStatusDetails(issue));
    });

    container.appendChild(table);
  }

  function renderStatusDetails(issue) {
    var details = document.createElement("details");
    details.className = "burndown-status-details";

    var summary = document.createElement("summary");
    var row = document.createElement("span");
    row.className = "burndown-status-row";

    var statusInfo = burndownStatus(issue);
    var remaining = burndownRemainingHours(issue);
    var consumed = burndownConsumedHours(issue);

    var titleSpan = document.createElement("span");
    titleSpan.textContent = issue.project + "／" + issue.issue_title;
    row.appendChild(titleSpan);

    var assigneeSpan = document.createElement("span");
    assigneeSpan.textContent = issue.assignees.join("、");
    row.appendChild(assigneeSpan);

    [issue.estimated_hours, consumed === null ? "—" : consumed, remaining === null ? "—" : remaining].forEach(function (value) {
      var span = document.createElement("span");
      span.textContent = String(value);
      row.appendChild(span);
    });

    var badge = document.createElement("span");
    badge.className = "status-badge status-" + statusInfo.key;
    badge.textContent = statusInfo.label;
    row.appendChild(badge);

    summary.appendChild(row);
    details.appendChild(summary);

    var title = issue.project + "／" + issue.issue_title + "（" + issue.assignees.join("、") + "）";
    var detail = document.createElement("div");
    detail.className = "burndown-status-detail";
    detail.appendChild(renderComboChart(issue, title));
    details.appendChild(detail);

    return details;
  }

  // ── 燃盡圖（長條＝當週實際 + 每人各自一條理想／實際累積折線與右軸，
  // 比照 Rails _burndown_combo_chart.html.erb） ──────────────────────

  var CHART_WIDTH = 640;
  var CHART_HEIGHT = 250;
  var CHART_PADDING_LEFT = 40;
  // 燃盡組合圖右軸每人一條，正上方要放色塊標記＋數字，留大一點的上邊界才不會擠在一起
  // （跟 Rails 端 BurndownHelper::BURNDOWN_PADDING_TOP 同步調整過的值一致）。
  var CHART_PADDING_TOP = 28;
  var CHART_PADDING_BOTTOM = 55;
  var CHART_Y_TICKS = 3;
  var AXIS_COLUMN_WIDTH = 34;
  var PADDING_RIGHT_BASE = 14;
  var svgNS = "http://www.w3.org/2000/svg";

  var STACK_COLORS = ["#60a5fa", "#f472b6", "#34d399", "#fbbf24", "#a78bfa", "#fb923c", "#38bdf8", "#f87171"];

  function shortDate(dateStr) {
    var parts = String(dateStr).split("-");
    return parts.length === 3 ? parts[1] + "/" + parts[2] : dateStr;
  }

  function plotWidth(paddingRight) { return CHART_WIDTH - CHART_PADDING_LEFT - paddingRight; }
  function plotHeight() { return CHART_HEIGHT - CHART_PADDING_TOP - CHART_PADDING_BOTTOM; }

  function yAt(value, min, max) {
    var ratio = (value - min) / (max - min);
    return CHART_HEIGHT - CHART_PADDING_BOTTOM - ratio * plotHeight();
  }

  function addText(svg, x, y, text, anchor, className, fill) {
    var el = document.createElementNS(svgNS, "text");
    el.setAttribute("x", x);
    el.setAttribute("y", y);
    el.setAttribute("text-anchor", anchor);
    el.setAttribute("class", className);
    if (fill) el.setAttribute("fill", fill);
    el.textContent = text;
    svg.appendChild(el);
    return el;
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
    if (min < 0 && max > 0 && !(0 in seen)) ticks.push({ value: 0, y: yAt(0, min, max) });
    ticks.sort(function (a, b) { return a.value - b.value; });
    return ticks;
  }

  function combinedDates(issue, perAssigneeIdeal) {
    var seen = {};
    var dates = [];
    function addDate(d) { if (!(d in seen)) { seen[d] = true; dates.push(d); } }
    issue.per_assignee.forEach(function (pa) { pa.cumulative_series.forEach(function (p) { addDate(p.date); }); });
    perAssigneeIdeal.forEach(function (series) { series.forEach(function (p) { addDate(p.date); }); });
    dates.sort();
    return dates;
  }

  function renderComboChart(issue, title) {
    var wrap = document.createElement("div");
    wrap.className = "burndown-chart-block";

    var heading = document.createElement("h3");
    heading.appendChild(document.createTextNode(title + " "));
    var info = document.createElement("span");
    info.className = "chart-info";
    info.tabIndex = 0;
    info.setAttribute("aria-label", "說明");
    var icon = document.createElement("span");
    icon.className = "chart-info-icon";
    icon.setAttribute("aria-hidden", "true");
    icon.textContent = "i";
    info.appendChild(icon);
    var tooltip = document.createElement("span");
    tooltip.className = "chart-info-tooltip";
    tooltip.textContent = "長條＝當週實際｜虛線＝計畫、實線＝實際累積（實線低於虛線即落後）｜右軸顏色對應人員｜點圖例可篩選";
    info.appendChild(tooltip);
    heading.appendChild(info);
    wrap.appendChild(heading);

    var perAssigneeIdeal = issue.per_assignee.map(function (pa) { return computePerAssigneeIdealSeries(pa, issue, pa.cumulative_series.map(function (p) { return p.date; })); });
    var dates = combinedDates(issue, perAssigneeIdeal);
    if (dates.length === 0) {
      appendEmptyState(wrap, "無燃盡資料");
      return wrap;
    }
    // 補上完整的日期後，理想線的錨點需要重新對齊到這個共用日期集合。
    perAssigneeIdeal = issue.per_assignee.map(function (pa) { return computePerAssigneeIdealSeries(pa, issue, dates); });

    var assigneeCount = issue.per_assignee.length;
    var paddingRight = PADDING_RIGHT_BASE + Math.max(assigneeCount, 1) * AXIS_COLUMN_WIDTH;
    var plotRight = CHART_WIDTH - paddingRight;

    var leftMax = Math.max.apply(null, dates.map(function (date) {
      return Math.max.apply(null, issue.per_assignee.map(function (pa) {
        var point = pa.weekly.filter(function (p) { return p.date === date; })[0];
        return point ? point.hours : 0;
      }).concat([0]));
    }).concat([1]));

    var stepX = plotWidth(paddingRight) / Math.max(dates.length - 1, 1);
    function xAt(i) { return CHART_PADDING_LEFT + i * stepX; }

    var svg = document.createElementNS(svgNS, "svg");
    svg.setAttribute("viewBox", "0 0 " + CHART_WIDTH + " " + CHART_HEIGHT);
    svg.setAttribute("class", "trend-svg");
    svg.setAttribute("role", "img");
    svg.setAttribute("aria-label", title + " 週別人時與累積進度");

    yTicks(0, leftMax).forEach(function (tick) {
      var gridline = document.createElementNS(svgNS, "line");
      gridline.setAttribute("x1", CHART_PADDING_LEFT);
      gridline.setAttribute("x2", plotRight);
      gridline.setAttribute("y1", tick.y);
      gridline.setAttribute("y2", tick.y);
      gridline.setAttribute("class", "trend-gridline");
      svg.appendChild(gridline);
      addText(svg, CHART_PADDING_LEFT - 8, tick.y + 3, String(tick.value), "end", "trend-axis-label trend-y-label");
    });

    dates.forEach(function (date, i) {
      addText(svg, xAt(i), CHART_HEIGHT - CHART_PADDING_BOTTOM + 18, shortDate(date), "end", "trend-axis-label trend-x-label")
        .setAttribute("transform", "rotate(-45 " + xAt(i) + " " + (CHART_HEIGHT - CHART_PADDING_BOTTOM + 18) + ")");
    });

    // 每人各自一根長條、並排顯示在同一週欄位內（而非疊加），才能直接比較「這週誰做得多」。
    var slotWidth = Math.min(stepX * 0.7, 60);
    var barWidth = slotWidth / Math.max(assigneeCount, 1);
    var zeroY = yAt(0, 0, leftMax);
    dates.forEach(function (date, i) {
      var xCenter = xAt(i);
      var slotLeft = Math.min(Math.max(xCenter - slotWidth / 2, CHART_PADDING_LEFT), plotRight - slotWidth);
      issue.per_assignee.forEach(function (pa, idx) {
        var point = pa.weekly.filter(function (p) { return p.date === date; })[0];
        var hours = Math.max(point ? point.hours : 0, 0);
        var yTop = yAt(hours, 0, leftMax);
        var color = STACK_COLORS[idx % STACK_COLORS.length];
        var rect = document.createElementNS(svgNS, "rect");
        rect.setAttribute("class", "burndown-series");
        rect.setAttribute("data-assignee", pa.assignee);
        rect.setAttribute("x", (slotLeft + idx * barWidth).toFixed(2));
        rect.setAttribute("y", yTop.toFixed(2));
        rect.setAttribute("width", barWidth.toFixed(2));
        rect.setAttribute("height", (zeroY - yTop).toFixed(2));
        rect.setAttribute("fill", color);
        rect.setAttribute("fill-opacity", "0.55");
        var titleEl = document.createElementNS(svgNS, "title");
        titleEl.textContent = pa.assignee + "｜" + date + "｜當週 " + hours + " 小時";
        rect.appendChild(titleEl);
        svg.appendChild(rect);
      });
    });

    var indexByDate = {};
    dates.forEach(function (d, i) { indexByDate[d] = i; });

    issue.per_assignee.forEach(function (pa, idx) {
      var color = STACK_COLORS[idx % STACK_COLORS.length];
      var idealSeries = perAssigneeIdeal[idx];
      var ownMax = Math.max.apply(null, pa.cumulative_series.concat(idealSeries).map(function (p) { return p.hours; }).concat([pa.estimated_hours, 1]));
      var axisX = plotRight + 8 + idx * AXIS_COLUMN_WIDTH;

      // 軸線本身也上色（不只是數字），色塊標記在軸線正上方，光看軸線／色塊就能對應到人，
      // 不用先讀數字顏色才知道是誰；色塊跟數字之間、數字跟軸線之間都留可辨識的間距。
      var axisLine = document.createElementNS(svgNS, "line");
      axisLine.setAttribute("x1", axisX);
      axisLine.setAttribute("x2", axisX);
      axisLine.setAttribute("y1", CHART_PADDING_TOP);
      axisLine.setAttribute("y2", CHART_HEIGHT - CHART_PADDING_BOTTOM);
      axisLine.setAttribute("stroke", color);
      axisLine.setAttribute("stroke-width", "1.5");
      axisLine.setAttribute("stroke-opacity", "0.55");
      svg.appendChild(axisLine);

      var marker = document.createElementNS(svgNS, "rect");
      marker.setAttribute("x", axisX - 4);
      marker.setAttribute("y", CHART_PADDING_TOP - 22);
      marker.setAttribute("width", 8);
      marker.setAttribute("height", 8);
      marker.setAttribute("rx", 2);
      marker.setAttribute("fill", color);
      svg.appendChild(marker);

      // 右軸刻度數字不能沿用 .trend-axis-label（那個 class 有自己的 fill 宣告，CSS 的 fill
      // 優先權高於 SVG 元素自己的 fill 屬性，會把每人的顏色蓋成同一個灰色），改用只設
      // font-size、不設 fill 的 .burndown-axis-label。
      yTicks(0, ownMax).forEach(function (tick) {
        addText(svg, axisX + 6, tick.y + 3, String(tick.value), "start", "burndown-axis-label", color);
      });

      if (idealSeries.length > 0) {
        var idealPoints = idealSeries.map(function (p) { return xAt(indexByDate[p.date]) + "," + yAt(p.hours, 0, ownMax); }).join(" ");
        var idealLine = document.createElementNS(svgNS, "polyline");
        idealLine.setAttribute("points", idealPoints);
        idealLine.setAttribute("class", "burndown-series");
        idealLine.setAttribute("data-assignee", pa.assignee);
        idealLine.setAttribute("fill", "none");
        idealLine.setAttribute("stroke", color);
        idealLine.setAttribute("stroke-width", "2");
        idealLine.setAttribute("stroke-dasharray", "6,4");
        svg.appendChild(idealLine);
      }

      var actualPoints = pa.cumulative_series.map(function (p) { return xAt(indexByDate[p.date]) + "," + yAt(p.hours, 0, ownMax); }).join(" ");
      var actualLine = document.createElementNS(svgNS, "polyline");
      actualLine.setAttribute("points", actualPoints);
      actualLine.setAttribute("class", "burndown-series");
      actualLine.setAttribute("data-assignee", pa.assignee);
      actualLine.setAttribute("fill", "none");
      actualLine.setAttribute("stroke", color);
      actualLine.setAttribute("stroke-width", "2");
      svg.appendChild(actualLine);

      pa.cumulative_series.forEach(function (point) {
        var circle = document.createElementNS(svgNS, "circle");
        circle.setAttribute("class", "burndown-series");
        circle.setAttribute("data-assignee", pa.assignee);
        circle.setAttribute("cx", xAt(indexByDate[point.date]));
        circle.setAttribute("cy", yAt(point.hours, 0, ownMax));
        circle.setAttribute("r", 3.5);
        circle.setAttribute("fill", "var(--color-surface)");
        circle.setAttribute("stroke", color);
        circle.setAttribute("stroke-width", "2");
        circle.setAttribute("tabindex", "0");
        var titleEl = document.createElementNS(svgNS, "title");
        titleEl.textContent = pa.assignee + "｜" + point.date + " ｜實際累積消耗 " + point.hours + " 小時";
        circle.appendChild(titleEl);
        svg.appendChild(circle);
      });
    });

    wrap.appendChild(svg);

    if (issue.per_assignee.length > 1) {
      wrap.appendChild(renderLegend(wrap, issue.per_assignee));
    }

    return wrap;
  }

  // 圖例：點某人的按鈕獨立切換該人是否隱藏（不是「只顯示這一人」的互斥選取），純顯示層級
  // 切換（class + opacity），不影響底層資料、燈號或右軸刻度的計算（比照 Rails
  // app/javascript/controllers/burndown_legend_controller.js 的 toggle 邏輯，這裡不需要
  // Stimulus，直接用原生事件處理；scope 限定在同一個 .burndown-chart-block 內，避免誤觸
  // 其他議題的圖表）。
  function renderLegend(scope, perAssignee) {
    var legend = document.createElement("ul");
    legend.className = "burndown-stack-legend";

    perAssignee.forEach(function (pa, idx) {
      var li = document.createElement("li");
      var button = document.createElement("button");
      button.type = "button";
      button.className = "burndown-legend-toggle";
      button.setAttribute("data-assignee", pa.assignee);
      var swatch = document.createElement("span");
      swatch.className = "burndown-stack-swatch";
      swatch.style.backgroundColor = STACK_COLORS[idx % STACK_COLORS.length];
      button.appendChild(swatch);
      button.appendChild(document.createTextNode(pa.assignee));
      button.addEventListener("click", function () {
        var hidden = button.classList.toggle("is-hidden");
        scope.querySelectorAll('[data-assignee="' + CSS.escape(pa.assignee) + '"]').forEach(function (el) {
          if (el === button) return;
          el.classList.toggle("is-dimmed", hidden);
        });
      });
      li.appendChild(button);
      legend.appendChild(li);
    });

    return legend;
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
