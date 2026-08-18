(function (global) {
  "use strict";

  // ── 模擬資料 ──────────────────────────────────────────────
  // 供 project-history-overview.js 使用，橫向總覽依 305 專案清單合併 307 燃盡議題做展示。
  // 欄位結構對齊真實試算表：305（project_name/status/...）、307（project/issue_id/.../
  // weekly_actual）、300_員工專案「專案清單」表（客戶/PM）。全部為模擬資料，不呼叫任何 API。

  // customer/pm 對齊 300_員工專案「專案清單」表（依「專案」全名 join）；
  // 比例／負責RD 等欄位與本功能呈現無關，不納入。
  var HISTORY_PROJECTS = [
    { project_name: "Virtuous HRM", status: "開發中", customer: "AMAS", pm: "楊欣翰" },
    { project_name: "JZN 舊振南智慧工廠", status: "測試中", customer: "舊振南", pm: "呂俐禎" },
    { project_name: "AG 亞炬", status: "已發布", customer: "亞炬", pm: "呂俐禎" }
  ];

  // 燃盡議題，欄位對齊 307（已依 issue_id 合併）：project, issue_id, issue_title, assignee,
  // start_date, due_date, status, estimated_hours, weekly_actual: [{date, hours}, ...]
  var HISTORY_BURNDOWN_ISSUES = [
    { project: "Virtuous HRM", issue_id: "B-2001", issue_title: "排班衝突偵測", assignee: "黃靖益／陳筱涵",
      start_date: "2026-07-08", due_date: "2026-08-24", status: "執行中", estimated_hours: 25,
      weekly_actual: [
        { date: "2026-07-08", hours: 3 }, { date: "2026-07-15", hours: 3 },
        { date: "2026-07-22", hours: 2 }, { date: "2026-07-29", hours: 1 },
        { date: "2026-08-05", hours: 2 }, { date: "2026-08-12", hours: 1 }
      ] },
    { project: "Virtuous HRM", issue_id: "B-2002", issue_title: "離職結算 PR", assignee: "蔡秉逸",
      start_date: "2026-07-08", due_date: "2026-07-20", status: "已完成", estimated_hours: 10,
      weekly_actual: [
        { date: "2026-07-08", hours: 4 }, { date: "2026-07-15", hours: 6 },
        { date: "2026-07-22", hours: 0 }, { date: "2026-07-29", hours: 0 },
        { date: "2026-08-05", hours: 0 }, { date: "2026-08-12", hours: 0 }
      ] },

    { project: "JZN 舊振南智慧工廠", issue_id: "B-1101", issue_title: "用電監測告警規則", assignee: "黃靖益",
      start_date: "2026-07-08", due_date: "2026-08-20", status: "執行中", estimated_hours: 20,
      weekly_actual: [
        { date: "2026-07-08", hours: 1 }, { date: "2026-07-15", hours: 2 },
        { date: "2026-07-22", hours: 1 }, { date: "2026-07-29", hours: 2 },
        { date: "2026-08-05", hours: 1 }, { date: "2026-08-12", hours: 1 }
      ] },

    // 落後範例：預估 40 小時，每週實際登記工時很少，剩餘人時遠高於理想線
    { project: "AG 亞炬", issue_id: "B-1001", issue_title: "API 效能優化", assignee: "王贊勛",
      start_date: "2026-07-08", due_date: "2026-08-22", status: "執行中", estimated_hours: 40,
      weekly_actual: [
        { date: "2026-07-08", hours: 2 }, { date: "2026-07-15", hours: 3 },
        { date: "2026-07-22", hours: 2 }, { date: "2026-07-29", hours: 1 },
        { date: "2026-08-05", hours: 2 }, { date: "2026-08-12", hours: 1 }
      ] },
    // 超前且超支範例：實際登記工時總計超過預估，剩餘人時變成負數
    { project: "AG 亞炬", issue_id: "B-1002", issue_title: "報表匯出功能", assignee: "蔡秉逸",
      start_date: "2026-07-08", due_date: "2026-08-01", status: "已完成", estimated_hours: 30,
      weekly_actual: [
        { date: "2026-07-08", hours: 8 }, { date: "2026-07-15", hours: 7 },
        { date: "2026-07-22", hours: 6 }, { date: "2026-07-29", hours: 5 },
        { date: "2026-08-05", hours: 6 }, { date: "2026-08-12", hours: 5 }
      ] }
  ];

  global.HISTORY_PROJECTS = HISTORY_PROJECTS;
  global.HISTORY_BURNDOWN_ISSUES = HISTORY_BURNDOWN_ISSUES;
})(window);
