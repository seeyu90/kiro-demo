# 設計文件

## 概述

新增一個完全獨立的頁面 `docs/project-phase-tracking.html`，搭配
`docs/js/project-phase-tracking-data.js`（模擬資料）與 `docs/js/project-phase-tracking.js`（渲染
邏輯）。既有 `docs/project-history-overview.html` 及其 JS **完全不修改**，僅 `docs/index.html` 新增
一張卡片連結、`docs/css/style.css` 擴充新增樣式規則（並重用既有 `.project-card` / `.status-badge` /
`.view-toggle-btn` / `.gantt-*` / `.empty-state` 等既有 class，避免重複造輪子，同時維持視覺一致性）。

全部為純前端 JavaScript，資料來自模擬資料常數，不呼叫外部 API，不引入建置工具或圖表框架。

---

## 架構

```
docs/
├── index.html                          ← 修改：新增「專案階段追蹤」卡片連結
├── project-history-overview.html       ← 不動
├── project-phase-tracking.html         ← 新：總覽篩選/排序 + 專案卡片（展開顯示階段表/甘特圖）
├── css/
│   └── style.css                       ← 擴充：新頁面專屬樣式（階段表格、差異高亮）
└── js/
    ├── project-phase-tracking-data.js  ← 新：模擬資料（PROJECT_PROFILES, PHASE_RECORDS, STAGE_ORDER）
    └── project-phase-tracking.js       ← 新：篩選/排序/渲染邏輯
```

---

## 元件與介面

### Prototype Data Contract

以下為模擬資料的**權威字面範例**，實作時 SHALL 直接依此欄位、型別、`null`／空字串慣例撰寫，不另行
設計資料形狀（避免實作者自行腦補）：

```js
// 固定順序的 5 個交付階段（見 requirements.md 待確認事項 3，prototype 明確規則，非動態推導）
var STAGE_ORDER = ["需求確認", "開案", "開發", "測試", "發布"];

// 專案基本資料：project_name, customer(客戶), pm(PM), status(專案狀態),
// planned_completion_date(專案層級預計完成日期)。真實來源待確認（見待確認事項 2），
// 本階段先仿照既有 300_員工專案 roster 的角色，用獨立模擬資料表示。
var PROJECT_PROFILES = [
  { project_name: "電商平台改版", customer: "台灣零售股份有限公司", pm: "王小明",
    status: "開發中", planned_completion_date: "2026-05-31" },
  { project_name: "內控調整2510", customer: "舊振南", pm: "呂俐禎",
    status: "已發布", planned_completion_date: "2025-12-15" }
  // ...其餘專案
];

// 階段紀錄：對齊未來 Notion 階段紀錄 database 欄位（日期→planned_date、實際完成→actual_date、
// 專案→project、類型→stage、狀態→status、原因→reason）。
//
// 【關鍵慣例，不得偏離】
// - project：純字串，值等於對應 PROJECT_PROFILES 的 project_name，用來模擬 Notion relation。
//   Prototype 階段不建立 Notion page ID 或 { id, name } 物件結構；real-source spec 接上真實 API 後
//   可能改為 project: { id: "<notion-page-id>", name: "..." }，屆時需同步調整本檔案與渲染邏輯。
// - actual_date：尚未完成一律為 null，禁止使用空字串 ""。
// - status：對齊 Notion「狀態」欄位原始文字。本檔案的模擬資料遵循「actual_date 為 null 時 status
//   也一律為 null，不發明『進行中』『未開始』等真實資料未觀察到的狀態值」這條 prototype-only 慣例
//   （真實 Notion 目前只觀察到「完成」一種狀態），但這只是本檔案撰寫模擬資料的約定，並非對未來
//   真實 Notion 資料的假設——real-source spec 接上真實 API 後，status 與 actual_date 的搭配可能
//   不遵循此規則。畫面上的「已完成／未完成／—」顯示邏輯一律由 planned_date／actual_date 是否存在
//   衍生（見需求 4.5 對照表），完全不讀 status 欄位，因此不受此慣例是否成立影響。
// - 每個專案固定建立 STAGE_ORDER 全部 5 筆（含尚未發生的階段），不得省略。
var PHASE_RECORDS = [
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

  { project: "內控調整2510", stage: "需求確認", planned_date: "2025-10-25",
    actual_date: "2025-10-28", status: "完成", reason: "" },
  { project: "內控調整2510", stage: "開案", planned_date: "2025-10-28",
    actual_date: "2025-10-28", status: "完成", reason: "" },
  { project: "內控調整2510", stage: "開發", planned_date: "2025-11-04",
    actual_date: "2025-11-07", status: "完成", reason: "" },
  { project: "內控調整2510", stage: "測試", planned_date: "2025-11-11",
    actual_date: "2025-11-13", status: "完成", reason: "" },
  { project: "內控調整2510", stage: "發布", planned_date: "2025-11-13",
    actual_date: "2025-12-15", status: "完成", reason: "與內控調整2511一起發布" }
  // ...其餘專案，皆固定 5 筆
];
```

資料筆數精簡（3〜4 個專案即可），但至少涵蓋：一個「進行中、部分階段未完成」的專案（如上例電商平台
改版，用以驗證需求 4.3、4.5 的未完成顯示）、一個「全部完成、含 reason 備註延遲發布」的專案（如上例
內控調整2510，直接對齊使用者提供的真實 Notion 截圖範例）、以及一個「至少一階段提前完成（實際早於
預計）」的專案（用以驗證需求 3.3、4.8 的提前完成樣式），並至少一個「完全沒有 PHASE_RECORDS」的專案
（驗證需求 4.6 的空值容錯，對照表顯示「—」而非「未完成」）。

### 總覽頁（`project-phase-tracking.js`）

- `state = { filters: { customer: null, status: null, pm: null }, sort: null, viewMode: "list",
  editedActualDates: {} }`。`editedActualDates` 是使用者互動編輯「實際完成日期」欄位後的暫存值，
  key 為 `` `${project_name}::${stage}` ``、value 為使用者輸入的日期字串或 `null`；**與
  `PHASE_RECORDS` 完全分離**，`PHASE_RECORDS` 陣列中的物件不得被直接改寫（需求 4.9）。
- `initFilters()`：讀取 `PROJECT_PROFILES` 唯一 `customer`／`status`／`pm` 值產生下拉選項（需求 2.1）。
- `applyFilters(profiles)`：依 `state.filters` 三者交集篩選（需求 2.2）。
- `applySort(profiles)`：依 `state.sort`（`null` / `"planned_date"` / `"status"` / `"customer"`）
  排序，規則對照需求 2.3 的表格；`null` 時維持原陣列順序。使用 `Array.prototype.slice().sort(...)`
  （現代瀏覽器 `Array.sort` 為穩定排序，鍵值相同時自動維持原始相對順序，滿足需求 2.4，不需額外
  index 比較）。
- `renderProjectCards(profiles)`：卡片式清單，複用既有 `.project-card` / `.project-card-summary` /
  `.status-badge` 樣式慣例（需求 4.1）；每張卡片展開後呼叫 `renderStageTable(projectName)`。
- `buildStageRows(projectName)`：依 `STAGE_ORDER` 逐一在 `PHASE_RECORDS` 中以
  `record.project === projectName && record.stage === stage` 找出對應紀錄；**找不到紀錄時**（需求
  4.6，例如專案完全沒有 `PHASE_RECORDS`）仍建立一列，`planned_date`／`actual_date`／`status` 皆視為
  `null`。**若 `state.editedActualDates` 中存在該 `` `${projectName}::${stage}` `` key**，其值覆寫
  該列的 `actual_date`（不覆寫 `PHASE_RECORDS` 本身，見需求 4.9）。回傳固定 5 筆陣列（每個 `stage`
  恰一筆，順序即 `STAGE_ORDER`）供 `renderStageTable`／`renderGanttChart` 共用渲染。
- `parseDateOnly(dateStr)`：將 `"YYYY-MM-DD"` 字串拆解年/月/日後以 `Date.UTC(y, m - 1, d)` 建構為
  UTC 毫秒數，避免直接 `new Date(dateStr)` 受瀏覽器時區影響（需求 4.4）。`dateStr` 為 `null`／缺失／
  格式不合法時回傳 `null`。
- `diffDays(actualDate, plannedDate)`：`parseDateOnly(actualDate)` 或 `parseDateOnly(plannedDate)`
  任一為 `null` 皆回傳 `null`；否則回傳
  `Math.round((parseDateOnly(actualDate) - parseDateOnly(plannedDate)) / 86400000)`（可為負值，需求
  4.4）。
- `computeRowState(plannedDate, actualDate)`：依 `plannedDate`／`actualDate` 兩欄位是否存在的四種
  組合，實作需求 4.5 的對照表，回傳 `{ completionLabel, diffDays }`（並非一個獨立的狀態 enum，純粹
  是這兩個既有欄位的組合判斷）：
  ```js
  function computeRowState(plannedDate, actualDate) {
    var hasPlanned = parseDateOnly(plannedDate) !== null;
    if (actualDate !== null) {
      return { completionLabel: "已完成", diffDays: hasPlanned ? diffDays(actualDate, plannedDate) : null };
    }
    return { completionLabel: hasPlanned ? "未完成" : "—", diffDays: null };
  }
  ```
  這是清單檢視（`renderStageTable`）與甘特圖檢視（`renderGanttChart`）**共用**的唯一狀態判斷函式，
  確保兩種檢視的完成狀態／差異呈現一致，且不讀取 `status` 欄位（需求 4.5）。**`renderStageTable`／
  `renderGanttChart` 皆不得各自重新實作完成狀態或差異的判斷邏輯**（例如各自寫一份
  `if (actual_date) {...}` 分支）——兩者一律呼叫 `computeRowState`，避免日後修改規則時兩處各改一半、
  逐漸不一致。
- `renderStageTable(projectName)`：呼叫 `buildStageRows`，逐列渲染：階段名稱、
  `parseDateOnly(plannedDate) !== null ? plannedDate : "—"`（**不可簡寫成 `plannedDate || "—"`**，
  因為那只擋得住 `null`／`""`／`undefined`，擋不住 `"2026/08/20"`、`"2026-99-99"` 等格式不合法但
  truthy 的字串——需求 4.6、4.7 要求的是「格式不合法」也要顯示「—」，必須透過 `parseDateOnly` 驗證）、
  `<input type="date" value={parseDateOnly(actualDate) !== null ? actualDate : ""}>`（同理，`value`
  也需經 `parseDateOnly` 驗證合法才寫入，不可簡寫成 `actual_date || ""`；`actual_date` 為 `null` 或
  格式不合法皆對應 input 空值，僅 UI 層轉譯，資料本身仍為原值，不違反需求 4.3 的 `null`-only 慣例）、
  差異與完成狀態標示（皆來自 `computeRowState`，需求 4.5）、`reason`（非空字串時於該列顯示備註文字，
  例如內控調整2510「發布」列的「與內控調整2511一起發布」；為空字串時不顯示備註區塊，見「錯誤處理」）。
  `<input type="date">` 綁定 `change` 事件：**寫入
  `state.editedActualDates["${projectName}::${stage}"] = input.value || null`**（不得寫入
  `record.actual_date` 或以任何方式修改 `PHASE_RECORDS` 陣列中的物件），再重新呼叫
  `buildStageRows`／`computeRowState` 重算並更新該列顯示（需求 4.9）。差異為正套用 `.diff-delayed`
  （紅色，比照既有 `.gantt-task-actual-delayed` 色系）、為負套用 `.diff-early`（綠色，新增 class，
  與需求 3.3、4.8 甘特圖提前完成樣式呼應）、為 0 或 `null`（含「—」）則不套用高亮 class（需求 4.8）。
- `todayUtcMs()`：`var now = new Date(); return Date.UTC(now.getFullYear(), now.getMonth(),
  now.getDate());`——一律讀取執行當下瀏覽器當地日期，不得寫死固定日期字串（需求 3.4）。
- `state.viewMode`：`<button>` 切換並呼叫對應渲染函式，比照既有 `.view-toggle-btn` 慣例（需求
  3.1、3.2）。
- `renderGanttChart(profiles)`：手刻 SVG，每個專案一列，每列依 `STAGE_ORDER` **最多**呈現 5 個色塊
  （`planned_date` 缺失或格式不合法的階段不繪製色塊，但該階段的 `buildStageRows`／`computeRowState`
  資料邏輯仍照常執行——只是甘特圖跳過繪製，不代表該階段「不存在」，清單檢視仍會顯示該階段列的
  「—"）。使用與 `renderStageTable` 相同的 `buildStageRows`／`computeRowState` 結果，確保清單／
  甘特圖兩種檢視資料一致。每個色塊一律以 `planned_date` 為左端點（X 軸基準），依需求 3.3 規則決定
  右端點與樣式：
  - `actual_date !== null` 且 `diffDays >= 0`（延遲或準時）：右端點＝`actual_date`（真實日期區間），
    套用 `.gantt-task-actual-delayed` 色系。
  - `actual_date !== null` 且 `diffDays < 0`（提前完成）：**不畫「預計→實際」的真實日期區間**（那會
    產生右端點小於左端點的反向色塊），色塊寬度改為 `|diffDays|` 對應的等比例寬度，從 `planned_date`
    往右延伸，套用新增的 `.gantt-task-actual-early`（與 `renderStageTable` 的 `.diff-early` 同色系）。
    此色塊語意是「提前幅度」的視覺標記，**不代表**該階段的實際完成日期落在此區間內；程式碼註解需
    載明此點，避免被後續維護者誤判為繪圖邏輯錯誤。
  - `actual_date === null` 且 `planned_date` 存在（未完成）：右端點＝`todayUtcMs()`，套用既有
    `.gantt-task-planned` 色系。
  - `planned_date` 缺失或格式不合法：無法定位左端點，該階段**不繪製色塊**（該列在清單檢視仍依
    `computeRowState` 顯示「—」）。

  **X 軸範圍與 SVG 寬度計算規則**（避免留給實作者自行決定 `pixelsPerDay`／`maxDate` 演算法）：
  - `minDateMs` = 全體專案、全體階段中，所有有效（`parseDateOnly` 非 `null`）`planned_date` 的最小值。
  - `maxDateMs` = 下列三者取最大值：全體有效 `actual_date` 的最大值、`todayUtcMs()`（涵蓋仍在
    進行中的階段延伸到今日）、`minDateMs`（避免無任何 `actual_date` 時 `maxDateMs` 小於
    `minDateMs`）。
  - IF 全體資料中找不到任何有效 `planned_date`（`minDateMs` 無法計算），THEN 不繪製甘特圖 SVG，改
    顯示既有 `.empty-state` 提示文字（例如「目前無可繪製的甘特圖資料」），不得渲染空白或報錯的 SVG。
  - `pixelsPerDay`：固定常數（例如 `24`），`computedWidth = (maxDateMs - minDateMs) / 86400000 *
    pixelsPerDay + leftPadding + rightPadding`（`leftPadding`／`rightPadding` 沿用既有 `.gantt-svg`
    版面慣例）。
  - `svgWidth = Math.max(computedWidth, 900)`，確保時間範圍很短時色塊不會過度擁擠，超出容器寬度時
    交由既有 `.gantt-scroll` 水平捲動呈現，不使頁面整體出現水平捲動軸（需求 3.5）。

  複用既有 `.gantt-scroll` / `.gantt-svg` / `.gantt-month-gridline` / `.gantt-today-line` 等 class
  與繪製手法。

---

## 資料模型

| 資料集 | 欄位 |
|---|---|
| `PROJECT_PROFILES` | `project_name, customer, pm, status, planned_completion_date` |
| `PHASE_RECORDS` | `project, stage, planned_date, actual_date, status, reason` |
| `STAGE_ORDER` | `["需求確認", "開案", "開發", "測試", "發布"]`（常數陣列） |

完整字面範例與欄位慣例（`null` vs `""` 規則、`project` 純字串規則等）見上方「Prototype Data
Contract」，此處不重複。欄位命名對齊簡介所述真實 Notion 欄位（`日期→planned_date`、
`實際完成→actual_date`、`專案→project`、`類型→stage`、`狀態→status`、`原因→reason`），確保之後
real-source spec 串接真實 Notion API 時，前端資料結構不需大改。`PROJECT_PROFILES` 的欄位來源仍為
待確認事項 2，屆時可能需要調整 join 方式；`PHASE_RECORDS.project` 屆時可能從純字串改為
`{ id, name }` 物件（見 Data Contract 註解），需同步調整 `buildStageRows` 的比對邏輯。

---

## 錯誤處理

- `actual_date` 為 `null`、`planned_date` 存在：「實際完成日期」欄位顯示空白 date input，`computeRowState`
  回傳完成狀態標示「未完成」、差異「—」，不拋出例外（需求 4.3、4.5）。**`null` 與空字串 `""` 不得
  混用**——模擬資料一律用 `null` 表示未完成，UI 層才轉譯為空白 input value（見 Data Contract）。
- `planned_date`、`actual_date` 皆缺失（含某專案完全沒有 `PHASE_RECORDS` 的情況）：`computeRowState`
  回傳完成狀態標示「—」，**不得顯示「未完成」**（無法判斷是否已排程）；`buildStageRows` 仍回傳固定
  5 筆，階段表正常顯示 5 列，不省略列、不讓卡片渲染失敗（需求 4.5、4.6）。
- 單筆 `planned_date` 缺失或格式不合法但 `actual_date` 存在：`parseDateOnly` 回傳 `null`，
  `computeRowState` 回傳完成狀態標示「已完成」、差異「—」，不拋出例外、不影響其他列／其他專案卡片
  渲染（需求 4.5、4.7）。
- 日期差異計算一律透過 `parseDateOnly`／`Date.UTC` 進行，不直接用 `new Date(dateStr)` 相減，避免
  時區偏移誤差（需求 4.4）。
- 使用者編輯「實際完成日期」input 僅寫入 `state.editedActualDates`，`PHASE_RECORDS` 物件本身不變；
  重新整理頁面後 `state` 重置，編輯值自動消失（需求 4.9）。
- 篩選後無資料：顯示「目前無符合條件的專案」提示文字，不留白、不隱藏欄位標題列（需求 2.5）。
- `reason` 為空字串時不額外顯示備註區塊（沿用既有「空值一律不強行渲染」慣例）。

---

## 待確認事項對本設計的影響

requirements.md 列出的 4 項待確認事項，本設計已針對 prototype 自身行為訂出明確規則（見上方 Data
Contract 與需求 3.3、4.3、4.5 的邏輯），不再有 prototype 層級的歧義；僅「真實資料的實際來源」尚待
後續 real-source spec 確認 Notion API 後可能需要調整：
- `PHASE_RECORDS` 是否每個階段一開始就有 `planned_date`，或需改為動態排程計算（待確認事項 1；
  prototype 固定規則為每專案 5 筆皆存在，不受影響）。
- `PROJECT_PROFILES` 的真實來源 database 與 join 方式（待確認事項 2）。
- `STAGE_ORDER` 是否需要新增/調整合法值（待確認事項 3；prototype 固定使用 5 階段常數）。
- 是否需要另外納入工時欄位與比較圖表（待確認事項 4，本階段不處理）。

---

## 測試策略（手動驗證）

由於 `docs/` 靜態站不使用建置工具或測試框架，以手動瀏覽器驗證為主：

1. 開啟 `docs/index.html`，確認新增「專案階段追蹤」卡片可正確導向 `project-phase-tracking.html`；
   既有卡片行為不變（需求 1.1、1.2）。
2. 開啟 `docs/project-phase-tracking.html`：
   - 確認客戶／狀態／PM 三個篩選下拉選單各自可正確篩選專案清單，同時選取多個條件時取交集（需求
     2.1、2.2）；排序下拉選單依「不排序／依預計完成日期／依狀態／依客戶」正確排序（依預計完成日期
     排序時確認用的是 `PROJECT_PROFILES.planned_completion_date`，而非任何階段的
     `PHASE_RECORDS[].planned_date`），鍵值相同的專案不因排序而跳動順序（需求 2.3、2.4）；篩選至
     無結果時顯示提示文字（需求 2.5）。
   - 確認清單／甘特圖切換正常運作，不觸發頁面重新載入；預設顯示清單檢視（需求 3.1、3.2）。
   - 確認甘特圖每個色塊左端點皆對齊「預計完成日期」；已完成延遲階段色塊延伸至實際完成日期（延遲
     樣式）、提前完成階段以另一種樣式呈現（色塊寬度＝提前天數，代表「提前幅度」的視覺標記，非真實
     日期區間）且不畫成反方向色塊、未完成階段延伸至今日（今日隨瀏覽器當地日期變動，非寫死字串）
     （需求 3.3、3.4）；縮小視窗寬度或於時間範圍很短的模擬資料下確認 SVG 維持至少 900px 寬度並可
     水平捲動，頁面整體不出現水平捲動軸（需求 3.5）。
   - 展開任一專案卡片，確認顯示固定 5 列階段表；找不到對應階段紀錄或無任何 `PHASE_RECORDS` 的
     專案，5 列完成狀態標示皆顯示「—」而非「未完成」（需求 4.1、4.3、4.6）；有 `planned_date` 但
     `actual_date` 為 `null` 的階段顯示空白 input、差異「—」、完成狀態標示「未完成」（需求 4.3、
     4.5）；`planned_date` 缺失/不合法但 `actual_date` 存在的階段列顯示完成狀態標示「已完成」、
     差異「—」，且不中斷渲染（需求 4.5、4.7）。
   - 修改某列「實際完成日期」input 為「晚於」「等於」「早於」預計完成日期三種情境，確認差異分別
     顯示正值（紅色）、`0`（一般樣式）、負值（另一種可辨識樣式，例如綠色），且完成狀態標示即時
     更新為「已完成」（需求 4.8、4.9、4.5）；於瀏覽器 DevTools console 檢查
     `PHASE_RECORDS`（或對應變數）中的原始物件未被此編輯動作改寫，僅 `state.editedActualDates`
     有新增內容（需求 4.9）；重新整理頁面確認所有編輯值消失、卡片恢復模擬資料原始值（不納入範圍）。
   - 【加強驗證，非主要驗收步驟】於 DevTools console 直接呼叫 `diffDays("2026-08-12", "2026-08-10")`
     應得 `2`、`diffDays("2026-08-08", "2026-08-10")` 應得 `-2`，確認計算邏輯正確；有餘力時可再將
     瀏覽器/系統時區切換為非 UTC+8（例如 UTC-7）重新整理頁面，確認上述計算結果不受影響（需求 4.4）。
3. 縮小視窗至手機寬度，確認頁面所有區塊不破版（需求 5.3）；確認深色/淺色主題切換正常（需求 5.4）。
4. 確認整頁繁體中文，無 console 錯誤。
