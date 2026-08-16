(function (global) {
  "use strict";

  // ── 模擬資料 ──────────────────────────────────────────────
  // 供 project-history-overview.js／project-history-detail.js 共用，兩頁對同一批
  // 專案／任務／議題／燃盡議題資料做不同角度的呈現（總覽做橫向聚合，詳情做單一專案篩選）。
  // 欄位結構對齊真實試算表：305（project_name/task_name/...）、306（issue_id/subject/...）、
  // 307（project/issue_id/.../weekly_actual）、300_員工專案「專案清單」表（客戶/PM）。
  // 全部為模擬資料，不呼叫任何 API。

  // customer/pm 對齊 300_員工專案「專案清單」表（依「專案」全名 join）；
  // 比例／負責RD 等欄位與本功能呈現無關，不納入。
  var HISTORY_PROJECTS = [
    { project_name: "Virtuous HRM", status: "開發中", customer: "AMAS", pm: "楊欣翰" },
    { project_name: "JZN 舊振南智慧工廠", status: "測試中", customer: "舊振南", pm: "呂俐禎" },
    { project_name: "AG 亞炬", status: "已發布", customer: "亞炬", pm: "呂俐禎" }
  ];

  // 任務明細，欄位對齊 305 專案進度 Sheet
  var HISTORY_TASKS = [
    { project_name: "Virtuous HRM", task_name: "請假模組串接", status: "完成", owner: "黃靖益",
      planned_completion_date: "2026-07-06", actual_completion_date: "2026-07-08", delay_days: 2, task_type: "功能" },
    { project_name: "Virtuous HRM", task_name: "排班衝突偵測", status: "未完成", owner: "黃靖益",
      planned_completion_date: "2026-08-24", actual_completion_date: null, delay_days: null, task_type: "功能" },
    { project_name: "Virtuous HRM", task_name: "離職結算 PR", status: "完成", owner: "蔡秉逸",
      planned_completion_date: "2026-07-20", actual_completion_date: "2026-07-19", delay_days: -1, task_type: "PR" },

    { project_name: "JZN 舊振南智慧工廠", task_name: "A3 原料發貨流程調整", status: "已確認", owner: "王贊勛",
      planned_completion_date: "2026-08-11", actual_completion_date: "2026-08-11", delay_days: 0, task_type: "調整" },
    { project_name: "JZN 舊振南智慧工廠", task_name: "用電監測告警規則", status: "未完成", owner: "黃靖益",
      planned_completion_date: "2026-08-20", actual_completion_date: null, delay_days: null, task_type: "功能" },
    { project_name: "JZN 舊振南智慧工廠", task_name: "產線報表遺漏欄位補齊", status: "完成", owner: "邱珮玲",
      planned_completion_date: "2026-07-15", actual_completion_date: "2026-07-18", delay_days: 3, task_type: "遺漏" },

    { project_name: "AG 亞炬", task_name: "API 效能優化", status: "未完成", owner: "王贊勛",
      planned_completion_date: "2026-08-22", actual_completion_date: null, delay_days: null, task_type: "功能" },
    { project_name: "AG 亞炬", task_name: "報表匯出功能", status: "完成", owner: "蔡秉逸",
      planned_completion_date: "2026-08-01", actual_completion_date: "2026-07-30", delay_days: -2, task_type: "功能" },
    { project_name: "AG 亞炬", task_name: "Notify Center PR", status: "完成", owner: "陳謹皓",
      planned_completion_date: "2026-07-10", actual_completion_date: "2026-07-10", delay_days: 0, task_type: "PR" }
  ];

  // 議題明細，欄位對齊 306 raw_YYYY 分頁（合併後）；type: Complaint（客訴）／TestingBug（測試）
  var HISTORY_ISSUES = [
    { issue_id: 4547, subject: "[客訴] 未匯入 2026 行事曆", type: "Complaint", tracker: "臭蟲",
      status: "已結束", assigned_to: "黃靖益", start_date: "2026-07-02", due_date: "2026-07-06",
      work_days: 3, project: "Virtuous HRM" },
    { issue_id: 4884, subject: "[測試] 按離職結算，出現伺服器錯誤", type: "TestingBug", tracker: "臭蟲",
      status: "已結束", assigned_to: "黃靖益", start_date: "2026-07-18", due_date: null,
      work_days: null, project: "Virtuous HRM" },
    { issue_id: 5165, subject: "[測試] Cloud Admin 申請白名單 申請時間錯誤", type: "TestingBug", tracker: "臭蟲",
      status: "新建立", assigned_to: "蔡秉逸", start_date: "2026-08-12", due_date: null,
      work_days: null, project: "Virtuous HRM" },

    { issue_id: 5160, subject: "[客訴] A3原料發貨異常", type: "Complaint", tracker: "臭蟲",
      status: "已解決", assigned_to: "王贊勛", start_date: "2026-08-11", due_date: "2026-08-11",
      work_days: 0, project: "JZN 舊振南智慧工廠" },
    { issue_id: 5171, subject: "[客訴] 廠區用電監測告警延遲", type: "Complaint", tracker: "臭蟲",
      status: "新建立", assigned_to: "黃靖益", start_date: "2026-08-13", due_date: null,
      work_days: null, project: "JZN 舊振南智慧工廠" },
    { issue_id: 4990, subject: "[測試] 產線報表匯出逾時", type: "TestingBug", tracker: "臭蟲",
      status: "已結束", assigned_to: "邱珮玲", start_date: "2026-07-16", due_date: null,
      work_days: null, project: "JZN 舊振南智慧工廠" },

    { issue_id: 3058, subject: "[PMS] 結案小工序DeadlockVictim", type: "Other", tracker: "臭蟲",
      status: "已暫停", assigned_to: "王贊勛", start_date: "2024-04-29", due_date: null,
      work_days: null, project: "AG 亞炬" },
    { issue_id: 5188, subject: "[測試] 報表匯出欄位順序錯誤", type: "TestingBug", tracker: "臭蟲",
      status: "已結束", assigned_to: "蔡秉逸", start_date: "2026-07-29", due_date: null,
      work_days: null, project: "AG 亞炬" }
  ];

  var REDMINE_ISSUE_URL_BASE = "https://redmine.amastek.com.tw/issues/";

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
  global.HISTORY_TASKS = HISTORY_TASKS;
  global.HISTORY_ISSUES = HISTORY_ISSUES;
  global.HISTORY_BURNDOWN_ISSUES = HISTORY_BURNDOWN_ISSUES;
  global.HISTORY_REDMINE_ISSUE_URL_BASE = REDMINE_ISSUE_URL_BASE;
})(window);
