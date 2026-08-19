# 實作計畫：專案階段追蹤靜態 Prototype

## 概述

新增完全獨立的 `docs/project-phase-tracking.html`，搭配 `docs/js/project-phase-tracking-data.js`
（模擬資料）與 `docs/js/project-phase-tracking.js`（篩選/排序/渲染邏輯）。純前端新增，不修改既有
`docs/project-history-overview.html` 或其對應 JS，僅 `docs/index.html`／`docs/css/style.css` 擴充。
所有欄位、`null`／空字串慣例、日期計算方式、甘特圖錨點方向、排序規則、完成狀態對照表，皆已在
[requirements.md](requirements.md)／[design.md](design.md) 中訂為明確規則，實作時直接依循，不另行
設計。

**狀態**：已完成實作並以 Playwright E2E 驗證通過（本機 headless Chromium，經由 Bash 執行，透過
`python3 -m http.server` 起本機靜態伺服器；互動式 MCP 瀏覽器工具因沙盒網域限制無法連線本機伺服器）。
涵蓋：入口頁卡片、篩選交集／排序（含依 `PROJECT_PROFILES.planned_completion_date` 排序、穩定排序
tie-break，以排序後兩個同客戶專案的相對順序驗證，見任務 6）、清單／甘特圖切換、4 種資料情境（部分
未完成／全部完成＋`reason` 備註／至少一階段提前完成／完全無 `PHASE_RECORDS` 顯示「—」而非「未完成」）、
互動編輯 `+7` 差異重算並跨清單／甘特圖檢視共用、甘特圖 empty-state（篩選至僅剩無有效 `planned_date`
的專案時）、篩選至無結果的 empty-state、全程無 console／pageerror。並附截圖確認實際畫面。

**實作與 tasks.md 的一處差異**：CSS 部分（任務 9.1）發現既有 `.delay-positive`／`.delay-negative`
class（`docs/css/style.css`）與規劃中要新增的 `.diff-delayed`／`.diff-early` 語意完全相同，故直接
沿用既有 class，未另外新增；僅新增 `.gantt-task-actual-early`（既有 `.gantt-task-actual-ontime`
語意是「消耗人時比例填色」track，與此處「提前完成單一實心色塊」不同，故獨立成一個 class）與
`.phase-reason`／`.phase-reason-row`（既有樣式無對應可重用）。

**副產品發現（未在本 spec 範圍內修正）**：測試手機版（375px）時發現既有 `.control-group`
class（篩選列共用樣式，`docs/project-history-overview.html` 也在用）在窄螢幕未換行，導致整頁出現
水平捲動軸（既有頁面 353px、本頁 277px，本頁的甘特圖 `.gantt-scroll` 本身未貢獻額外溢出，已驗證
甘特圖切換前後溢出量相同）。這是既有共用樣式的既存問題，非本 spec 引入，依「不修改既有頁面／既有
規則」原則不在此修正，已另開背景任務追蹤。

---

## 任務

- [x] 1. 模擬資料
  - [x] 1.1 新增 `docs/js/project-phase-tracking-data.js`，依 [design.md](design.md)「Prototype
        Data Contract」章節建立 `STAGE_ORDER`／`PROJECT_PROFILES`／`PHASE_RECORDS` 常數。
        `PHASE_RECORDS` 每個專案固定 5 筆（`STAGE_ORDER` 各一筆），未完成階段 `actual_date`／
        `status` 為 `null`（禁止空字串）。資料需涵蓋：一個「部分階段未完成」專案（如電商平台改版
        範例）、一個「全部完成＋`reason` 備註延遲發布」專案（如內控調整2510，對齊使用者提供的真實
        Notion 截圖）、一個「至少一階段提前完成（`actual_date` 早於 `planned_date`）」專案、一個
        「完全沒有 `PHASE_RECORDS`」的專案
    - _需求：4.3, 4.6, 5.1_

- [x] 2. 入口頁新增連結
  - [x] 2.1 `docs/index.html` 新增「專案階段追蹤」卡片，導向 `project-phase-tracking.html`；不變更
        既有卡片內容與行為
    - _需求：1.1, 1.2, 1.3_

- [x] 3. 日期與狀態計算共用邏輯
  - [x] 3.1 `docs/js/project-phase-tracking.js`：實作 `parseDateOnly(dateStr)`（拆解
        `"YYYY-MM-DD"` 年/月/日以 `Date.UTC` 建構，避免時區偏移；格式不合法或缺失回傳 `null`）、
        `diffDays(actualDate, plannedDate)`、`todayUtcMs()`（讀取 `new Date()`，不得寫死日期字串）
    - _需求：3.4, 4.4_
  - [x] 3.2 實作 `computeRowState(plannedDate, actualDate)`：依 `plannedDate`／`actualDate` 兩欄位
        是否存在（`parseDateOnly` 驗證通過視為存在）的組合判斷（並非獨立的狀態 enum），回傳
        `{ completionLabel, diffDays }`。規則：`actualDate` 存在 →「已完成」（`diffDays` 僅於
        `plannedDate` 也存在時計算，否則 `null`）；`plannedDate` 存在且 `actualDate` 不存在 →
        「未完成」（`diffDays` 為 `null`）；兩者皆不存在 →「—」（`diffDays` 為 `null`）
    - _需求：4.5_
  - [x] 3.3 **不變式**：`renderStageTable`（任務 5）與 `renderGanttChart`（任務 7）皆不得各自重新
        實作完成狀態或差異的判斷邏輯（例如各自寫一份 `if (actual_date) {...}` 分支）——兩者一律呼叫
        `computeRowState()` 取得結果，避免日後修改規則時兩處分別修改、逐漸不一致
    - _需求：4.5_

- [x] 4. 總覽頁 — 篩選與排序
  - [x] 4.1 建立 `docs/project-phase-tracking.html` 頁面骨架：篩選列（客戶／狀態／PM 下拉＋排序
        下拉）、清單／甘特圖切換按鈕、卡片容器、返回入口頁連結
    - _需求：1.3, 2.1, 3.1_
  - [x] 4.2 實作 `initFilters()`（客戶／狀態／PM 唯一值產生下拉選項）、`applyFilters(profiles)`
        （三者交集）、`applySort(profiles)`（依需求 2.3 表格：不排序／依
        `PROJECT_PROFILES.planned_completion_date`／依 `status`／依 `customer`，皆用穩定排序）
    - _需求：2.1, 2.2, 2.3, 2.4, 2.5_

- [x] 5. 總覽頁 — 專案卡片與階段追蹤表（清單檢視）
  - [x] 5.1 實作 `buildStageRows(projectName)`：依 `STAGE_ORDER` 從 `PHASE_RECORDS` 找對應紀錄
        （`project`＋`stage` 比對），找不到時回傳 `planned_date`／`actual_date`／`status` 皆為
        `null` 的列；若 `state.editedActualDates` 有對應 `` `${projectName}::${stage}` `` key，
        覆寫該列 `actual_date`（不得修改 `PHASE_RECORDS` 陣列本身）
    - _需求：4.3, 4.6, 4.9_
  - [x] 5.2 實作 `renderProjectCards(profiles)`（複用既有 `.project-card`／`.project-card-summary`／
        `.status-badge` 樣式，卡片標頭顯示專案名稱／客戶／PM／狀態／專案層級預計完成日期）與
        `renderStageTable(projectName)`（呼叫 `buildStageRows`＋`computeRowState` 渲染固定 5 列）：
        - 「預計完成日期」欄位：`parseDateOnly(planned_date) !== null ? planned_date : "—"`（**不得
          簡寫成 `planned_date || "—"`**——那只擋得住 `null`／`""`／`undefined`，擋不住
          `"2026/08/20"`、`"2026-99-99"` 等格式不合法但 truthy 的字串，需經 `parseDateOnly` 驗證）
        - `<input type="date">` 的 `value`：`parseDateOnly(actual_date) !== null ? actual_date :
          ""`（同理不得簡寫成 `actual_date || ""`）
        - 差異、完成狀態標示：來自 `computeRowState`；差異正值套用既有 `.delay-positive`
          （紅，非新增 `.diff-delayed`——語意與既有 class 完全相同，見上方「實作差異」）、負值套用
          既有 `.delay-negative`（綠）
        - `reason` 非空字串時於該階段列顯示備註文字（例如內控調整2510「發布」列的「與內控調整2511
          一起發布」）；為空字串時不顯示備註區塊
    - _需求：4.1, 4.2, 4.3, 4.5, 4.6, 4.7, 4.8_
  - [x] 5.3 `<input type="date">` 綁定 `change` 事件：寫入
        `state.editedActualDates["${projectName}::${stage}"] = input.value || null`，重新呼叫
        `buildStageRows`／`computeRowState` 更新該列差異與完成狀態標示；確認未寫入 `PHASE_RECORDS`
    - _需求：4.9_

- [x] 6. 檢查點 — 總覽頁清單檢視功能驗證
  - 依 [design.md](design.md)「測試策略」清單檢視相關項目驗證：篩選交集／排序（含穩定排序、依
    `PROJECT_PROFILES.planned_completion_date` 而非階段層級日期）／空結果提示／卡片展開固定 5 列／
    無 `PHASE_RECORDS` 專案顯示「—」而非「未完成」／`planned_date` 缺失容錯（含格式不合法字串，非
    僅 `null`）／`reason` 非空時正確顯示備註、為空字串時不顯示
  - **`editedActualDates` 跨檢視共用驗證**（驗證它是清單／甘特圖真正共用的 UI state，而非只是「input
    有反應」）：編輯「內控調整2510／發布」列的實際完成日期 → 確認 `state.editedActualDates` 出現
    對應 key、原始 `PHASE_RECORDS` 物件的值不變 → 切換到甘特圖檢視 → 確認該色塊反映編輯後的日期 →
    切回清單檢視 → 確認階段列仍反映編輯後的日期（而非退回原始值）→ 重新整理頁面 → 確認兩種檢視皆
    恢復為模擬資料原始值

- [x] 7. 總覽頁 — 甘特圖檢視
  - [x] 7.1 實作 `renderGanttChart(profiles)`：手刻 SVG，每專案一列，依 `STAGE_ORDER` **最多**呈現
        5 個色塊（並非固定 5 個——`planned_date` 缺失或格式不合法的階段仍照常跑
        `buildStageRows`／`computeRowState`，只是不繪製色塊，不代表該階段被移除）：
        - 色塊左端點固定為 `planned_date`；已完成延遲／準時（`diffDays >= 0`）延伸至 `actual_date`；
          提前完成（`diffDays < 0`）**不畫真實日期區間**，改以 `|diffDays|` 等比例寬度呈現「提前
          幅度」視覺標記（套用新增的 `.gantt-task-actual-early`，避免與延遲同色）；未完成（`actual_date`
          為 `null` 但 `planned_date` 存在）延伸至 `todayUtcMs()`；`planned_date` 缺失或格式不合法
          時該階段不繪製色塊
        - X 軸範圍：`minDateMs` = 全體專案全體階段中所有有效 `planned_date` 的最小值；`maxDateMs` =
          （全體有效 `actual_date` 最大值、`todayUtcMs()`、`minDateMs`）三者取最大值；找不到任何
          有效 `planned_date` 時不繪製 SVG，改顯示既有 `.empty-state` 提示文字
        - SVG 寬度：`computedWidth = (maxDateMs - minDateMs) / 86400000 * pixelsPerDay + leftPadding
          + rightPadding`（`pixelsPerDay` 取固定常數，例如 `24`），`svgWidth = Math.max(computedWidth,
          900)`
        - 複用既有 `.gantt-scroll`／`.gantt-svg`／`.gantt-month-gridline`／`.gantt-today-line`
    - _需求：3.3, 3.5_
  - [x] 7.2 實作檢視模式切換（`state.viewMode` + 按鈕事件，複用既有 `.view-toggle-btn` 慣例，切換
        不重新載入頁面）
    - _需求：3.1, 3.2_

- [x] 8. 檢查點 — 甘特圖檢視功能驗證
  - 依 design.md 測試策略甘特圖相關項目驗證：色塊錨點與方向（延遲／提前／未完成三種樣式，提前完成
    色塊不得畫成反方向）／`planned_date` 缺失或不合法的階段正確跳過繪製、不影響同列其他階段或其他
    專案／SVG 最小寬度 900px 與水平捲動（含時間範圍很短時仍維持最小寬度、頁面整體不出現水平捲動軸）／
    今日日期讀自 `new Date()`，不寫死字串／全體資料皆無有效 `planned_date` 時顯示 `.empty-state`
    而非空白或報錯的 SVG

- [x] 9. 樣式與響應式設計
  - [x] 9.1 `docs/css/style.css` 新增本頁專屬樣式規則：`.gantt-task-actual-early`／`.phase-reason`／
        `.phase-reason-row`（差異高亮直接沿用既有 `.delay-positive`／`.delay-negative`，未新增
        `.diff-delayed`／`.diff-early`，見上方「實作差異」），沿用既有 768px／560px 斷點與
        `.project-card`／`.gantt-*`／`.view-toggle-btn`／`.empty-state` 既有 class，不修改既有規則
    - _需求：5.3_
  - [x] 9.2 確認頁面沿用既有 `warroom-theme`／`theme-toggle` 機制，不另建主題邏輯
    - _需求：5.4_

- [x] 10. 最終檢查點 — 全面驗證
  - 依 [design.md](design.md)「測試策略」全部項目執行手動／自動化瀏覽器驗證，含：入口頁卡片、篩選
    排序、清單／甘特圖切換、階段表 4 種資料情境、互動編輯與 `state.editedActualDates` 隔離、
    `diffDays` 計算正確性、響應式與主題切換、全程無 console 錯誤。**實作差異**：所有函式皆包在
    IIFE 內（比照既有 `project-history-overview.js` 慣例，不對外暴露），因此無法如 design.md 測試
    策略所寫直接於 DevTools console 呼叫 `diffDays(...)`；改以 UI 互動驗證等價行為（模擬資料本身
    即涵蓋 `+3`／`+2`／`0`／`+32`／`-1`／`-2` 等多種差異值，並實際編輯日期驗證重算為 `+7`）。確認
    `git status` 僅新增規劃內檔案，未觸及既有 `project-history-*` 頁面與程式碼

---

## Notes

- 全部任務皆為純前端新增，不修改既有專案歷程頁面與程式碼，不引入建置工具或圖表框架，不呼叫任何
  外部 API
- 每項任務參照對應需求編號以利追溯
- 依 karpathy-guidelines：每項工作開始前先確認可驗證標準，完成後才勾選
- requirements.md 的待確認事項（1〜4）皆為「真實資料來源」層級的未決項，不影響本 tasks 的 prototype
  實作範圍
