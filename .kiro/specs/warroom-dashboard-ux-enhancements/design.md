# 設計文件

## Overview

本強化僅修改 `docs/` 靜態站既有三檔案（`index.html`、`js/app.js`、`css/style.css`），
不引入建置工具或框架，不呼叫外部 API。所有邏輯為純前端 JavaScript，資料仍來自
`app.js` 內的 `RECORDS` 陣列（模擬資料）。

核心變更：
1. `RECORDS` 新增 `task_type` 欄位，並將部分任務的 `planned_completion_date` 改為相對「今天」動態計算，確保逾期／本週到期情境永遠可展示。
2. 篩選狀態集中於單一物件 `state`，任一篩選變更皆重新渲染表格與摘要列，不觸發整頁重載（本來就是 SPA-like 靜態頁）。
3. 表格新增「類型」欄位與逾期標示；狀態欄位改為 badge。

---

## Architecture

```
DOMContentLoaded
    │
    ▼
populateProjectSelect()  ──┐
initTypeFilter()            │  初始化控制項（皆讀取 RECORDS 產生選項）
initScopeFilter()           │
initIncompleteToggle()      │
    │                       │
    ▼                       ▼
render()  ← 使用者互動（change/click 事件）皆呼叫 render() 重新渲染
    │
    ├─ filterTasks(RECORDS, state)   → 依 project / typeFilters / scopeFilter / incompleteOnly 過濾
    ├─ computeSummary(filteredByProjectAndType)  → 摘要列（不受 incompleteOnly / scopeFilter 影響，見需求 4.4）
    ├─ groupByProject(filtered) → buildTable(...) → 逐專案渲染表格
    └─ renderEmptyStates(...)
```

**狀態物件 `state`**（模組內變數，不做持久化）：

```js
var PRIORITY_TYPES = ["功能", "PR"];

var state = {
  project: null,                        // null = 全部專案（預設，需求 2.8）
  typeFilters: PRIORITY_TYPES.slice(),  // 預設多選「功能」「PR」（需求 6.4）
  scopeFilter: "due_this_week",         // "all" | "due_this_week" | "overdue"（需求 3.7 預設本週到期）
  incompleteOnly: true                  // 預設開啟，畫面主要聚焦未完成／逾期任務（需求 2.6）
};
```

所有控制項的事件處理器只改 `state` 的對應欄位並呼叫 `render()`，`render()` 為唯一渲染入口，
確保任一篩選都不會互相覆蓋（需求 2.5：切換專案保留「只顯示未完成」狀態）。

---

## Components and Interfaces

### 模擬資料：`RECORDS`

新增欄位 `task_type`（`"功能"` | `"PR"` | `"調整"` | `"遺漏"` | `"臭蟲"`，對齊 `warroom-data-api-real-source`
的 5 個類型分頁），並改用相對日期產生逾期／本週到期／未來到期三種示範情境（需求 7）：

```js
function daysFromToday(offset) {
  var d = new Date();
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() + offset);
  return d.toISOString().slice(0, 10); // YYYY-MM-DD
}

// 本週內、但相對今天尚未逾期的日期（今天或今天+1天，不超過本週週日）
function thisWeekDueSoon() {
  var today = new Date();
  today.setHours(0, 0, 0, 0);
  var range = getWeekRange(today);
  var tomorrow = new Date(today);
  tomorrow.setDate(tomorrow.getDate() + 1);
  var candidate = tomorrow.getTime() <= range.end.getTime() ? tomorrow : today;
  return candidate.toISOString().slice(0, 10);
}

var RECORDS = [
  // ...既有 completed 任務保留原樣（作為摘要列「已完成」對照組）...
  { project_name: "Project Alpha", task_name: "Initial setup", task_type: "功能", status: "completed", owner: "Alice", planned_completion_date: "2024-01-15", actual_completion_date: "2024-01-20", delay_days: 2 },
  { project_name: "Project Alpha", task_name: "Design phase", task_type: "調整", status: "completed", owner: "Bob", planned_completion_date: "2024-01-21", actual_completion_date: "2024-02-05", delay_days: 0 },
  { project_name: "Project Alpha", task_name: "Implementation", task_type: "功能", status: "completed", owner: "Charlie", planned_completion_date: "2024-02-06", actual_completion_date: "2024-02-20", delay_days: -3 },
  { project_name: "Project Alpha", task_name: "Overdue feature review", task_type: "功能", status: "in_progress", owner: "Alice", planned_completion_date: daysFromToday(-3), actual_completion_date: null, delay_days: null },   // 需求 7.1 逾期情境
  { project_name: "Project Alpha", task_name: "PR review backlog", task_type: "PR", status: "in_progress", owner: "Bob", planned_completion_date: thisWeekDueSoon(), actual_completion_date: null, delay_days: null },        // 需求 7.2 本週到期情境（PR 類型）
  { project_name: "Project Beta", task_name: "Requirements gathering", task_type: "臭蟲", status: "completed", owner: "David", planned_completion_date: "2024-02-01", actual_completion_date: "2024-02-10", delay_days: 1 },
  { project_name: "Project Beta", task_name: "Development", task_type: "功能", status: "in_progress", owner: "Eve", planned_completion_date: thisWeekDueSoon(), actual_completion_date: null, delay_days: null },             // 需求 7.2 本週到期情境
  { project_name: "Project Beta", task_name: "Testing", task_type: "遺漏", status: "pending", owner: "Frank", planned_completion_date: daysFromToday(10), actual_completion_date: null, delay_days: null },                   // 需求 7.3 未來情境
  { project_name: "Project Beta", task_name: "PR fix urgent", task_type: "PR", status: "in_progress", owner: "Eve", planned_completion_date: daysFromToday(-1), actual_completion_date: null, delay_days: null }              // 需求 7.1 逾期情境（PR 類型）
];
```

- 每個專案至少一筆 `task_type: "功能"` 與一筆 `task_type: "PR"`（需求 6.1）。
- `thisWeekDueSoon()` 挑今天或明天（取本週週日為上限），確保落在本週結束前但尚未逾期，用來與
  「已逾期」情境做出區別。

### 日期／篩選工具函式

```js
function getWeekRange(date) {
  var d = new Date(date);
  d.setHours(0, 0, 0, 0);
  var day = d.getDay(); // 0=Sun ... 6=Sat
  var mondayOffset = day === 0 ? -6 : 1 - day;
  var monday = new Date(d);
  monday.setDate(d.getDate() + mondayOffset);
  var sunday = new Date(monday);
  sunday.setDate(monday.getDate() + 6);
  sunday.setHours(23, 59, 59, 999);
  return { start: monday, end: sunday };
}

function isOverdue(task, today) {
  if (task.status === "completed" || !task.planned_completion_date) return false;
  return new Date(task.planned_completion_date) < today;
}

// 本週到期＝不晚於本週週日，不限下界（因此已逾期任務必為本週到期任務的子集）
function isDueByThisWeekEnd(task, weekRange) {
  if (task.status === "completed" || !task.planned_completion_date) return false;
  var d = new Date(task.planned_completion_date);
  return d <= weekRange.end;
}
```

- `isOverdue`／`isDueByThisWeekEnd` 對 `planned_completion_date` 為 `null` 一律回傳 `false`（需求 3.6）。
- `today` 與 `weekRange` 於每次 `render()` 呼叫時重新取得（避免長時間開啟頁面後日期過期）。

```js
function sortOverdueFirst(tasks, today) {
  return tasks.slice().sort(function (a, b) {
    var aOverdue = isOverdue(a, today) ? 0 : 1;
    var bOverdue = isOverdue(b, today) ? 0 : 1;
    return aOverdue - bOverdue; // 逾期（0）排在非逾期（1）之前，同組維持原順序（stable sort）
  });
}
```

- `buildTable` 渲染前，各專案的任務陣列先經 `sortOverdueFirst` 排序，逾期任務固定排在該專案清單最前面（需求 2.7）。`Array.prototype.sort` 於現代瀏覽器為 stable sort，故同為逾期或同為非逾期的任務彼此相對順序不變。

### 篩選與摘要

```js
function matchesProjectAndType(task, state) {
  if (state.project && task.project_name !== state.project) return false;
  // typeFilters 為空集合 = 不套用類型篩選（需求 6.6）
  if (state.typeFilters.length > 0 && state.typeFilters.indexOf(task.task_type) === -1) return false;
  return true;
}

function filterTasks(records, state, today, weekRange) {
  return records.filter(function (t) {
    if (!matchesProjectAndType(t, state)) return false;
    if (state.incompleteOnly && t.status === "completed") return false;
    if (state.scopeFilter === "overdue" && !isOverdue(t, today)) return false;
    if (state.scopeFilter === "due_this_week" && !isDueByThisWeekEnd(t, weekRange)) return false;
    return true;
  });
}

function computeSummary(records, state, today) {
  // 摘要列只套用「專案」與「任務類型」範圍（需求 4.4、6.7），不套用 incompleteOnly / scopeFilter
  var scoped = records.filter(function (t) { return matchesProjectAndType(t, state); });
  return {
    total: scoped.length,
    completed: scoped.filter(function (t) { return t.status === "completed"; }).length,
    in_progress: scoped.filter(function (t) { return t.status === "in_progress"; }).length,
    pending: scoped.filter(function (t) { return t.status === "pending"; }).length,
    overdue: scoped.filter(function (t) { return isOverdue(t, today); }).length
  };
}
```

### 渲染層擴充

- `buildTable(tasks)`：`COLUMNS` 新增 `{ key: "task_type", label: "類型" }`；狀態欄位改渲染
  `<span class="status-badge status-{{status}}">{{label}}</span>`；逾期任務的任務名稱欄位旁加
  `<span class="overdue-tag">逾期</span>`（需求 1.3）。
- `renderSummary(summary)`：於 `#content` 之前的新增區塊 `#summary`，顯示 5 個統計數字（需求 4.1）。
- `populateProjectSelect()`：選項文字改為 `"{{project}}（{{count}}）"`，「全部專案」選項為
  `"全部專案（{{total}}）"`（需求 5.1、5.2）。
- `initTypeFilter()`：讀取 `RECORDS` 內所有 `task_type` 唯一值，依 `PRIORITY_TYPES = ["功能", "PR"]`
  排序（優先類型在前，其餘依原順序排列在後），為每個值渲染一個 checkbox（多選，需求 6.3）；初始
  勾選狀態依 `state.typeFilters`（預設 `["功能", "PR"]`）決定，`change` 事件將該值加入／移出
  `state.typeFilters` 陣列後呼叫 `render()`。
- `initScopeFilter()` / `initIncompleteToggle()`：一組 radio（全部／本週到期／已逾期，預設勾選
  「本週到期」）與一個 checkbox（只顯示未完成，預設勾選），事件處理器更新 `state` 並呼叫 `render()`。
- 專案區塊於篩選後為空時，顯示「目前無符合條件的任務」而非隱藏整個區塊標題（需求 2.4）。

---

## Data Models

任務紀錄新增欄位：

| 欄位名稱    | 類型   | 說明                              |
|-------------|--------|-----------------------------------|
| `task_type` | String | 任務類型：`"功能"` \| `"PR"` \| `"調整"` \| `"遺漏"` \| `"臭蟲"` |

---

## Error Handling

- `planned_completion_date` 為 `null` 的任務：於「本週到期」「已逾期」篩選中一律排除（需求 3.6），
  但仍計入摘要列的「任務總數」與其狀態計數。
- 篩選後專案區塊為空：顯示提示文字而非拋出例外或留白（需求 2.4）。

---

## Testing Strategy（手動驗證，符合 karpathy-guidelines 可驗證標準）

由於 `docs/` 靜態站不使用建置工具或測試框架，本 spec 以手動瀏覽器驗證為主，每項對應需求：

1. 開啟 `docs/index.html`，確認專案下拉選單預設為「全部專案」（需求 2.8），摘要列顯示 5 個數字且總數等於「功能＋PR」兩類任務筆數。
2. 切換專案下拉選單，確認摘要列數字與下拉選單顯示的任務數一致（需求 4.2、5.1）。
3. 確認「只顯示未完成」預設為勾選、已完成任務未顯示（需求 2.6）；關閉後確認已完成任務出現，切換專案後確認開關狀態仍保留（需求 2.2、2.3、2.5）。
3a. 確認任一專案區塊內，若同時有逾期與非逾期的未完成任務，逾期任務排列在該區塊清單最上方（需求 2.7）。
4. 確認範圍篩選預設勾選「本週到期」（需求 3.7），畫面僅顯示不晚於本週週日、未完成的任務（含所有已逾期任務）。切換為「已逾期」，確認僅顯示 `planned_completion_date` 早於今天且未完成的任務，且該任務列有「逾期」標示（需求 3.3、1.3）。切換為「全部」，確認任務列增加。
5. 確認任務類型篩選預設勾選「功能」與「PR」（需求 6.4）；取消勾選其一，確認對應類型任務消失；全部取消勾選後，確認視為不套用類型篩選、顯示所有類型（需求 6.6）；加選其他類型，確認任務列相應增加。
6. 縮小視窗至手機寬度，確認新增欄位（類型、狀態 badge）與新控制項（多選 checkbox、單選 radio）在卡片版型下仍正常顯示、不破版（響應式設計，steering 規範）。
7. 確認狀態標籤在無色覺情況下（例如切換瀏覽器灰階模式）仍可透過文字辨識狀態（需求 1.2）。
