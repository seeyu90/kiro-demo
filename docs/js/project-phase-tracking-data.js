(function (global) {
  "use strict";

  // ── 模擬資料 ──────────────────────────────────────────────
  // 專案階段追蹤：完全獨立於既有專案歷程（305/306/307）功能。2026-08-25 隨 Rails 真實資料串接
  // （warroom-project-phase-tracking-real-source）大幅調整過設計，這份靜態展示版同步更新，
  // 欄位形狀與真實 Sheet／Rails Actor 輸出一致，不再是最早期 Notion 截圖假設的形狀。全部為
  // 模擬資料，不呼叫任何 API。

  // 固定順序的 5 個交付階段。真實資料目前只觀察到「開案／開發／測試／發布」4 個值（「需求確認」
  // 尚未出現過任何紀錄），但使用者確認這代表「目前抽樣剛好沒有」而非「這個階段不會發生」，故
  // 常數仍保留 5 個值——這份模擬資料刻意示範一筆「需求確認」紀錄，證明畫面撐得住這個階段真的
  // 出現的情況。
  var STAGE_ORDER = ["需求確認", "開案", "開發", "測試", "發布"];

  // 專案層級資料：只有客戶／PM（真實 ProjectProfilesSheetsClient 讀 300_員工專案「專案」分頁的
  // 客戶／PM 兩欄，不含狀態——「狀態」欄那是專案維運狀態，跟本頁的議題完成狀態是兩回事，見
  // PHASE_RECORDS 附註）。key 用 project 代碼（例如 HRM、JZNPMS），對應真實 Sheet 的
  // Github/Notion 欄。
  var PROJECT_PROFILES = [
    { project: "HRM", customer: "AMAS", pm: "楊欣翰" },
    { project: "JZNPMS", customer: "舊振南", pm: "呂俐禎" },
    { project: "AGWMS", customer: "亞炬", pm: "呂俐禎" }
  ];

  // 階段紀錄：欄位對齊真實 Sheet 表頭（project, issue_id, issue_name, stage, planned_date,
  // actual_date, status, reason）。
  //
  // 【關鍵慣例，不得偏離】
  // - project + issue_id：卡片分組單位（2026-08-25 確認，不是只有 project——同一個 project
  //   代碼底下常有多個獨立的 issue_id 生命週期，見下方 HRM 出現兩次）。
  // - issue_id：議題名稱（如「v2.1調整」）或純 Redmine ID（如「4548」）皆可能出現。
  // - issue_name：只在 issue_id 是純 ID 時才會填人類可讀名稱；issue_id 本身已是描述性名稱時
  //   留空字串。
  // - actual_date：尚未完成一律為 null，禁止使用空字串 ""。
  // - status：來自階段紀錄本身（完成／延誤已完成／延誤未完成／暫緩／未完成），不是專案層級
  //   欄位；卡片顯示的「狀態」是由 STAGE_ORDER 由後往前第一個有記錄的階段之 status 推導出來的
  //   （見 computeIssueStatus），不是這裡直接存的欄位。
  // - unique_key（= project + issue_id + stage）並非真的唯一：同一個 (project, issue_id, stage)
  //   可能出現兩筆，代表「重新排程」（原本排定的時間點沒能如期完成，另外新增一筆而非覆蓋舊的），
  //   下方 JZNPMS／4548 的「開案」刻意示範這個情況。
  var PHASE_RECORDS = [
    // HRM / v2.1調整：issue_id 本身是描述性名稱，issue_name 留空。示範「需求確認」階段真的出現、
    // 一個延誤、一個提前、一個尚未完成——卡片目前狀態＝測試（未完成），符合預設篩選「狀態：未
    // 完成」會顯示出來。
    { project: "HRM", issue_id: "v2.1調整", issue_name: "", stage: "需求確認",
      planned_date: "2026-06-01", actual_date: "2026-06-01", status: "完成", reason: "" },
    { project: "HRM", issue_id: "v2.1調整", issue_name: "", stage: "開案",
      planned_date: "2026-06-05", actual_date: "2026-06-08", status: "延誤已完成", reason: "" },
    { project: "HRM", issue_id: "v2.1調整", issue_name: "", stage: "開發",
      planned_date: "2026-07-01", actual_date: "2026-06-28", status: "完成", reason: "" },
    { project: "HRM", issue_id: "v2.1調整", issue_name: "", stage: "測試",
      planned_date: "2026-07-15", actual_date: null, status: "未完成", reason: "" },
    { project: "HRM", issue_id: "v2.1調整", issue_name: "", stage: "發布",
      planned_date: "2026-07-25", actual_date: null, status: "未完成", reason: "" },

    // JZNPMS / 4548（issue_name：現場報工）：示範 issue_id 是純 Redmine ID 時 issue_name 補上
    // 人類可讀名稱；「開案」示範重新排程（同一 (project, issue_id, stage) 兩筆，較新一筆為主要
    // 呈現，較舊一筆在清單檢視展開後以次要樣式顯示）；「開發」示範 diff_days 剛好等於 0（準時，
    // 應顯示綠色，不是紅色——2026-08-25 使用者發現並修正的 bug）。卡片目前狀態＝測試（延誤已
    // 完成），預設篩選「未完成」不會顯示，切到「全部狀態」才看得到。
    { project: "JZNPMS", issue_id: "4548", issue_name: "現場報工", stage: "開案",
      planned_date: "2026-01-05", actual_date: null, status: "延誤未完成", reason: "忘記安排" },
    { project: "JZNPMS", issue_id: "4548", issue_name: "現場報工", stage: "開案",
      planned_date: "2026-01-20", actual_date: "2026-01-20", status: "完成", reason: "" },
    { project: "JZNPMS", issue_id: "4548", issue_name: "現場報工", stage: "開發",
      planned_date: "2026-02-01", actual_date: "2026-02-01", status: "完成", reason: "" },
    { project: "JZNPMS", issue_id: "4548", issue_name: "現場報工", stage: "測試",
      planned_date: "2026-02-10", actual_date: "2026-02-15", status: "延誤已完成", reason: "" },
    { project: "JZNPMS", issue_id: "4548", issue_name: "現場報工", stage: "發布",
      planned_date: "2026-02-20", actual_date: null, status: "未完成", reason: "" },

    // AGWMS / v1開發：全部完成，年度是 2025（示範年度篩選：預設只看今年，這筆要切到「全部
    // 年度」或選 2025 才會出現）。
    { project: "AGWMS", issue_id: "v1開發", issue_name: "", stage: "需求確認",
      planned_date: "2025-11-01", actual_date: "2025-11-01", status: "完成", reason: "" },
    { project: "AGWMS", issue_id: "v1開發", issue_name: "", stage: "開案",
      planned_date: "2025-11-05", actual_date: "2025-11-05", status: "完成", reason: "" },
    { project: "AGWMS", issue_id: "v1開發", issue_name: "", stage: "開發",
      planned_date: "2025-12-01", actual_date: "2025-12-10", status: "延誤已完成", reason: "" },
    { project: "AGWMS", issue_id: "v1開發", issue_name: "", stage: "測試",
      planned_date: "2025-12-15", actual_date: "2025-12-14", status: "完成", reason: "" },
    { project: "AGWMS", issue_id: "v1開發", issue_name: "", stage: "發布",
      planned_date: "2025-12-20", actual_date: "2025-12-20", status: "完成", reason: "" },

    // HRM / 5164（issue_name：調整2.0.1）：跟上面的「HRM / v2.1調整」同一個 project 代碼、不同
    // issue_id，示範同一 project 底下多個獨立生命週期。目前卡在「暫緩」——示範「暫緩不屬於
    // 未完成」（2026-08-25 使用者確認），預設篩選「未完成」不會顯示這張卡片。
    { project: "HRM", issue_id: "5164", issue_name: "調整2.0.1", stage: "開案",
      planned_date: "2026-08-01", actual_date: "2026-08-01", status: "完成", reason: "" },
    { project: "HRM", issue_id: "5164", issue_name: "調整2.0.1", stage: "開發",
      planned_date: "2026-08-10", actual_date: null, status: "暫緩", reason: "客戶因素" },

    // JZNPMS / 外包裝調整：2026 年、目前未完成，讓預設篩選（今年＋未完成）不會只有一張卡片。
    { project: "JZNPMS", issue_id: "外包裝調整", issue_name: "", stage: "開案",
      planned_date: "2026-07-01", actual_date: "2026-07-01", status: "完成", reason: "" },
    { project: "JZNPMS", issue_id: "外包裝調整", issue_name: "", stage: "開發",
      planned_date: "2026-08-15", actual_date: null, status: "未完成", reason: "" }
  ];

  global.STAGE_ORDER = STAGE_ORDER;
  global.PROJECT_PROFILES = PROJECT_PROFILES;
  global.PHASE_RECORDS = PHASE_RECORDS;
})(window);
