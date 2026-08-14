# 設計文件

## 概述

新增 `docs/issues.html` + `docs/js/issues.js`，並將既有 `docs/index.html`（305 戰情室本體）搬移為
`docs/project-progress.html` + `docs/js/project-progress.js`（由 `app.js` 更名，內容不變），`docs/index.html`
改為極簡入口頁。全部為純前端 JavaScript，資料來自 `issues.js` 內的模擬資料常數，不呼叫外部 API，
不引入建置工具或圖表框架。

---

## 架構

```
docs/
├── index.html              ← 新：極簡入口頁（連到下方兩頁）
├── project-progress.html   ← 新：既有 index.html 內容原樣搬移（305）
├── issues.html              ← 新：306 臭蟲議題 prototype 頁面
├── css/
│   └── style.css            ← 擴充：入口頁卡片、KPI 卡片、趨勢圖、議題連結樣式
└── js/
    ├── project-progress.js  ← 新：由 app.js 更名搬移（305，內容不變）
    └── issues.js             ← 新：306 模擬資料 + 渲染邏輯
```

### 分頁籤結構（需求 5，`issues.html`）

`<main>` 內以純 CSS（`<input type="radio">` + `<label>` + 相鄰兄弟選擇器 `~`）實作兩個分頁籤，不需
JS：

```html
<div class="tabs">
  <input type="radio" name="issue-tab" id="tab-stats" class="tab-radio" checked>
  <input type="radio" name="issue-tab" id="tab-detail" class="tab-radio">

  <div class="tab-buttons">
    <label for="tab-stats" class="tab-button">統計摘要</label>
    <label for="tab-detail" class="tab-button">議題資料</label>
  </div>

  <div class="tab-panel" id="tab-panel-stats">
    <!-- 月度 KPI（含月份選單、section-note）＋ 每日趨勢（依月份篩選）＋ 依專案分類（依月份篩選） -->
  </div>
  <div class="tab-panel" id="tab-panel-detail">
    <!-- 議題明細（含專案／狀態篩選，不受月份篩選影響） -->
  </div>
</div>
```

（**設計變更紀錄**：「依專案分類」原本歸類在 `tab-panel-detail`；因需求 4a 變更為依月份篩選後，改為
歸類到 `tab-panel-stats`，與月份選單放在一起，`tab-panel-detail` 現僅保留議題明細。）

CSS 以 `#tab-stats:checked ~ #tab-panel-stats { display: block; }`（`.tab-panel` 預設
`display: none`）切換顯示；`#tab-stats:checked ~ .tab-buttons label[for="tab-stats"]` 標示當前分頁籤
的作用中樣式。純 CSS 方案避免引入額外 JS 事件綁定，`issues.js` 既有的 `getElementById` 查找邏輯
不受 DOM 巢狀層級變動影響（ID 不變，只是父層容器改變）。

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
renderStatsTab(yearMonth)         ← 月份切換時的統一入口，依 yearMonth 篩選後分派至下列三者
    ├─ renderKpiCards(monthRecord)                          ← 需求 2
    ├─ renderTrendChart(DAILY_KPI filtered by yearMonth)    ← 需求 3
    └─ renderProjectBreakdown(ISSUES filtered by start_date) ← 需求 2.4a
renderIssueTable(state)           ← 需求 4，篩選變更時重新渲染（不受月份篩選影響）
```

（**設計變更紀錄**：原設計 `renderKpiCards` 與 `renderTrendChart` 各自獨立呼叫、互不相依，且
`renderProjectBreakdown` 對全量 `ISSUES` 運算一次即可；因需求 4a／3a.1 變更為依月份篩選後，改為
統一由 `renderStatsTab(yearMonth)` 依所選月份篩選後的子集分派給三個渲染函式，月份切換時三者一併
重新渲染。）

---

## 元件與介面

### 模擬資料（`docs/js/issues.js`）

依真實 306 試算表分頁欄位結構仿造，資料筆數精簡（每張表 4〜8 筆樣本即可，重點是展示畫面而非資料量）：

```js
var MONTH_KPI = [
  { year_month: "2026-06", complaint: 34, testing: 8, total_bug: 42, block_rate: 19.05, completed: 5, unresolved: 1, avg_days: 1.88, sla_rate: 11.76 },
  { year_month: "2026-07", complaint: 28, testing: 7, total_bug: 35, block_rate: 20.00, completed: 10, unresolved: 7, avg_days: 2.61, sla_rate: 10.71 },
  { year_month: "2026-08", complaint: 15, testing: 9, total_bug: 24, block_rate: 37.50, completed: 6, unresolved: 3, avg_days: 3.10, sla_rate: 25.00 }
];

// type 欄位對應歸屬責任：Complaint（客訴）＝專案共同責任（影響範圍為整個專案），
// TestingBug（測試）＝個人責任（開發階段自行發現），其餘（Other）列為「其他」。
// 負責人（assigned_to）不作為統計分類主軸，「專案」才是本頁面的分類主軸。
var ATTRIBUTION_LABELS = { Complaint: "專案共同責任", TestingBug: "個人責任" };
var ATTRIBUTION_CLASSES = { Complaint: "attribution-shared", TestingBug: "attribution-individual" };

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

var REDMINE_ISSUE_URL_BASE = "https://redmine.amastek.com.tw/issues/";
```

試算表的工程師負載表／專案清單表兩個分頁經評估後不呈現，故無對應模擬資料常數。

`assigned_to` 可能為空字串／`null`（真實資料常見未指派情境），渲染時比照既有 `formatValue()` 慣例
顯示 `—`。`due_date`／`work_days` 亦常為空，同樣處理。

### KPI 摘要卡片與依專案分類統計（需求 2）

- `populateMonthSelect()`：讀取 `MONTH_KPI` 產生月份下拉選單，預設選中陣列最後一筆（最新月份）；
  `change` 事件呼叫 `renderStatsTab(select.value)`（見上方「分頁籤結構」章節的流程圖），而非只更新
  KPI 卡片。
- `renderKpiCards(monthRecord)`：依卡片渲染 8 個統計值，複用既有 `.stat-item` / `.stat-value` /
  `.stat-label` CSS class 命名慣例（沿用 `project-progress` 頁面摘要列風格）。
- `sameMonth(dateStr, yearMonth)`：共用輔助函式，`dateStr.slice(0, 7) === yearMonth`，供每日趨勢與
  依專案分類共同使用，判斷資料是否屬於所選月份。
- `computeProjectBreakdown(monthIssues)`：依已篩選為所選月份子集（`start_date` 落在該月份）的議題
  之 `project` 欄位分組，統計各專案的 `complaint`／`testing`／`other` 筆數與 `total`；
  `renderProjectBreakdown(monthIssues)` 將結果渲染為表格（複用 `buildGenericTable`），取代原本以
  負責人為主軸的 Top3 排行——理由見需求 2.4：客訴問題影響整個專案（全專案成員共同承擔），測試階段
  問題則歸屬個別開發者，兩者性質不同，故以「專案」而非「負責人」作為統計分類主軸；WHEN 篩選後為空
  陣列，顯示「所選月份無議題資料」（需求 2.4a）。
- 排序（需求 2.4b）：`state.breakdownSort = { key: null, dir: -1 }` 記錄目前排序欄位／方向；
  `renderProjectBreakdown` 於計算完 `rows` 後呼叫 `sortBreakdownRows(rows)`（`key` 為 `null` 時原樣
  回傳，維持依專案分組的原始順序）。`buildGenericTable` 擴充為接受選填的 `sortState`／`onSortClick`
  參數：欄位定義加上 `sortable: true` 時，標題渲染為 `<button class="sort-button">`，點擊呼叫
  `toggleBreakdownSort(key)`（同欄位重複點擊反轉方向；切換不同欄位預設 `dir: -1` 即由大到小）並以
  `currentBreakdownMonthIssues`（模組變數，記錄最近一次 `renderProjectBreakdown` 的月份子集）重新
  渲染，不需重新計算 `computeProjectBreakdown`。議題明細清單呼叫 `buildGenericTable` 時不傳入這兩個
  參數，欄位標題維持純文字，不受影響。目前排序中的欄位標題附加 `▲`（升冪）／`▼`（降冪）指示。

### tracker=測試 議題排除（需求 4.6）

- `RAW_ISSUE_ROWS`：模擬 raw_2023~raw_2026 分頁的原始資料（含 `tracker` 為「測試」的樣本列，驗證
  排除邏輯）；`ISSUES = RAW_ISSUE_ROWS.filter(issue => issue.tracker !== "測試")`，載入後立即整批
  過濾，不進入本頁面任何區塊（KPI 摘要、每日趨勢、依專案分類統計、議題明細清單皆讀取過濾後的
  `ISSUES`，不需個別實作排除邏輯）。

### 每日趨勢圖（需求 3）

- `renderTrendChart(records)`：手刻 SVG 折線圖，接收已依所選月份篩選過的 `DAILY_KPI` 子集
  （需求 3.1a）；WHEN `records` 為空陣列，顯示「所選月份無每日趨勢資料」，不繪製空圖。
  - X 軸：日期（依篩選後的 `records` 陣列順序，等距分佈，不需要真實時間比例尺）；每一個資料點都
    渲染一個 `<text>` 標籤（不省略、不限制數量），並以 `transform="rotate(-45 x y)"` 搭配
    `text-anchor="end"` 呈現，避免資料點密集時標籤互相重疊（需求 3.5）。為容納旋轉後的斜向文字，
    `TREND_HEIGHT`（220→250）與底部留白 `TREND_PADDING_BOTTOM`（28→55）皆需增加。
  - Y 軸：`total` 欄位數值，依資料最大值等比例縮放高度。
  - 折線：`<polyline>` 連接各資料點；資料點另加 `<circle>`，`<title>` 子元素顯示瀏覽器原生 tooltip
    （客訴／測試／其他／總計數值），不需額外實作自訂 tooltip 元件或函式庫（需求 3.3）。
  - 不需要處理超大量資料點（單月模擬資料僅數筆），無需虛擬捲動或降採樣。

### Issue 明細清單（需求 4）

- `state.issueFilters = { project: null, status: "新建立" }`（`project: null` = 不篩選／全部；
  `status` 預設「新建立」，聚焦最需要處理的新進議題，非全部狀態，見需求 4.3）。
  `initIssueFilters()` 產生下拉選項後，將 `<select>` 的 `value` 同步設為 `state.issueFilters` 的
  對應值，確保畫面初始狀態與 `state` 一致。
- `initProjectFilter()` / `initStatusFilter()`：讀取 `ISSUES` 內唯一值產生下拉選項，`change` 事件更新
  `state.issueFilters` 並呼叫 `renderIssueTable()`。
- `renderIssueTable(state)`：依 `state.issueFilters` 過濾 `ISSUES`，複用既有 `buildTable`-like 邏輯
  （建立 `<table>`／`<thead>`／`<tbody>`）。
- `ISSUE_COLUMNS` 欄位依序為：`issue_id`（議題編號）、`project`（專案）、`subject`（主旨）、
  `attribution`（歸屬類型）、`status`（狀態）、`assigned_to`（負責人）、`start_date`（開始日期）、
  `due_date`（到期日期）、`work_days`（工作天數）；不顯示 `type`／`tracker` 原始欄位（分類意義已由
  「歸屬類型」徽章呈現，避免重複資訊，見需求 4.1）。
- `buildGenericTable` 的欄位定義支援可選的 `render(value, record)` 函式，該欄位有定義時優先呼叫並將
  回傳的 DOM 節點插入儲存格，取代預設的純文字渲染：
  - 「歸屬類型」欄位依 `type` 對應 `ATTRIBUTION_LABELS`／`ATTRIBUTION_CLASSES`（見「模擬資料」章節）
    渲染彩色徽章（需求 4.1a）。
  - 「議題編號」欄位渲染為 `<a href="{REDMINE_ISSUE_URL_BASE}{issue_id}" target="_blank"
    rel="noopener noreferrer" class="issue-id-link">`，導向 Redmine 議題頁面（需求 4.1b）。
- 篩選後為空集合時顯示「目前無符合條件的議題」（比照既有 `.empty-state` class）。

---

## 資料模型

| 資料集 | 欄位 |
|---|---|
| `MONTH_KPI` | `year_month, complaint, testing, total_bug, block_rate, completed, unresolved, avg_days, sla_rate` |
| `DAILY_KPI` | `date, complaint, testing, other, total` |
| `ISSUES` | `issue_id, subject, type, tracker, status, assigned_to, start_date, due_date, work_days, project`（`attribution` 為渲染時依 `type` 動態計算，非資料欄位；`type`／`tracker` 保留於資料模型供 `attribution` 計算使用，但不作為獨立顯示欄位） |

（欄位命名使用英文 key + 中文顯示標籤，比照 `project-progress.js` 既有慣例，非直接沿用試算表中文欄名，
避免中文變數名稱造成程式碼可讀性問題；未來真實資料串接時，Rails 端 Blueprint 欄位命名可再行決定，
不受本 prototype 前端變數命名約束。）

---

## 錯誤處理

- 空值欄位（`due_date`、`work_days`、`assigned_to`、`expire_month` 等）一律顯示 `—`，不拋出例外。
- 篩選後無資料：顯示提示文字，不留白、不隱藏欄位標題列。

---

## 測試策略（手動驗證）

由於 `docs/` 靜態站不使用建置工具或測試框架，以手動瀏覽器驗證為主：

1. 開啟 `docs/index.html`，確認可見兩個入口連結，點擊後分別正確導向 `project-progress.html`／`issues.html`（需求 1.2）。
2. 開啟 `docs/project-progress.html`，確認與搬移前的 `index.html` 行為完全一致（篩選、摘要列、逾期標示皆正常）（需求 1.3）。
3. 開啟 `docs/issues.html`：
   - 確認頁面載入時預設顯示「統計摘要」分頁籤；點擊「議題資料」分頁籤可切換顯示，不觸發頁面重新
     載入（需求 5.1、5.3、5.4）；確認月份選單位於「統計摘要」分頁籤內，專案／狀態選單位於
     「議題資料」分頁籤內（需求 5.2）。
   - 確認 KPI 卡片預設顯示最新月份數值；切換月份下拉選單，確認卡片數值隨之更新（需求 2.2、2.3）。
   - 確認「依專案分類」統計表正確顯示各專案的客訴／測試／其他數量與總計（需求 2.4）。
   - 確認每日趨勢圖正確繪製，滑鼠移到資料點可看到當日數值（需求 3.1、3.3）。
   - 確認 Issue 明細表格欄位依序為議題編號／專案／主旨／歸屬類型／狀態／負責人／開始日期／到期日期／
     工作天數（不含 type／tracker），「歸屬類型」徽章正確（Complaint→專案共同責任、TestingBug→
     個人責任、其餘→其他）；「議題編號」為可點擊連結，導向
     `https://redmine.amastek.com.tw/issues/{issue_id}`，以新分頁開啟；確認頁面載入時預設專案為
     「全部專案」、狀態預設為「新建立」（非全部狀態）；切換專案／狀態篩選後清單正確過濾；篩選至無
     結果時顯示提示文字（需求 4.1、4.1a、4.1b、4.2、4.3、4.4、4.5）。
   - 縮小視窗至手機寬度，確認所有區塊（KPI 卡片、趨勢圖、表格）不破版，表格切換為堆疊卡片版型（需求 6.3，沿用既有 560px 斷點慣例；分頁籤結構新增後之驗證見 Task 15）。
4. 確認整頁繁體中文，無 console 錯誤。
