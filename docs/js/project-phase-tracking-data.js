(function (global) {
  "use strict";

  // ── 模擬資料 ──────────────────────────────────────────────
  // 專案階段追蹤：完全獨立於既有專案歷程（305/306/307）功能，資料來源改為 Notion 資料庫
  // （見 .kiro/specs/warroom-project-phase-tracking-static-prototype/design.md「Prototype Data
  // Contract」）。全部為模擬資料，不呼叫任何 API。

  // 固定順序的 5 個交付階段（prototype 明確規則，非動態推導 — 見 requirements.md 待確認事項 3）
  var STAGE_ORDER = ["需求確認", "開案", "開發", "測試", "發布"];

  // 專案基本資料：customer/pm/status/planned_completion_date（專案層級）真實來源待確認
  // （見 requirements.md 待確認事項 2），本階段先用獨立模擬資料表示。
  var PROJECT_PROFILES = [
    { project_name: "電商平台改版", customer: "台灣零售股份有限公司", pm: "王小明",
      status: "開發中", planned_completion_date: "2026-05-31" },
    { project_name: "內控調整2510", customer: "舊振南", pm: "呂俐禎",
      status: "已發布", planned_completion_date: "2025-12-15" },
    { project_name: "倉儲效能優化", customer: "亞炬", pm: "呂俐禎",
      status: "測試中", planned_completion_date: "2026-07-31" },
    { project_name: "會員系統評估", customer: "台灣零售股份有限公司", pm: "王小明",
      status: "需求確認中", planned_completion_date: "2026-09-30" }
  ];

  // 階段紀錄：對齊未來 Notion 階段紀錄 database 欄位（日期→planned_date、實際完成→actual_date、
  // 專案→project、類型→stage、狀態→status、原因→reason）。
  //
  // 【關鍵慣例，不得偏離 — 見 design.md「Prototype Data Contract」】
  // - project：純字串，值等於對應 PROJECT_PROFILES 的 project_name，用來模擬 Notion relation。
  // - actual_date：尚未完成一律為 null，禁止使用空字串 ""。
  // - status：actual_date 為 null 時一律也為 null，不發明「進行中」等真實資料未觀察到的狀態值
  //   （此規則僅為本檔案模擬資料的撰寫慣例，非對真實 Notion 資料的假設）。
  // - 每個專案固定建立 STAGE_ORDER 全部 5 筆（含尚未發生的階段），僅「會員系統評估」刻意不建立
  //   任何一筆，用來驗證「完全沒有 PHASE_RECORDS」的容錯情境（需求 4.6）。
  var PHASE_RECORDS = [
    // 電商平台改版：部分階段未完成
    { project: "電商平台改版", stage: "需求確認", planned_date: "2026-02-15",
      actual_date: "2026-02-18", status: "完成", reason: "" },
    { project: "電商平台改版", stage: "開案", planned_date: "2026-03-01",
      actual_date: "2026-03-03", status: "完成", reason: "" },
    { project: "電商平台改版", stage: "開發", planned_date: "2026-05-31",
      actual_date: null, status: null, reason: "" },
    { project: "電商平台改版", stage: "測試", planned_date: "2026-06-20",
      actual_date: null, status: null, reason: "" },
    { project: "電商平台改版", stage: "發布", planned_date: "2026-06-30",
      actual_date: null, status: null, reason: "" },

    // 內控調整2510：全部完成，對齊使用者提供的真實 Notion 截圖範例（含 reason 備註延遲發布）
    { project: "內控調整2510", stage: "需求確認", planned_date: "2025-10-25",
      actual_date: "2025-10-28", status: "完成", reason: "" },
    { project: "內控調整2510", stage: "開案", planned_date: "2025-10-28",
      actual_date: "2025-10-28", status: "完成", reason: "" },
    { project: "內控調整2510", stage: "開發", planned_date: "2025-11-04",
      actual_date: "2025-11-07", status: "完成", reason: "" },
    { project: "內控調整2510", stage: "測試", planned_date: "2025-11-11",
      actual_date: "2025-11-13", status: "完成", reason: "" },
    { project: "內控調整2510", stage: "發布", planned_date: "2025-11-13",
      actual_date: "2025-12-15", status: "完成", reason: "與內控調整2511一起發布" },

    // 倉儲效能優化：含至少一階段提前完成（開案／開發皆早於預計），測試/發布尚未完成
    { project: "倉儲效能優化", stage: "需求確認", planned_date: "2026-06-01",
      actual_date: "2026-06-01", status: "完成", reason: "" },
    { project: "倉儲效能優化", stage: "開案", planned_date: "2026-06-05",
      actual_date: "2026-06-04", status: "完成", reason: "" },
    { project: "倉儲效能優化", stage: "開發", planned_date: "2026-07-10",
      actual_date: "2026-07-08", status: "完成", reason: "" },
    { project: "倉儲效能優化", stage: "測試", planned_date: "2026-07-20",
      actual_date: null, status: null, reason: "" },
    { project: "倉儲效能優化", stage: "發布", planned_date: "2026-07-31",
      actual_date: null, status: null, reason: "" }

    // 會員系統評估：刻意不建立任何 PHASE_RECORDS，驗證需求 4.6 的空值容錯
  ];

  global.STAGE_ORDER = STAGE_ORDER;
  global.PROJECT_PROFILES = PROJECT_PROFILES;
  global.PHASE_RECORDS = PHASE_RECORDS;
})(window);
