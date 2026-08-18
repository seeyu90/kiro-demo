# 實作計畫：專案歷程靜態 Prototype

## 概述

新增 `docs/project-history-overview.html`（橫向總覽）與 `docs/project-history-detail.html`
（縱向歷程），共用 `docs/js/project-history-data.js` 模擬資料，各自搭配獨立渲染 JS。純前端修改，
不引入建置工具或框架，不修改既有 `docs/project-progress.html`／`docs/issues.html`／
`docs/burndown.html`。307（人時燃盡追蹤）已上線，「花費工時趨勢」「每週進度達成率」改為重用其
`estimated_hours`／`weekly_actual`／理想剩餘人時計算邏輯；客戶／PM 篩選改用 `300_員工專案` 試算表
「專案清單」表的 `客戶`／`PM` 欄位，詳見 requirements.md／design.md。

**狀態**：已完成實作並以 Playwright E2E 驗證通過，共 35/35 項檢查通過（入口頁卡片、橫向總覽篩選
交集／甘特圖切換／導向詳情頁、縱向歷程四區塊渲染／專案切換／Redmine 連結／主題切換、全程無 console
錯誤）。互動式 MCP 瀏覽器工具因沙盒網域限制無法連線本機伺服器，改用 Playwright（本機 headless
Chromium，經由 Bash 執行，非透過該 MCP 工具）對 `python3 -m http.server` 起的本機靜態伺服器直接跑
E2E，並附截圖確認實際畫面（甘特圖色塊、燃盡圖雙線疊圖皆正常渲染）。驗證過程中發現「依專案彙總理想
剩餘人時序列」有一個真實邏輯錯誤並已修正（見任務 9.1 附註），E2E 測試並針對此修正加了迴歸檢查
（理想線 y 座標單調遞增／人時單調遞減）。

---

## 任務

- [x] 1. 模擬資料
  - [x] 1.1 新增 `docs/js/project-history-data.js`，加入 `HISTORY_PROJECTS`（含 `customer`／`pm`）／
        `HISTORY_TASKS`／`HISTORY_ISSUES`／`HISTORY_BURNDOWN_ISSUES` 模擬資料常數
    - 依 [design.md](design.md) 的「模擬資料」章節建立，欄位對齊真實 305/306/307 與 `300_員工專案`
      試算表結構；3 個專案（Virtuous HRM／JZN 舊振南智慧工廠／AG 亞炬），customer/pm 取自
      `300_員工專案`「專案清單」表
    - _需求：8.1_

- [x] 2. 入口頁新增連結
  - [x] 2.1 `docs/index.html` 新增「專案歷程」卡片，導向 `project-history-overview.html`
    - _需求：1.1, 1.2_

- [x] 3. 橫向總覽頁 — 篩選與清單檢視
  - [x] 3.1 建立 `docs/project-history-overview.html` 頁面骨架（篩選列、檢視切換按鈕、清單/甘特圖
        容器）
    - _需求：2.1, 3.1_
  - [x] 3.2 `docs/js/project-history-overview.js`：`initFilters()`（狀態／客戶／PM 三個下拉選單）+
        `applyFilters(projects)` + `renderProjectList(projects)`
    - _需求：2.1, 2.2, 2.3, 2.4, 3.2, 3.4_

- [x] 4. 橫向總覽頁 — 甘特圖檢視
  - [x] 4.1 實作 `renderGanttChart(projects)`（手刻 SVG 條狀圖，每專案一列，任務為色塊，已完成／
        進行中任務用不同顏色區分）
    - _需求：3.3_
  - [x] 4.2 實作檢視模式切換（`state.viewMode` + 按鈕事件，`renderContent()` 統一分派）
    - _需求：3.1, 3.4, 3.5_

- [x] 5. 橫向總覽頁 — 導向詳情頁
  - [x] 5.1 專案清單列（專案名稱連結）加上連結，導向
        `project-history-detail.html?project={encodeURIComponent(project_name)}`
    - _需求：4.2_

- [x] 6. 檢查點 — 橫向總覽頁功能驗證
  - Playwright E2E（headless Chromium）：清單檢視預設顯示且 3 個專案列正確；狀態/客戶/PM 三個篩選
    選項齊全，篩選客戶=舊振南後正確只剩 1 列，客戶+PM 交集為空時正確顯示「目前無符合條件的專案」，
    清空篩選後恢復 3 列（需求 2.1〜2.4）；切換甘特圖後 svg 與任務色塊正確渲染、切換按鈕
    `aria-pressed` 狀態正確（需求 3.1〜3.5）；點擊專案連結 href 與導向後的 URL query string 皆正確
    帶上 `project=AG%20%E4%BA%9E%E7%82%AC`（需求 4.2）；16/16 項通過，無 console 錯誤

- [x] 7. 縱向歷程頁 — 專案選擇
  - [x] 7.1 建立 `docs/project-history-detail.html` 頁面骨架（專案選單、各區塊空容器）
    - _需求：4.1_
  - [x] 7.2 `docs/js/project-history-detail.js`：`getProjectFromQuery()` + `initProjectSelect()` +
        `renderDetail(projectName)` 統一入口
    - _需求：4.1, 4.3, 4.4_

- [x] 8. 縱向歷程頁 — 花費工時趨勢（重用 307 資料）
  - [x] 8.1 實作 `sumWeeklyHours(burndownIssues)`（依週日期加總 `weekly_actual`，命名與作法比照
        `burndown.js` 的 `sumWeeklyByDate`）+ `renderWorkHoursTrend(burndownIssues)`（手刻 SVG 折線圖，
        沿用 `issues.js` `renderTrendChart` 的座標計算手法）
    - _需求：5.1, 5.2_

- [x] 9. 縱向歷程頁 — 每週進度達成率（重用 307 燃盡序列邏輯）
  - [x] 9.1 實作 `idealHoursAt(issue, date)` + `computeActualSeries(issue)` + `computeProjectBurndown(issues)`
    - _需求：6.1, 6.3_
    - **實作變更**：原計畫比照 `burndown.js` 的 `computeIdealSeries(issue)`（回傳含起訖錨點的完整
      序列）逐議題算好後再加總。以 Node.js 執行驗證時發現：多議題彙總下，各議題自己的起訖錨點日期
      插入聯集後，其他議題在那天沒有對應資料，加總結果會在該日期出現不該有的凹陷（例：AG 亞炬彙總
      序列在 08/01 這天只算到剛好完成的那個議題，其餘進行中議題被跳過，總和從 25.08 瞬間掉到 0 又
      彈回 15.11）。改為 `idealHoursAt(issue, date)`：只在專案全部議題共用的週日期上，逐議題即時算
      當天的理想剩餘人時（不插入個別錨點）再加總；缺少合法起訖日期的議題該天回傳 `null`，直接排除
      不計入加總（需求 6.3）。修正後 3 個專案的理想序列皆單調遞減，無異常凹陷（已用 Node 重新執行
      驗證，並在 Playwright E2E 中對 AG 亞炬的燃盡圖 `polyline.burndown-ideal-line` 實際 SVG 座標
      加了迴歸測試，確認 y 座標單調遞增／人時單調遞減）。
  - [x] 9.2 實作 `renderBurndownChart(idealSeries, actualSeries)`（同一張 SVG 疊合實線／虛線兩條線，
        沿用 `burndown.js` 既有的 `.burndown-ideal-line`／`.burndown-actual-line`／
        `.burndown-actual-point` CSS 類別）
    - _需求：6.2_

- [x] 10. 縱向歷程頁 — 測試問題趨勢與客訴議題狀態
  - [x] 10.1 實作 `weekStart(dateStr)` + `renderTestingTrend(issues)`（依 ISO 週分組計數）
    - _需求：7.1_
  - [x] 10.2 實作 `computeComplaintStatus(issues)` + `renderComplaintSummary(result)`（依議題明細
        `status` 逐筆判斷已解決／未解決，非 `month_kpi` 月度彙總欄位；含未解決客訴清單、Redmine 連結）
    - _需求：7.2, 7.3, 7.4_

- [x] 11. 檢查點 — 縱向歷程頁功能驗證
  - Playwright E2E：帶 `?project=Virtuous+HRM` 直接開啟時下拉選單與標題正確預選（需求 4.1、4.4）；
    花費工時趨勢／燃盡圖（實際線＋理想線）／測試問題趨勢三個 svg 皆正確渲染（需求 5.1、6.1、6.2、
    7.1）；Virtuous HRM 無未解決客訴、正確不顯示「未解決客訴清單」；切換到 JZN 舊振南智慧工廠後
    正確顯示「未解決客訴清單」，Redmine 連結 href／`target="_blank"`／`rel="noopener"` 皆正確（需求
    7.2〜7.4）；切換專案後所有區塊正確重新渲染（需求 4.3）；19/19 項通過，無 console 錯誤

- [x] 12. 樣式與響應式設計
  - [x] 12.1 新增 `.view-toggle`／`.view-toggle-btn`／`.project-history-link`／`.gantt-svg`／
        `.gantt-row-label`／`.gantt-row-baseline`／`.gantt-task-done`／`.gantt-task-open`，沿用既有
        768px／560px 響應式斷點與既有表格/趨勢圖 class（未新增額外斷點規則，兩個新頁面皆重用既有
        `table.project-tasks`／`.trend-svg` 響應式行為）
    - _需求：8.3_
  - [x] 12.2 兩個新頁面沿用既有 `warroom-theme`／`theme-toggle` 機制（與 issues.js/burndown.js 同一套
        程式碼，非另建邏輯）
    - _需求：8.4_

- [x] 13. 最終檢查點 — 全面驗證
  - 依 [design.md](design.md)「測試策略」全部項目以 Playwright（本機 headless Chromium，透過
    `python3 -m http.server` 起本機靜態伺服器）執行 E2E，35/35 項全部通過，涵蓋入口頁卡片、橫向
    總覽三個篩選交集／清單與甘特圖切換／甘特圖色塊／導向詳情頁 query string、縱向歷程四區塊渲染／
    專案切換／未解決客訴 Redmine 連結／主題切換，全程無 console error／pageerror；並以截圖確認實際
    畫面（甘特圖色塊、燃盡圖雙線疊圖皆正常渲染，已提供給使用者）。`git status` 確認僅新增規劃內的
    7 個檔案、`docs/index.html`／`docs/css/style.css` 為預期內的擴充修改，未觸及 305/306/307 既有
    頁面與程式碼。

---

## Notes

- 全部任務皆為純前端新增，不修改既有 305/306/307 頁面與程式碼，無後端／API 變更（含 `300_員工專案`
  試算表，本階段僅用其內容仿造模擬資料，不呼叫任何 API）
- 每項任務參照對應需求編號以利追溯
- 依 karpathy-guidelines：每項工作開始前先確認可驗證標準，完成後才勾選
- requirements.md 開頭列出的待確認事項已全數解決（307 上線 ＋ `300_員工專案` 試算表內容確認）
- E2E 驗證方式：互動式 MCP 瀏覽器工具的沙盒網域限制無法連線本機伺服器／`file://`，改用 Playwright
  透過 Bash 在本機啟動 headless Chromium 直接對本機靜態伺服器跑測試，測試腳本與截圖存於
  session 的 scratchpad 目錄（非專案檔案，不納入版控）
