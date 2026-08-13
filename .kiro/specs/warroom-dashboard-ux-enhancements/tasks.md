# Implementation Plan: 戰情室 Dashboard UX 強化

## Overview

於既有 `docs/index.html` / `docs/js/app.js` / `docs/css/style.css` 上，新增未完成任務辨識
（逾期／本週到期含已逾期／只顯示未完成，皆有預設值）、任務類型多選篩選（預設「功能」＋「PR」）
與整體進度摘要。純前端修改，不新增檔案、不引入建置工具。每項任務均可獨立開發、於瀏覽器手動驗證並 Commit。

**狀態**：已完成實作並於瀏覽器驗證通過（見下方各項）。

---

## Tasks

- [x] 1. 模擬資料擴充
  - [x] 1.1 新增 `daysFromToday(offset)` / `thisWeekDueSoon()` 工具函式與 `task_type` 欄位
    - 在 `app.js` 加入 `daysFromToday(offset)`，回傳相對今天（時分秒歸零）的 `YYYY-MM-DD` 字串
    - 為 `RECORDS` 每筆紀錄新增 `task_type`（"功能" | "PR" | "調整" | "遺漏" | "臭蟲"，對齊
      `warroom-data-api-real-source` 的 5 個類型分頁），每個專案至少一筆「功能」與一筆「PR」
    - _需求：6.1, 7.4_

  - [x] 1.2 加入逾期／本週到期／未來到期示範情境
    - 新增至少一筆 `status` 非 completed、`planned_completion_date` 為 `daysFromToday(負數)` 的任務（逾期）
    - 新增至少一筆 `thisWeekDueSoon()`（本週內、相對今天尚未逾期）的未完成任務（本週到期但不逾期）
    - 新增至少一筆 `planned_completion_date` 晚於本週、未完成的任務（未來對照組）
    - _需求：7.1, 7.2, 7.3_

- [x] 2. 篩選與統計工具函式
  - [x] 2.1 實作 `getWeekRange(date)`
    - 回傳 `{ start, end }`，分別為當週週一 00:00 與週日 23:59（本地時間）
    - _需求：3.5_

  - [x] 2.2 實作 `isOverdue(task, today)` 與 `isDueByThisWeekEnd(task, weekRange)`
    - `status === "completed"` 或 `planned_completion_date` 為 `null` 時一律回傳 `false`
    - `isDueByThisWeekEnd` 不限下界（只檢查 `<= weekRange.end`），故已逾期任務必為其子集
    - _需求：3.2, 3.3, 3.6_

  - [x] 2.3 實作 `matchesProjectAndType(task, state)` 與 `filterTasks(records, state, today, weekRange)`
    - `matchesProjectAndType`：`typeFilters` 為空陣列時視為不篩選（需求 6.6）
    - `filterTasks` 依序套用 `project`／`typeFilters`／`incompleteOnly`／`scopeFilter` 四個條件（AND 邏輯）
    - _需求：2.2, 2.3, 3.2, 3.3, 3.4, 6.5, 6.6_

  - [x] 2.4 實作 `computeSummary(records, state, today)`
    - 僅套用 `project` 與 `typeFilters` 範圍（不受 `incompleteOnly`／`scopeFilter` 影響）
    - 回傳 `{ total, completed, in_progress, pending, overdue }`
    - _需求：4.1, 4.2, 4.3, 4.4, 6.7_

  - [x] 2.5 實作 `sortOverdueFirst(tasks, today)`
    - 以 stable sort 將逾期任務排到陣列最前面，其餘任務維持原順序
    - _需求：2.7_

- [x] 3. 檢查點 — 邏輯驗證
  - 於瀏覽器實測：預設狀態（全部專案／功能＋PR／本週到期含已逾期／只顯示未完成）下摘要與清單數字互相一致，已核對無誤。

- [x] 4. 控制項渲染與事件綁定
  - [x] 4.1 擴充 `populateProjectSelect()`：顯示任務數，預設選中「全部專案」
    - 選項文字改為 `"{{專案名稱}}（{{任務數}}）"`；「全部專案」顯示總任務數
    - _需求：5.1, 5.2, 2.8_

  - [x] 4.2 新增 `initTypeFilter()`（多選 checkbox，取代原本單選 `<select>`）
    - 讀取 `RECORDS` 的 `task_type` 唯一值，依 `PRIORITY_TYPES = ["功能", "PR"]` 排序在前
    - 初始勾選 `state.typeFilters`（預設 `["功能", "PR"]`），`change` 事件將值加入／移出陣列
    - _需求：6.3, 6.4_

  - [x] 4.3 新增「只顯示未完成」checkbox 與「範圍」radio（全部／本週到期／已逾期，預設「本週到期」）
    - 於 `index.html` 新增對應 HTML 結構；checkbox 初始 `checked = true`；`scope` radio 預設勾選 `due_this_week`
    - `app.js` 綁定 `change` 事件更新 `state` 並呼叫 `render()`
    - _需求：2.1, 2.6, 3.1, 3.7_

  - [x] 4.4 確認篩選狀態於切換專案時不被重置
    - 專案下拉選單的 `change` 事件只更新 `state.project`，不重設 `incompleteOnly` / `typeFilters` / `scopeFilter`
    - _需求：2.5_

- [x] 5. 表格與摘要渲染擴充
  - [x] 5.1 `COLUMNS` 新增「類型」欄位
    - _需求：6.2_

  - [x] 5.2 狀態欄位改為文字＋樣式 badge
    - 依 `status` 值套用不同 CSS class，文字內容維持可讀（不得只靠顏色辨識）
    - _需求：1.1, 1.2_

  - [x] 5.3 逾期任務加註「逾期」標示
    - 於任務名稱欄位旁加 `<span class="overdue-tag">逾期</span>`，判斷邏輯重用 `isOverdue`
    - _需求：1.3_

  - [x] 5.3a `buildTable` 渲染前套用 `sortOverdueFirst`
    - 各專案任務陣列先排序（逾期優先）再傳入 `buildTable`
    - _需求：2.7_

  - [x] 5.4 篩選後專案區塊為空的提示文字
    - 區塊標題維持顯示，內容改為「目前無符合條件的任務」
    - _需求：2.4_

  - [x] 5.5 新增摘要列渲染 `renderSummary(summary)`
    - 於 `#content` 上方新增 `#summary` 區塊，顯示任務總數／已完成／進行中／待開始／逾期五個數字
    - 專案切換或任一篩選變更時重新計算並更新
    - _需求：4.1, 4.2, 4.3_

- [x] 6. 檢查點 — 渲染驗證
  - 已依 [design.md](design.md) 的「Testing Strategy」章節逐項於瀏覽器手動驗證通過。

- [x] 7. 樣式調整
  - [x] 7.1 新增狀態 badge、逾期標示、摘要列樣式
    - 於 `style.css` 新增 `.status-badge`、`.status-completed` / `.status-in_progress` / `.status-pending`、`.overdue-tag`、`#summary` 相關樣式
    - _需求：1.1, 1.3, 4.1_

  - [x] 7.2 新增篩選控制項樣式與響應式調整
    - 類型多選 checkbox（`.type-filter`）、範圍 radio（`.scope-filter`）、未完成 checkbox 的排版；768px 與 560px 斷點下確認不破版
    - _需求：（響應式設計，見 steering project-standards.md）_

- [x] 8. 最終檢查點 — 全面驗證
  - 已完整走過 [design.md](design.md) Testing Strategy 全部項目，所有需求驗收標準逐一符合。

---

## Notes

- 全部任務皆為純前端修改，無後端／API 變更（Rails 端對應強化見 `warroom-data-api-real-source` 需求 10）
- 每項任務參照對應需求編號以利追溯
- 依 karpathy-guidelines：每項工作開始前先確認可驗證標準（對照本檔任務描述與 [design.md](design.md) Testing Strategy），完成後才勾選

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "2.1"] },
    { "id": 2, "tasks": ["2.2"] },
    { "id": 3, "tasks": ["2.3", "2.4"] },
    { "id": 4, "tasks": ["3"] },
    { "id": 5, "tasks": ["4.1", "4.2", "4.3"] },
    { "id": 6, "tasks": ["4.4", "5.1", "5.2", "5.3", "5.4", "5.5"] },
    { "id": 7, "tasks": ["6"] },
    { "id": 8, "tasks": ["7.1", "7.2"] },
    { "id": 9, "tasks": ["8"] }
  ]
}
```
