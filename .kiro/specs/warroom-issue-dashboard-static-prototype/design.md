# 設計文件

## Overview

新增 `docs/issues.html` + `docs/js/issues.js`，並將既有 `docs/index.html`（305 戰情室本體）搬移為
`docs/project-progress.html` + `docs/js/project-progress.js`（由 `app.js` 更名，內容不變），`docs/index.html`
改為極簡入口頁。全部為純前端 JavaScript，資料來自 `issues.js` 內的模擬資料常數，不呼叫外部 API，
不引入建置工具或圖表框架。

---

## Architecture

```
docs/
├── index.html              ← 新：極簡入口頁（連到下方兩頁）
├── project-progress.html   ← 新：既有 index.html 內容原樣搬移（305）
├── issues.html              ← 新：306 臭蟲議題 prototype 頁面
├── css/
│   └── style.css            ← 擴充：入口頁卡片、KPI 卡片、趨勢圖、負載表樣式
└── js/
    ├── project-progress.js  ← 新：由 app.js 更名搬移（305，內容不變）
    └── issues.js             ← 新：306 模擬資料 + 渲染邏輯
```

`issues.js` 內部結構（比照 `project-progress.js` 的 IIFE + 模組內 state 慣例）：

```
DOMContentLoaded
    │
    ▼
populateMonthSelect()  ──┐
initProjectFilter()        │  初始化各區塊控制項（皆讀取模擬資料產生選項）
initStatusFilter()         │
    │                      │
    ▼                      ▼
renderKpiCards(month)             ← 需求 2
renderTrendChart(DAILY_KPI)       ← 需求 3
renderIssueTable(state)           ← 需求 4，篩選變更時重新渲染
renderEngineerLoadTable()         ← 需求 5，靜態渲染一次
renderProjectListTable()          ← 需求 5，靜態渲染一次
```

---

## Components and Interfaces

### 模擬資料（`docs/js/issues.js`）

依真實 306 試算表分頁欄位結構仿造，資料筆數精簡（每張表 4〜8 筆樣本即可，重點是展示畫面而非資料量）：

```js
var MONTH_KPI = [
  { year_month: "2026-06", complaint: 34, testing: 8, total_bug: 42, block_rate: 19.05, completed: 5, unresolved: 1, avg_days: 1.88, sla_rate: 11.76, top3: [["王贊勛", 16], ["黃靖益", 7], ["蔡秉逸", 6]] },
  { year_month: "2026-07", complaint: 28, testing: 7, total_bug: 35, block_rate: 20.00, completed: 10, unresolved: 7, avg_days: 2.61, sla_rate: 10.71, top3: [["王贊勛", 20], ["沈舫竹", 6], ["陳謹皓", 4]] },
  { year_month: "2026-08", complaint: 15, testing: 9, total_bug: 24, block_rate: 37.50, completed: 6, unresolved: 3, avg_days: 3.10, sla_rate: 25.00, top3: [["黃靖益", 9], ["王贊勛", 8], ["邱珮玲", 4]] }
];

var DAILY_KPI = [
  // { date: "YYYY-MM-DD", complaint, testing, other, total }
  { date: "2026-08-01", complaint: 0, testing: 1, other: 0, total: 1 },
  { date: "2026-08-04", complaint: 4, testing: 0, other: 0, total: 4 },
  { date: "2026-08-06", complaint: 0, testing: 2, other: 0, total: 2 },
  { date: "2026-08-08", complaint: 1, testing: 4, other: 0, total: 5 },
  { date: "2026-08-11", complaint: 0, testing: 4, other: 0, total: 4 },
  { date: "2026-08-12", complaint: 1, testing: 0, other: 0, total: 1 },
  { date: "2026-08-13", complaint: 0, testing: 0, other: 0, total: 0 }
];

var ISSUES = [
  // { issue_id, subject, type, tracker, status, assigned_to, start_date, due_date, work_days, project }
  { issue_id: 4547, subject: "[客訴] 未匯入 2026 行事曆", type: "Complaint", tracker: "臭蟲", status: "已結束", assigned_to: "黃靖益", start_date: "2026-01-02", due_date: "2026-01-06", work_days: 3, project: "Virtuous HRM" },
  { issue_id: 4884, subject: "[測試] 按離職結算，出現伺服器錯誤", type: "TestingBug", tracker: "臭蟲", status: "已結束", assigned_to: "黃靖益", start_date: "2026-05-18", due_date: null, work_days: null, project: "Virtuous HRM" },
  { issue_id: 5160, subject: "[客訴] A3原料發貨異常", type: "Complaint", tracker: "臭蟲", status: "已解決", assigned_to: "王贊勛", start_date: "2026-08-11", due_date: "2026-08-11", work_days: 0, project: "JZN 舊振南智慧工廠" },
  { issue_id: 5165, subject: "[測試] Cloud Admin 申請白名單 申請時間錯誤", type: "TestingBug", tracker: "臭蟲", status: "新建立", assigned_to: "蔡秉逸", start_date: "2026-08-12", due_date: null, work_days: null, project: "Virtuous HRM" },
  { issue_id: 3058, subject: "[PMS] 結案小工序DeadlockVictim", type: "Other", tracker: "臭蟲", status: "已暫停", assigned_to: "王贊勛", start_date: "2024-04-29", due_date: null, work_days: null, project: "AG 亞炬" }
];

var ENGINEER_LOAD = [
  // { name, project, allocation_pct, effective_month, expire_month, total_pct }
  { name: "黃紹鈞", project: "RAG", allocation_pct: 40, effective_month: "2026/05", expire_month: "2026/12", total_pct: 115 },
  { name: "陳謹皓", project: "客服支援", allocation_pct: 15, effective_month: "2026/01", expire_month: null, total_pct: 15 }
];

var PROJECT_LIST = [
  // { name, abbr, status, allocation_pct, effective_month, expire_month, owner_rd }
  { name: "KKY - 地瓜生產管理系統", abbr: "瓜瓜園 KKPMS", status: "維護", allocation_pct: 20, effective_month: "2026/01", expire_month: "2026/12", owner_rd: "周詩御,呂俐禛,楊采維(5%)" }
];
```

`assigned_to` 可能為空字串／`null`（真實資料常見未指派情境），渲染時比照既有 `formatValue()` 慣例
顯示 `—`。`due_date`／`work_days` 亦常為空，同樣處理。

### KPI 摘要卡片（需求 2）

- `populateMonthSelect()`：讀取 `MONTH_KPI` 產生月份下拉選單，預設選中陣列最後一筆（最新月份）。
- `renderKpiCards(monthRecord)`：依卡片渲染 8 個統計值 + Top3 排行列表，複用既有 `.stat-item` /
  `.stat-value` / `.stat-label` CSS class 命名慣例（沿用 `project-progress` 頁面摘要列風格）。

### 每日趨勢圖（需求 3）

- `renderTrendChart(records)`：手刻 SVG 折線圖。
  - X 軸：日期（`DAILY_KPI` 陣列順序，等距分佈，不需要真實時間比例尺）。
  - Y 軸：`total` 欄位數值，依資料最大值等比例縮放高度。
  - 折線：`<polyline>` 連接各資料點；資料點另加 `<circle>`，`title` 子元素或 `data-*` 屬性搭配
    `mouseenter`/`touchstart` 事件顯示 tooltip（純 DOM，不需額外函式庫）。
  - 不需要處理超大量資料點（模擬資料僅 7 筆），無需虛擬捲動或降採樣。

### Issue 明細清單（需求 4）

- `state.issueFilters = { project: null, status: null }`（`null` = 不篩選／全部）。
- `initProjectFilter()` / `initStatusFilter()`：讀取 `ISSUES` 內唯一值產生下拉選項，`change` 事件更新
  `state.issueFilters` 並呼叫 `renderIssueTable()`。
- `renderIssueTable(state)`：依 `state.issueFilters` 過濾 `ISSUES`，複用既有 `buildTable`-like 邏輯
  （建立 `<table>`／`<thead>`／`<tbody>`），欄位標籤中文化（如「議題編號」「主旨」「類型」…）。
- 篩選後為空集合時顯示「目前無符合條件的議題」（比照既有 `.empty-state` class）。

### 工程師負載／專案清單（需求 5）

- 兩張表格頁面載入時各自靜態渲染一次（`renderEngineerLoadTable()` / `renderProjectListTable()`），
  不提供篩選，維持最簡實作（僅為呈現既有資料形狀）。

---

## Data Models

| 資料集 | 欄位 |
|---|---|
| `MONTH_KPI` | `year_month, complaint, testing, total_bug, block_rate, completed, unresolved, avg_days, sla_rate, top3` |
| `DAILY_KPI` | `date, complaint, testing, other, total` |
| `ISSUES` | `issue_id, subject, type, tracker, status, assigned_to, start_date, due_date, work_days, project` |
| `ENGINEER_LOAD` | `name, project, allocation_pct, effective_month, expire_month, total_pct` |
| `PROJECT_LIST` | `name, abbr, status, allocation_pct, effective_month, expire_month, owner_rd` |

（欄位命名使用英文 key + 中文顯示標籤，比照 `project-progress.js` 既有慣例，非直接沿用試算表中文欄名，
避免中文變數名稱造成程式碼可讀性問題；未來真實資料串接時，Rails 端 Blueprint 欄位命名可再行決定，
不受本 prototype 前端變數命名約束。）

---

## Error Handling

- 空值欄位（`due_date`、`work_days`、`assigned_to`、`expire_month` 等）一律顯示 `—`，不拋出例外。
- 篩選後無資料：顯示提示文字，不留白、不隱藏欄位標題列。

---

## Testing Strategy（手動驗證）

由於 `docs/` 靜態站不使用建置工具或測試框架，以手動瀏覽器驗證為主：

1. 開啟 `docs/index.html`，確認可見兩個入口連結，點擊後分別正確導向 `project-progress.html`／`issues.html`（需求 1.2）。
2. 開啟 `docs/project-progress.html`，確認與搬移前的 `index.html` 行為完全一致（篩選、摘要列、逾期標示皆正常）（需求 1.3）。
3. 開啟 `docs/issues.html`：
   - 確認 KPI 卡片預設顯示最新月份數值；切換月份下拉選單，確認卡片數值隨之更新（需求 2.2、2.3）。
   - 確認 Top3 排行正確顯示姓名與數量（需求 2.4）。
   - 確認每日趨勢圖正確繪製，滑鼠移到資料點可看到當日數值（需求 3.1、3.3）。
   - 確認 Issue 明細表格顯示全部欄位；切換專案／狀態篩選後清單正確過濾；篩選至無結果時顯示提示文字（需求 4.1〜4.5）。
   - 確認工程師負載表、專案清單表正確顯示（需求 5.1、5.2）。
   - 縮小視窗至手機寬度，確認所有區塊（KPI 卡片、趨勢圖、表格）不破版，表格切換為堆疊卡片版型（需求 6.3，沿用既有 560px 斷點慣例）。
4. 確認整頁繁體中文，無 console 錯誤。
