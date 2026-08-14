# Implementation Plan: 306 臭蟲議題靜態 Prototype

## Overview

新增 `docs/issues.html` + `docs/js/issues.js` 呈現 306 臭蟲議題模擬資料，並將既有 `docs/index.html`
（305 內容）搬移為 `docs/project-progress.html` + `docs/js/project-progress.js`，`docs/index.html`
改為極簡入口頁。純前端修改，不引入建置工具或框架。每項任務均可獨立開發、於瀏覽器手動驗證並 Commit。

**狀態**：已完成實作並以 Playwright E2E 驗證通過，共 49/49 項檢查通過：基礎頁面／篩選／主題切換等
32 項（Task 11 移除工程師負載／專案清單相關斷言後改為驗證區塊已移除；Task 12 後「全部顯示」類斷言
改為先清空狀態篩選再驗證）＋ Task 10 依專案分類統計／歸屬類型徽章 8 項 ＋ Task 11 議題編號 Redmine
連結 4 項 ＋ Task 12 預設狀態篩選「新建立」5 項。

---

## Tasks

- [x] 1. 首頁改版：305 搬移 + 入口頁
  - [x] 1.1 新增 `docs/project-progress.html`（原 `docs/index.html` 內容原樣搬移）
    - 複製既有 `docs/index.html` 全部內容至新檔案，`<script src="js/app.js">` 改為
      `<script src="js/project-progress.js">`
    - _需求：1.3_

  - [x] 1.2 新增 `docs/js/project-progress.js`（由 `docs/js/app.js` 更名搬移，內容不變）
    - _需求：1.3_

  - [x] 1.3 改寫 `docs/index.html` 為極簡入口頁
    - 移除原本的資料邏輯與 `<script>` 參照，改為兩張卡片／連結：「305 專案進度戰情室」
      （連到 `project-progress.html`）與「306 臭蟲議題」（連到 `issues.html`）
    - _需求：1.1, 1.2_

  - [x] 1.4 刪除舊 `docs/js/app.js`（內容已搬移至 `project-progress.js`，避免重複檔案）
    - _需求：1.3_

  - [x] 1.5 檢查點 — 入口頁與 305 頁面驗證
    - 瀏覽器開啟 `docs/index.html`，確認兩個連結可用；開啟 `docs/project-progress.html`，
      確認行為與搬移前的 `index.html` 完全一致

- [x] 2. 306 模擬資料
  - [x] 2.1 新增 `docs/js/issues.js`，加入 `MONTH_KPI`／`DAILY_KPI`／`ISSUES` 模擬資料常數
    - 依 [design.md](design.md) 的「模擬資料」章節建立，欄位對齊真實 306 試算表分頁結構
    - _需求：2.1, 3.1, 4.1, 5.1_

- [x] 3. KPI 摘要卡片
  - [x] 3.1 建立 `docs/issues.html` 頁面骨架（header、月份選單、KPI 卡片區、趨勢圖區、Issue 清單區
        的空容器）
    - _需求：2.1_

  - [x] 3.2 實作 `populateMonthSelect()` 與 `renderKpiCards(monthRecord)`
    - 月份下拉選單預設選中最新月份；卡片顯示 8 個統計值 + Top3 排行
    - _需求：2.1, 2.2, 2.3, 2.4_

- [x] 4. 每日趨勢圖
  - [x] 4.1 實作 `renderTrendChart(records)`（手刻 SVG 折線圖）
    - X 軸等距分佈日期，Y 軸依 `total` 最大值等比例縮放；資料點加 tooltip 互動
    - _需求：3.1, 3.2, 3.3_

- [x] 5. Issue 明細清單
  - [x] 5.1 實作 `initProjectFilter()` / `initStatusFilter()`
    - 讀取 `ISSUES` 唯一值產生下拉選項，預設「全部」
    - _需求：4.2, 4.3_

  - [x] 5.2 實作 `renderIssueTable(state)`
    - 依 `state.issueFilters` 過濾並渲染表格；空結果顯示提示文字
    - _需求：4.1, 4.4, 4.5_

- [x] 6. 工程師負載／專案清單表（**已於 Task 11 移除，見下方**）
  - [x] 6.1 實作 `renderEngineerLoadTable()` 與 `renderProjectListTable()`
    - 頁面載入時各自靜態渲染一次，無篩選
    - _需求：5.1, 5.2, 5.3（舊編號，本需求已於後續 requirements.md 修訂中移除）_

- [x] 7. 檢查點 — 306 頁面功能驗證
    - 依 [design.md](design.md) 的「Testing Strategy」章節第 3 點逐項於瀏覽器手動驗證

- [x] 8. 樣式調整
  - [x] 8.1 新增入口頁卡片樣式（`docs/index.html` 用）
    - _需求：1.1_

  - [x] 8.2 新增 KPI 卡片、趨勢圖、Issue 表格樣式，含 768px／560px 響應式斷點
    - 沿用 `style.css` 既有配色與 class 命名慣例，表格於 560px 以下切換為堆疊卡片版型
    - _需求：5.2, 5.3（舊編號 6.2/6.3，requirements.md 需求 6 已改編號為需求 5）_

- [x] 9. 最終檢查點 — 全面驗證
    - 完整走過 [design.md](design.md) Testing Strategy 全部項目，所有需求驗收標準逐一符合，
      無 console 錯誤

- [x] 10. 依專案分類統計 + 議題歸屬類型標示（取代 Top3 責任人排行）
  - [x] 10.1 移除 `MONTH_KPI` 的 `top3` 欄位與 `renderTop3()`，改為 `computeProjectBreakdown(issues)` +
        `renderProjectBreakdown()`，依專案分組統計客訴／測試／其他數量與總計
    - 理由：客訴問題影響整個專案（全專案成員共同承擔），測試階段問題歸屬個別開發者，兩者性質不同，
      故以「專案」而非「負責人」作為統計分類主軸
    - `docs/issues.html` 的 `#top3` 容器改為 `#project-breakdown`
    - _需求：2.4_

  - [x] 10.2 Issue 明細清單新增「歸屬類型」欄位（徽章樣式）
    - `buildGenericTable` 支援欄位可選的 `render(value, record)` 函式；新增
      `attributionLabel(type)` / `attributionClass(type)` 依 `type` 對應
      `Complaint→專案共同責任 / TestingBug→個人責任 / 其餘→其他`
    - _需求：4.1, 4.1a_

  - [x] 10.3 樣式：`.breakdown-heading`／`.attribution-badge`（`-shared`／`-individual`／`-other`）
    - `.top3-list`／`.top3-heading`／`.top3-badge` 改名為 `.breakdown-wrap`／`.breakdown-heading`
    - _需求：2.4, 4.1a_

  - [x] 10.4 檢查點 — Playwright E2E 驗證
    - 依專案分類統計表正確渲染（4 個專案分組，數字正確）；`#top3` 元素已移除；議題明細清單 6 筆
      皆正確標示歸屬類型徽章（含 class 正確對應）；月份切換仍正常更新 KPI 卡片；無 console error
    - 8/8 通過

- [x] 11. 移除工程師負載／專案清單表 + 議題明細欄位調整
  - [x] 11.1 移除 `docs/issues.html` 的工程師負載／專案清單區塊（`#engineer-load-table`／
        `#project-list-table` 及對應 `<section>`）
    - _需求：（不納入範圍段落，見 requirements.md）_

  - [x] 11.2 移除 `docs/js/issues.js` 的 `ENGINEER_LOAD`／`PROJECT_LIST` 常數與
        `renderEngineerLoadTable()`／`renderProjectListTable()`
    - _需求：（同上）_

  - [x] 11.3 調整 `ISSUE_COLUMNS` 欄位順序與內容
    - 改為：議題編號／專案／主旨／歸屬類型／狀態／負責人／開始日期／到期日期／工作天數；移除
      `type`（類型）／`tracker`（追蹤標籤）欄位（分類意義已由歸屬類型徽章呈現）
    - _需求：4.1_

  - [x] 11.4 「議題編號」欄位改為可點擊連結
    - 新增 `REDMINE_ISSUE_URL_BASE = "https://redmine.amastek.com.tw/issues/"`；`ISSUE_COLUMNS` 的
      `issue_id` 欄位新增 `render` 函式，輸出 `<a class="issue-id-link" target="_blank"
      rel="noopener noreferrer">`
    - _需求：4.1b_

  - [x] 11.5 樣式：`.issue-id-link`（無底線，hover/focus 才顯示底線，與 `.back-link` 一致慣例）
    - _需求：4.1b_

  - [x] 11.6 檢查點 — Playwright E2E 驗證
    - 議題明細表格欄位順序與標籤正確（9 欄，不含類型／追蹤標籤）；議題編號連結 href 正確指向
      Redmine、`target="_blank"`、`rel` 含 `noopener`、預設無底線；工程師負載／專案清單區塊確認已
      移除（`#engineer-load-table`／`#project-list-table` 皆為 `null`）；全量回歸重測（32 項基礎
      檢查 + 8 項 Task 10 檢查）皆通過，無 console error
    - 4/4（新增）+ 32/32（回歸）+ 8/8（Task 10 回歸）通過

- [x] 12. 議題明細預設篩選改為「新建立」
  - [x] 12.1 `state.issueFilters` 預設值改為 `{ project: null, status: "新建立" }`
    - 原預設為 `{ project: null, status: null }`（全部狀態）；改為聚焦最需要處理的新進議題
    - _需求：4.3_

  - [x] 12.2 `initIssueFilters()` 產生下拉選項後同步設定 `<select>` 初始 `value`
    - `projectSelect.value = state.issueFilters.project || ""`；
      `statusSelect.value = state.issueFilters.status || ""`，確保畫面與 `state` 一致
    - _需求：4.3_

  - [x] 12.3 檢查點 — Playwright E2E 驗證
    - 頁面載入時專案篩選為「全部專案」、狀態篩選為「新建立」；預設僅顯示 1 筆符合議題；清除狀態
      篩選後恢復顯示全部 6 筆；全量回歸重測（32 項基礎檢查，其中「全部顯示」類斷言改為先清空狀態
      篩選再驗證）皆通過，無 console error
    - 5/5（新增）+ 32/32（回歸）+ 4/4（Task 11 回歸）通過

- [x] 13. 每日趨勢圖新增橫軸日期標籤／縱軸數值刻度（見需求 3.4、3.5）
  - [x] 13.1 `renderTrendChart` 改用 `TREND_PADDING_LEFT/RIGHT/TOP/BOTTOM` 分向留白（原單一
        `padding` 值不足以容納軸線標籤）
    - _需求：3.4, 3.5_

  - [x] 13.2 新增 `pickLabelIndices(count, maxLabels)`：資料點數量超過 `TREND_MAX_X_LABELS`（6）時，
        等距挑選含首尾的標籤索引，避免橫軸標籤重疊
    - _需求：3.5_

  - [x] 13.3 新增 `shortDate(dateStr)`：`YYYY-MM-DD` 轉為 `MM/DD` 精簡顯示
    - _需求：3.5_

  - [x] 13.4 繪製 3 條縱軸格線（0／中間值／最大值）與對應數字標籤
    - _需求：3.4_

  - [x] 13.5 樣式：新增 `.trend-gridline`／`.trend-axis-label`
    - _需求：3.4, 3.5_

  - [x] 13.6 檢查點 — Playwright E2E 驗證
    - 3 條縱軸格線正確渲染；橫軸標籤在資料點 ≤6 時全部顯示、>6 時精簡為 6 個且含首尾；標籤格式為
      `MM/DD`；原有 7 個資料點／折線／tooltip 功能不受影響
    - 6/6（新增）通過；全量回歸重測 32+4+5 項（Task 11、12 回歸）皆通過

- [x] 14. 月度 KPI 區塊新增說明文字，釐清「月結」與「即時資料」的關係（見需求 2.5、2.6）
  - [x] 14.1 於「月度 KPI」標題下新增 `<p class="section-note">`：「月結數字，當月進行中尚未結算；
        下方依專案分類統計與議題明細皆為即時資料，不受此處月份選擇影響」
    - 起因：使用者反映「當月仍有議題要顯示，但統計資料是月底結算」，容易誤解為「當月無資料」
    - _需求：2.5_

  - [x] 14.2 說明文字僅置於月度 KPI 區塊一處，不重複放在議題明細的專案／狀態篩選控制項附近
    - 初版曾一併在「依專案分類」標題與「議題明細」篩選列旁加註，使用者指出篩選列旁的說明文字容易
      讓人誤以為專案／狀態篩選未生效（實際上這兩個篩選確實會影響下方議題明細），故收斂為單一位置
    - _需求：2.6_

  - [x] 14.3 樣式：新增 `.section-note`
    - _需求：2.5_

  - [x] 14.4 檢查點 — Playwright E2E 驗證
    - 頁面僅有 1 個 `.section-note`（位於月度 KPI 區塊）；文字同時包含「月結」與「即時」關鍵字；
      「依專案分類」標題與議題明細篩選列附近皆無重複說明文字
    - 4/4（新增）通過；全量回歸重測 32+4+5+6 項（Task 11〜13 回歸）皆通過

- [x] 15. 改為分頁籤呈現：統計摘要（月度 KPI＋每日趨勢） / 議題資料（依專案分類＋議題明細）
  - [x] 15.1 `docs/issues.html` 改用純 CSS radio+label 分頁籤結構（`.tabs`／`.tab-radio`／
        `.tab-buttons`／`.tab-panel`），不需 JS
    - 起因：使用者反映原本頁首單一篩選列同時放月份／專案／狀態三個選單，容易誤以為月份篩選會
      影響下方所有區塊；改為分頁籤後，篩選控制項各自歸屬到其實際影響的分頁籤內
    - 「統計摘要」分頁籤：月度 KPI（含月份選單、section-note）＋ 每日趨勢；預設顯示
    - 「議題資料」分頁籤：依專案分類（原本在月度 KPI 區塊內，移至此）＋ 議題明細（含專案／狀態
      選單）
    - `docs/js/issues.js`：`getElementById` 查找邏輯不受影響（ID 不變，只是父層容器改變），無需
      修改
    - _需求：5.1, 5.2, 5.3_

  - [x] 15.2 `section-note` 文字更新：「下方依專案分類統計與議題明細」改為「「議題資料」分頁的
        依專案分類統計與議題明細」，反映內容已移至不同分頁籤、不再是「下方」
    - _需求：2.5_

  - [x] 15.3 樣式：新增 `.tab-radio`／`.tab-buttons`／`.tab-button`／`.tab-panel`
    - `.tab-radio` 以 clip 隱藏但保留鍵盤可聚焦；`:focus-visible` 有明顯外框，符合可及性
    - _需求：5.1_

  - [x] 15.4 檢查點 — Playwright E2E 驗證
    - 預設顯示「統計摘要」分頁籤（議題資料隱藏）；分頁籤各自包含正確區塊（KPI+趨勢 vs
      分類+明細）；點擊「議題資料」分頁籤正確切換顯示；切換後資料仍正確渲染（不因隱藏過而失效）；
      `section-note` 文字更新為提及「議題資料」分頁、不再用「下方」
    - 6/6（新增）通過；全量回歸重測 32+4+5+6+4 項（Task 11〜14 回歸，含月份/note/axis 測試腳本
      補上分頁籤點擊後才能互動的修正）皆通過，無 console error

- [x] 16. 每日趨勢與依專案分類改為依所選月份篩選；依專案分類移回統計摘要分頁籤；橫軸標籤改為
      全部顯示並旋轉（反轉 Task 10／13／15 部分決策，見需求 2.4a、3.1a、3.5、5.1 的設計變更紀錄）
  - [x] 16.1 `sameMonth(dateStr, yearMonth)` 輔助函式 + `renderStatsTab(yearMonth)` 統一入口
    - 起因：使用者反映「每日趨勢不是應該按照月份去呈現嗎？」「依專案分類統計也是統計摘要裡依照
      選擇月份呈現」；月份判斷依議題 `start_date`（議題建立日），非 `due_date`
    - `renderProjectBreakdown(monthIssues)` 改為接收已篩選子集；篩選後為空時顯示
      「所選月份無議題資料」；`renderTrendChart(records)` 篩選後為空時顯示「所選月份無每日趨勢
      資料」
    - _需求：2.4a, 3.1a_

  - [x] 16.2 「依專案分類」區塊移回「統計摘要」分頁籤（原 Task 15 移至「議題資料」分頁籤，此次
        反轉該決策）
    - `section-note` 文字更新：「月度 KPI 為月結數字，當月進行中尚未結算；每日趨勢與依專案分類
      統計則依此處所選月份即時呈現；「議題資料」分頁的議題明細不受月份篩選影響（顯示全部議題）」
    - _需求：2.5, 5.1_

  - [x] 16.3 橫軸標籤改為每個資料點都顯示日期並以 -45 度旋轉（取代 Task 13 的「>6 個資料點時
        等距挑選含首尾標籤」做法）
    - 起因：使用者詢問「hover 要有值跟橫軸數值能補齊嗎？」，確認 hover 維持瀏覽器原生 `<title>`
      提示框即可（不需自訂 tooltip），橫軸則改為顯示每個資料點的日期；使用者進一步要求
      「可以旋轉啊，斜斜的應該就不會重疊」，故加上 `transform="rotate(-45 x y)"` + `text-anchor: end`
    - 移除 `TREND_MAX_X_LABELS` 常數與 `pickLabelIndices()` 函式；`TREND_HEIGHT` 220→250、
      `TREND_PADDING_BOTTOM` 28→55 以容納旋轉後的斜向文字
    - _需求：3.3, 3.5_

  - [x] 16.4 檢查點 — Playwright E2E 驗證
    - 每日趨勢與依專案分類隨月份切換正確重新渲染；空月份顯示對應的空狀態文字；「依專案分類」
      確認位於統計摘要分頁籤；橫軸標籤數量等於資料點數量（不再受 6 個上限限制）；所有橫軸標籤皆有
      `rotate(-45 ...)` 與 `text-anchor="end"`；資料點 `<title>` 提示框內容正確；無 console error
    - 7/7（月份篩選，`e2e_monthscope.js`）+ 7/7（橫軸旋轉，`e2e_rotation.js`）通過；全量回歸重測
      33+4+5+4+5+6 項（Task 11〜15 回歸腳本）皆通過

- [x] 17. 排除 tracker=測試 議題；依專案分類統計表新增排序功能（見需求 2.4b、4.6）
  - [x] 17.1 `RAW_ISSUE_ROWS` + 載入時整批過濾 `tracker === "測試"` 的議題
    - 起因：使用者反映「如果 tracker 是測試的不列入品質裡面，那個是測試議題」；確認排除範圍為
      整個頁面（議題明細清單＋依專案分類統計，非僅統計類區塊）
    - 新增一筆 `tracker: "測試"` 的樣本資料（issue_id 5170）驗證排除邏輯；`ISSUES` 改為
      `RAW_ISSUE_ROWS.filter(issue => issue.tracker !== "測試")`，其餘渲染函式讀取 `ISSUES`
      不需個別修改
    - _需求：4.6_

  - [x] 17.2 依專案分類統計表新增排序（客訴／測試／其他／總計）
    - 起因：使用者詢問「依專案分類 能有排序嗎？例如可以依照客訴數量 測試數量 總數量」
    - `state.breakdownSort = { key: null, dir: -1 }`；`buildGenericTable` 擴充 `sortState`／
      `onSortClick` 選填參數，欄位標記 `sortable: true` 時標題渲染為可點擊按鈕；同欄位再次點擊
      反轉方向，切換不同欄位預設由大到小；目前排序欄位標題顯示 ▲／▼ 指示；專案欄位不可排序
    - 新增 `.sort-button` CSS（無框透明背景、hover/`:focus-visible` 呈現 accent 色與外框，符合
      可及性）
    - _需求：2.4b_

  - [x] 17.3 檢查點 — Playwright E2E 驗證
    - tracker=測試 議題不出現在議題明細清單（含清空狀態篩選後）、不計入依專案分類統計；點擊排序
      按鈕正確排序（含降冪／升冪切換、切換不同欄位重設方向、▲／▼ 指示正確）；切換月份後排序狀態
      維持、頁面不崩潰；無 console error
    - 2/2（tracker 排除，`e2e_tracker_filter.js`）+ 8/8（排序，`e2e_sort.js`）通過；全量回歸重測
      33+4+5+4+5+6+7 項（Task 11〜16 回歸腳本）皆通過

---

## Notes

- 全部任務皆為純前端修改，無後端／API 變更（真實 306 資料串接為下一階段獨立 spec）
- 每項任務參照對應需求編號以利追溯
- 依 karpathy-guidelines：每項工作開始前先確認可驗證標準，完成後才勾選

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2"] },
    { "id": 1, "tasks": ["1.3"] },
    { "id": 2, "tasks": ["1.4"] },
    { "id": 3, "tasks": ["1.5", "2.1"] },
    { "id": 4, "tasks": ["3.1"] },
    { "id": 5, "tasks": ["3.2", "4.1", "5.1", "6.1"] },
    { "id": 6, "tasks": ["5.2"] },
    { "id": 7, "tasks": ["7"] },
    { "id": 8, "tasks": ["8.1", "8.2"] },
    { "id": 9, "tasks": ["9"] },
    { "id": 10, "tasks": ["10.1", "10.2"] },
    { "id": 11, "tasks": ["10.3"] },
    { "id": 12, "tasks": ["10.4"] },
    { "id": 13, "tasks": ["11.1", "11.2"] },
    { "id": 14, "tasks": ["11.3"] },
    { "id": 15, "tasks": ["11.4"] },
    { "id": 16, "tasks": ["11.5"] },
    { "id": 17, "tasks": ["11.6"] },
    { "id": 18, "tasks": ["12.1"] },
    { "id": 19, "tasks": ["12.2"] },
    { "id": 20, "tasks": ["12.3"] },
    { "id": 21, "tasks": ["13.1"] },
    { "id": 22, "tasks": ["13.2", "13.3"] },
    { "id": 23, "tasks": ["13.4"] },
    { "id": 24, "tasks": ["13.5"] },
    { "id": 25, "tasks": ["13.6"] },
    { "id": 26, "tasks": ["14.1"] },
    { "id": 27, "tasks": ["14.2"] },
    { "id": 28, "tasks": ["14.3"] },
    { "id": 29, "tasks": ["14.4"] },
    { "id": 30, "tasks": ["15.1"] },
    { "id": 31, "tasks": ["15.2"] },
    { "id": 32, "tasks": ["15.3"] },
    { "id": 33, "tasks": ["15.4"] }
  ]
}
```
