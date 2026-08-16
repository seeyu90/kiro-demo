# 設計文件

## 概述

新增兩個獨立頁面 `docs/project-history-overview.html`（橫向總覽）、
`docs/project-history-detail.html`（縱向歷程），各自搭配 `docs/js/project-history-overview.js`、
`docs/js/project-history-detail.js`。既有 `docs/project-progress.html`、`docs/issues.html`、
`docs/burndown.html` 與其對應 JS **完全不修改**，僅 `docs/index.html` 新增卡片連結、
`docs/css/style.css` 擴充新增的樣式規則。全部為純前端 JavaScript，資料來自各自檔案內的模擬資料
常數，不呼叫外部 API，不引入建置工具或圖表框架。

**307 上線後的資料來源調整**：`warroom-project-burndown-tracking`（307）已實作完成，提供每個議題的
`estimated_hours`（預估人時）與逐週實際登記人時（`weekly_actual`），並已有經測試驗證的「理想剩餘
人時／實際剩餘人時」燃盡序列計算邏輯（`docs/js/burndown.js` 的 `computeIdealSeries`／
`computeActualSeries`／`mergeRows`，與 Rails `Sheets::FetchProjectBurndown` 對應邏輯一致）。本 spec
的「花費工時趨勢」（需求 5）與「每週進度達成率」（需求 6）**直接沿用 307 的資料結構與計算邏輯**，
不再假設 306 的 `work_days` 或即時計算任務完成率。

**客戶／PM 資料來源**：`300_員工專案` 試算表（`101fF0GlW2iwjC6TNQnNgKjUrxJg-3Ia5nCYox6haTNM`）「專案
清單」表提供 `客戶`／`PM` 欄位，以「專案」全名對應 305/306/307 的專案名稱。本 spec 的橫向總覽頁
「客戶」「PM」篩選（需求 2.2）直接沿用此結構，不再是待確認項。

---

## 架構

```
docs/
├── index.html                        ← 修改：新增「專案歷程」卡片連結
├── project-progress.html             ← 不動（305）
├── issues.html                       ← 不動（306）
├── burndown.html                     ← 不動（307）
├── project-history-overview.html     ← 新：橫向總覽（篩選＋清單/甘特圖）
├── project-history-detail.html       ← 新：縱向歷程（單一專案時間軸）
├── css/
│   └── style.css                     ← 擴充：入口頁新卡片、甘特圖、歷程趨勢圖樣式
└── js/
    ├── project-history-overview.js   ← 新：橫向總覽模擬資料 + 渲染邏輯
    └── project-history-detail.js     ← 新：縱向歷程模擬資料 + 渲染邏輯
```

兩個新頁面各自的模擬資料**皆是同一份「歷程資料集」的檢視**（同一批專案/任務/議題/燃盡議題資料，
總覽頁做橫向聚合、詳情頁做單一專案篩選），因此共用資料結構定義，避免總覽與詳情兩頁資料兜不起來。
實作時以獨立的 `docs/js/project-history-data.js` 集中定義模擬資料常數，兩個渲染 JS 皆引入此檔案
（比照 `issues.js` 內部即定義資料的簡單慣例，但因兩頁共用同一份資料，抽成獨立檔案避免重複維護
兩份）：

```
docs/js/project-history-data.js
    ├── HISTORY_PROJECTS   // 專案基本資訊：project_name, status, customer(客戶), pm(PM),
    │                      //   planned_completion_date(專案層級最早),
    │                      //   actual_completion_date(專案層級最晚/null=進行中)
    │                      //   customer/pm 欄位對齊 300_員工專案「專案清單」表的 客戶/PM 欄位
    ├── HISTORY_TASKS      // 任務明細，欄位對齊 305 Sheet：project_name, task_name, status, owner,
    │                      //   planned_completion_date, actual_completion_date, delay_days, task_type
    ├── HISTORY_ISSUES     // 議題明細，欄位對齊 306 raw_YYYY：issue_id, subject, type, tracker, status,
    │                      //   assigned_to, start_date, due_date, work_days, project
    └── HISTORY_BURNDOWN_ISSUES  // 燃盡議題，欄位對齊 307（已依 issue_id 合併）：project, issue_id,
                               //   issue_title, assignee, start_date, due_date, status,
                               //   estimated_hours, weekly_actual: [{date, hours}, ...]
```

`HISTORY_BURNDOWN_ISSUES` 的資料與計算邏輯（合併同 `issue_id` 多列、理想/實際剩餘人時序列）直接
比照 `docs/js/burndown.js` 既有實作模式；因是獨立靜態頁彼此不共用程式碼（同既有 305/306/307 慣例），
本 spec 的 `project-history-detail.js` 需重寫一份邏輯相同的函式，而非 `import`/`require` 該檔案。

---

## 元件與介面

### 模擬資料（`docs/js/project-history-data.js`）

資料筆數精簡（3〜4 個專案、每專案 5〜10 筆任務、5〜10 筆議題即可，重點是展示畫面而非資料量）：

```js
var HISTORY_PROJECTS = [
  // customer/pm 欄位對齊 300_員工專案「專案清單」表（依「專案」全名 join），比例/負責RD 欄位
  // 與本 spec 呈現無關，不納入
  { project_name: "Virtuous HRM", status: "開發中", customer: "AMAS", pm: "楊欣翰" },
  { project_name: "JZN 舊振南智慧工廠", status: "測試中", customer: "舊振南", pm: "呂俐禎" },
  { project_name: "AG 亞炬", status: "已發布", customer: "亞炬", pm: "呂俐禎" }
];

var HISTORY_TASKS = [
  // { project_name, task_name, status, owner, planned_completion_date, actual_completion_date, delay_days, task_type }
  { project_name: "Virtuous HRM", task_name: "請假模組串接", status: "已完成", owner: "黃靖益",
    planned_completion_date: "2026-07-06", actual_completion_date: "2026-07-08", delay_days: 2, task_type: "功能" },
  // ...更多任務，涵蓋多週跨度以利需求 6 週彙總展示
];

var HISTORY_ISSUES = [
  // { issue_id, subject, type, tracker, status, assigned_to, start_date, due_date, work_days, project }
  { issue_id: 5160, subject: "[客訴] A3原料發貨異常", type: "Complaint", tracker: "臭蟲",
    status: "已解決", assigned_to: "王贊勛", start_date: "2026-08-11", due_date: "2026-08-11",
    work_days: 0, project: "JZN 舊振南智慧工廠" },
  // ...更多議題，涵蓋 Complaint／TestingBug 兩種 type，且 Complaint 需包含至少一筆非「已結束/已解決」
  //    狀態的樣本，以驗證需求 7.3「未解決客訴清單」
];

var REDMINE_ISSUE_URL_BASE = "https://redmine.amastek.com.tw/issues/";

var HISTORY_BURNDOWN_ISSUES = [
  // 已依 issue_id 合併（比照 burndown.js 的 mergeRows()）；欄位對齊 307 燃盡議題結構
  { project: "Virtuous HRM", issue_id: "B-2001", issue_title: "排班衝突偵測", assignee: "黃靖益／陳筱涵",
    start_date: "2026-07-08", due_date: "2026-08-24", status: "執行中", estimated_hours: 25,
    weekly_actual: [
      { date: "2026-07-08", hours: 3 }, { date: "2026-07-15", hours: 3 },
      { date: "2026-07-22", hours: 2 }, { date: "2026-07-29", hours: 1 },
      { date: "2026-08-05", hours: 2 }, { date: "2026-08-12", hours: 1 }
    ] }
  // ...每個 HISTORY_PROJECTS 專案至少一筆，供需求 5、6 的趨勢圖有資料可畫
];
```

`HISTORY_PROJECTS` 的 `status` 為專案整體狀態（篩選用），`HISTORY_TASKS`／`HISTORY_ISSUES` 皆以
`project_name`／`project` 欄位關聯回 `HISTORY_PROJECTS`。

### 橫向總覽頁（`project-history-overview.js`）

- `state.filters = { status: null, customer: null, pm: null }`（皆不篩選／全部）；`initFilters()`
  讀取 `HISTORY_PROJECTS` 唯一 `status`／`customer`／`pm` 值分別產生三個下拉選項（需求 2.1、2.2）。
- `applyFilters(projects)`：依 `state.filters` 三者交集篩選（需求 2.3），供 `renderProjectList`／
  `renderGanttChart` 共用。
- `renderProjectList(projects)`：清單檢視，複用既有 `buildGenericTable` 樣式慣例，欄位為專案名稱、
  客戶、PM、狀態、預計完成日期（該專案任務中最晚的 `planned_completion_date`）、實際完成日期（該
  專案任務中最晚的 `actual_completion_date`，若任一任務尚無實際完成日期則顯示「進行中」）。
- `renderGanttChart(projects, tasks)`：手刻 SVG 條狀圖，每個專案一列，每個任務一個色塊，X 軸為日期
  （依全體任務的最早 `planned_completion_date` 至最晚 `actual_completion_date`／今日 等比例縮放）；
  無需真實時間比例尺精度，等比例呈現即可。
- `state.viewMode = "list"`；`<button>` 切換 `state.viewMode` 並呼叫對應渲染函式，不使用 radio+label
  純 CSS 方案（因需要依篩選後資料重新渲染 SVG，本來就需要 JS 介入，不必額外用 CSS-only 技巧）。
- 專案清單／甘特圖的專案名稱（或條狀圖區塊）皆為可點擊連結，導向
  `project-history-detail.html?project={encodeURIComponent(project_name)}`（需求 4.2）。

### 縱向歷程頁（`project-history-detail.js`）

- `getProjectFromQuery()`：解析 `location.search` 取得 `project` 參數；`initProjectSelect()` 讀取
  `HISTORY_PROJECTS` 產生下拉選項，`value` 初始化為 query string 值，若無效則預設第一筆（需求 4.4）。
- `renderDetail(projectName)`：統一入口，依 `projectName` 篩選 `HISTORY_TASKS`／`HISTORY_ISSUES`／
  `HISTORY_BURNDOWN_ISSUES` 後分派至下列各渲染函式：
  - `renderWorkHoursTrend(burndownIssues)`（需求 5）：依所選專案的 `HISTORY_BURNDOWN_ISSUES` 子集，
    逐週加總各議題 `weekly_actual[].hours`（同一週日期對齊加總，比照 `burndown.js` 的
    `sumProjectSeries` 手法），以折線圖呈現週人時趨勢，複用 `issues.js` 既有 `renderTrendChart` 的
    手刻 SVG 折線圖手法（新檔案獨立實作，不共用函式，避免跨檔案耦合）。
  - `computeProjectBurndown(burndownIssues)`（需求 6）：重寫一份與 `burndown.js` 邏輯一致的
    `computeIdealSeries(issue)`／`computeActualSeries(issue)`（線性分攤理想剩餘人時／逐週累減實際
    剩餘人時），再依日期彙總所選專案全部議題的兩條序列；`due_date` 不晚於 `start_date` 或缺失時，
    該議題理想序列排為空陣列，不納入理想線彙總（需求 6.3）。`renderBurndownChart(idealSeries,
    actualSeries)` 於同一張 SVG 疊合渲染兩條折線（實線＝實際、虛線＝理想，比照 307 既有樣式）。
  - `renderTestingTrend(issues)`（需求 7.1）：篩選 `type === "TestingBug"`，依 `start_date` 週別分組
    計數，折線圖呈現。
  - `computeComplaintStatus(issues)`（需求 7.2）：篩選 `type === "Complaint"`，依 `status` 屬於
    `["已結束", "已解決"]` 判斷已解決／未解決，回傳 `{ resolved_count, unresolved_count,
    unresolved_list }`；`renderComplaintSummary(result)` 顯示統計數字＋`unresolved_list` 表格
    （議題編號連結、主旨、狀態、`start_date`，需求 7.3）。
- 各區塊皆有對應空狀態文字（需求 5.2、7.4），比照既有 `.empty-state` class。

---

## 資料模型

| 資料集 | 欄位 |
|---|---|
| `HISTORY_PROJECTS` | `project_name, status, customer, pm` |
| `HISTORY_TASKS` | `project_name, task_name, status, owner, planned_completion_date, actual_completion_date, delay_days, task_type` |
| `HISTORY_ISSUES` | `issue_id, subject, type, tracker, status, assigned_to, start_date, due_date, work_days, project` |
| `HISTORY_BURNDOWN_ISSUES` | `project, issue_id, issue_title, assignee, start_date, due_date, status, estimated_hours, weekly_actual: [{date, hours}]` |

欄位命名與型別對齊 `warroom-data-api-prototype/app/actors/sheets/fetch_project_progress.rb`
（`COLUMN_KEYS`）、`fetch_issue_dashboard.rb`、`fetch_project_burndown.rb` 既有欄位定義，以及
`300_員工專案`「專案清單」表的 `客戶`／`PM` 欄位，確保之後 real-source spec 串接真實 Sheets 時，
前端資料結構不需大改。

---

## 錯誤處理

- 空值欄位（`actual_completion_date`、`due_date`、`work_days` 等）一律顯示 `—`，不拋出例外。
- 篩選／計算後無資料：顯示提示文字，不留白、不隱藏欄位標題列（需求 2.4、4.4、5.2、6.3、7.4）。
- `computeIdealSeries` 於 `due_date` 不晚於 `start_date` 或缺失時回傳空陣列，不計算除以零（需求 6.3）。

---

## 待確認事項對本設計的影響

requirements.md 開頭列出的全部 4 項待確認事項，已因 307（人時燃盡追蹤）上線與 `300_員工專案`
試算表內容確認而全數解決，均已反映於上方各段落，本設計無殘留的待確認項。

---

## 測試策略（手動驗證）

由於 `docs/` 靜態站不使用建置工具或測試框架，以手動瀏覽器驗證為主：

1. 開啟 `docs/index.html`，確認新增「專案歷程」卡片可正確導向 `project-history-overview.html`；
   既有兩張卡片行為不變（需求 1.1、1.2）。
2. 開啟 `docs/project-history-overview.html`：
   - 確認狀態、客戶、PM 三個篩選下拉選單各自可正確篩選專案清單，同時選取多個條件時取交集
     （需求 2.1〜2.3）；篩選至無結果時顯示提示文字（需求 2.4）。
   - 確認清單／甘特圖切換正常運作，不觸發頁面重新載入；預設顯示清單檢視（需求 3.1、3.4、3.5）。
   - 確認甘特圖以色塊呈現任務區間，圖形與清單資料一致（需求 3.3）。
   - 點擊任一專案，確認正確導向 `project-history-detail.html` 並帶正確 `project` query string
     （需求 4.2）。
3. 開啟 `docs/project-history-detail.html?project=Virtuous+HRM`：
   - 確認頁面預選該專案；下拉選單切換專案後，所有區塊正確重新渲染（需求 4.1、4.3）。
   - 確認花費工時趨勢圖依 307 燃盡議題週人時正確繪製（需求 5.1）；改用 307 無資料之專案驗證空狀態
     文字（需求 5.2）。
   - 確認理想／實際剩餘人時燃盡圖正確計算並疊合繪製兩條線；缺少合法起訖日期的議題不計入理想線彙總
     （需求 6.1〜6.3）。
   - 確認測試問題趨勢圖正確繪製（需求 7.1）；客訴議題統計數字與「未解決客訴」清單正確，議題編號
     連結可正確導向 Redmine（需求 7.2、7.3）；改用無客訴議題之專案驗證空狀態文字（需求 7.4）。
4. 縮小視窗至手機寬度，確認兩個新頁面所有區塊不破版（需求 8.3）；確認深色/淺色主題切換正常
   （需求 8.4）。
5. 確認整頁繁體中文，無 console 錯誤。
