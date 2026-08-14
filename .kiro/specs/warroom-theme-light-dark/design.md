# 設計文件

## Overview

本 spec 在兩個既有 Dashboard 實作上，將目前寫死的深色色碼改為 CSS 自訂屬性（CSS Custom
Properties／變數），並新增一顆主題切換鈕，透過 `<html>` 根元素上的 `data-theme` 屬性切換
淺色／深色配色。兩處實作各自獨立套用相同的視覺規格：

1. `docs/` 靜態站：`index.html`、新增 `css/theme.css`（變數定義）、`js/app.js` 內新增切換邏輯。
2. `warroom-data-api-prototype`：`application.html.erb`、`application.css`（變數定義 + 既有
   規則改用變數）、新增一小段原生 JS（放在 view 或 `app/javascript` 中，依 Rails 慣例）。

不改動任何任務資料存取、篩選、摘要邏輯；不引入建置工具或前端框架。

---

## Architecture

### 避免 FOUC（Flash of Unstyled Content）

主題屬性必須在瀏覽器渲染 `<body>` 之前就決定好，否則會先閃一次深色再切換成淺色。做法：
在 `<head>` 內、CSS 載入之前，放一段**同步（非 `defer`／`async`）內聯 `<script>`**，讀取
`localStorage`，立即把 `data-theme` 屬性設到 `<html>` 上：

```html
<script>
  (function () {
    try {
      var saved = localStorage.getItem("warroom-theme");
      if (saved === "light") {
        document.documentElement.setAttribute("data-theme", "light");
      }
      // 沒有已儲存值，或值不是 "light" → 不設屬性，CSS :root 預設即為深色（需求 3.1）
    } catch (e) {
      // localStorage 不可用 → 靜默忽略，維持預設深色（需求 4.3）
    }
  })();
</script>
```

- `docs/index.html`：此段內聯 script 直接寫在 `<head>` 內，CSS `link` 標籤之後即可（因為只是
  設屬性，不依賴樣式）。
- `warroom-data-api-prototype`：同樣的內聯 script 放進 `application.html.erb` 的 `<head>`
  區塊（`<%= yield :head %>` 之前或之後皆可，只需早於 `</head>`）。

### 切換流程

```
使用者點擊 Theme_Toggle
    │
    ▼
toggleTheme()
    ├─ 讀目前 document.documentElement.dataset.theme（"light" 或 undefined＝深色）
    ├─ 計算下一個主題值
    ├─ 設定 document.documentElement.setAttribute("data-theme", next)
    ├─ 更新 Theme_Toggle 按鈕文字／aria-label（需求 1.2）
    └─ try { localStorage.setItem("warroom-theme", next) } catch (e) { /* 忽略，需求 4.3 */ }
```

`data-theme` 屬性變更後，CSS 透過屬性選擇器立即套用對應變數，不需 JS 逐一改動元素樣式
（需求 1.3：既有元件內容與互動狀態不受影響，因為 DOM 結構完全沒變，只變 CSS 變數值）。

---

## CSS 變數規格（兩處實作共用相同數值，需求 5.1）

深色（預設，定義在 `:root`，不需屬性即套用，對應需求 3.1／3.2 與現況一致）：

```css
:root {
  --color-bg: #0f1117;
  --color-surface: #1a202c;
  --color-border: #2d3748;
  --color-text: #e2e8f0;
  --color-text-strong: #f7fafc;
  --color-text-muted: #a0aec0;
  --color-text-faint: #718096;
  --color-accent: #63b3ed;

  --badge-completed-bg: rgba(104, 211, 145, 0.15);
  --badge-completed-text: #68d391;
  --badge-progress-bg: rgba(99, 179, 237, 0.15);
  --badge-progress-text: #63b3ed;
  --badge-pending-bg: rgba(160, 174, 192, 0.2);
  --badge-pending-text: #cbd5e0;
  --overdue-bg: rgba(252, 129, 129, 0.15);
  --overdue-text: #fc8181;

  --delay-negative: #68d391;
  --delay-positive: #fc8181;
}
```

淺色（`html[data-theme="light"]` 覆寫，數值皆通過 WCAG AA 4.5:1 對比度檢查，對應需求 2.1／2.2）：

```css
html[data-theme="light"] {
  --color-bg: #f7fafc;
  --color-surface: #ffffff;
  --color-border: #cbd5e0;
  --color-text: #1a202c;
  --color-text-strong: #171923;
  --color-text-muted: #4a5568;
  --color-text-faint: #64748b;
  --color-accent: #2b6cb0;

  --badge-completed-bg: #c6f6d5;
  --badge-completed-text: #22543d;
  --badge-progress-bg: #bee3f8;
  --badge-progress-text: #2c5282;
  --badge-pending-bg: #e2e8f0;
  --badge-pending-text: #4a5568;
  --overdue-bg: #fed7d7;
  --overdue-text: #9b2c2c;

  --delay-negative: #2f855a;
  --delay-positive: #c53030;
}
```

淺色主題的狀態 badge／逾期標示改用**不透明淺色底 + 深色文字**（而非沿用深色主題的半透明疊色），
因為半透明疊色在白底上會過淡、文字對比不足（需求 2.2）。

> **修正記錄**：`--color-text-faint` 淺色值最初沿用深色主題的 `#718096`，經 code review 用
> WCAG 對比度公式核算，對白色背景（`--color-surface: #ffffff`）僅約 4.02:1，未達需求 2.2 的
> 4.5:1 門檻（影響 `table.project-tasks th`／Rails `.empty-state`）。已改為 `#64748b`
> （對白底約 4.76:1，通過 AA），兩處實作同步修正。

### 既有樣式規則改寫對照（兩檔案皆比照辦理）

實作時另外新增了一些本表未列出的工具變數（如 `--color-border-hover`、`--btn-text`、
`--table-row-border`、`--table-row-hover-bg`、`--color-accent-strong`、`--select-arrow`、
Rails 專屬的 `--error-*`），用途皆為既有樣式規則的直接色碼替換，不影響本節列出的核心對照關係。

| 既有寫死色碼 | 改用變數 |
|---|---|
| `background: #0f1117`（body） | `background: var(--color-bg)` |
| `color: #e2e8f0`（body） | `color: var(--color-text)` |
| `#1a202c`（`.stat-item`／`select`／`table.project-tasks`） | `var(--color-surface)` |
| `#718096`（`table th`） | `var(--color-text-faint)` |
| `#2d3748`（各邊框） | `var(--color-border)` |
| `#a0aec0`（`.subtitle`／`.stat-label`／legend） | `var(--color-text-muted)` |
| `#f7fafc`（標題／`.stat-value`） | `var(--color-text-strong)` |
| `#63b3ed`（header span） | `var(--color-accent)` |
| `.status-completed` 背景／文字 | `var(--badge-completed-bg)` / `var(--badge-completed-text)` |
| `.status-in_progress` 背景／文字 | `var(--badge-progress-bg)` / `var(--badge-progress-text)` |
| `.status-pending` 背景／文字 | `var(--badge-pending-bg)` / `var(--badge-pending-text)` |
| `.overdue-tag` 背景／文字 | `var(--overdue-bg)` / `var(--overdue-text)` |
| `.delay-negative` / `.delay-positive` | `var(--delay-negative)` / `var(--delay-positive)` |

不改動排版相關屬性（padding、border-radius、flex、media query 斷點），僅替換色碼，確保
需求 2.4（響應式版型不受影響）。

---

## Components and Interfaces

### Theme_Toggle 按鈕

放置於 `.dashboard-header` 內，標題右側（需求 5.2）：

```html
<button type="button" id="theme-toggle" class="theme-toggle" aria-label="切換至淺色模式">
  🌙 深色
</button>
```

- 按鈕文字／`aria-label` 依目前主題動態更新：深色時顯示「🌙 深色」＋`aria-label="切換至淺色模式"`；
  淺色時顯示「☀️ 淺色」＋`aria-label="切換至深色模式"`（需求 1.2）。
- 原生 `<button>` 元素天生支援 Tab 聚焦與 Enter／Space 觸發，滿足需求 1.4，不需額外 JS 處理鍵盤事件。
- 樣式沿用 `var(--color-surface)` / `var(--color-border)` / `var(--color-text)`，深淺主題下皆可讀。

### `docs/js/app.js` 新增函式

```js
var THEME_KEY = "warroom-theme";

function getCurrentTheme() {
  return document.documentElement.getAttribute("data-theme") === "light" ? "light" : "dark";
}

function applyThemeToggleLabel(theme) {
  var btn = document.getElementById("theme-toggle");
  if (!btn) return;
  if (theme === "light") {
    btn.textContent = "☀️ 淺色";
    btn.setAttribute("aria-label", "切換至深色模式");
  } else {
    btn.textContent = "🌙 深色";
    btn.setAttribute("aria-label", "切換至淺色模式");
  }
}

function toggleTheme() {
  var next = getCurrentTheme() === "light" ? "dark" : "light";
  if (next === "light") {
    document.documentElement.setAttribute("data-theme", "light");
  } else {
    document.documentElement.removeAttribute("data-theme");
  }
  applyThemeToggleLabel(next);
  try {
    localStorage.setItem(THEME_KEY, next);
  } catch (e) {
    // 忽略：localStorage 不可用時僅本次瀏覽切換有效（需求 4.3）
  }
}

// DOMContentLoaded 內：
// applyThemeToggleLabel(getCurrentTheme());
// document.getElementById("theme-toggle").addEventListener("click", toggleTheme);
```

`warroom-data-api-prototype` 側以等效的原生 JS 實作相同函式（放在
`app/javascript/theme_toggle.js`，經 importmap 引入），行為與命名邏輯一致，`localStorage` key
可沿用同一字串 `"warroom-theme"`（不影響需求 4.4，因兩者網域本就不同、天然隔離）。

---

## Data Models

不涉及任務資料模型變更。新增的唯一「資料」是瀏覽器端狀態：

| 儲存位置 | Key | 值 |
|---|---|---|
| `localStorage`（各自網域獨立） | `warroom-theme` | `"light"`（顯式儲存）；未儲存或非 `"light"` 一律視為深色 |

---

## Error Handling

- `localStorage.getItem` / `setItem` 拋出例外（例如瀏覽器隱私模式限制、使用者停用）：以
  `try/catch` 攔截，不影響主題切換本身在當次瀏覽中的行為，僅無法跨重新整理保留（需求 4.3）。
- `theme-toggle` 按鈕元素不存在（理論上不會發生，防禦性判斷）：`applyThemeToggleLabel` 提前
  return，不拋出例外。

---

## Testing Strategy（手動驗證，符合 karpathy-guidelines 可驗證標準）

兩處實作（`docs/index.html` 與 Rails `dashboard#index`）皆需分別驗證以下項目：

1. 開啟頁面（清空該網域 `localStorage`），確認預設為深色主題，畫面配色與重構前完全一致（需求 3.1、3.2）。
2. 點擊 Theme_Toggle，確認立即切換為淺色，背景、卡片、表格、篩選控制項、狀態 badge、逾期標示、delay 正負色皆同步變化，且任務列表內容、目前篩選狀態不受影響（需求 1.3、2.1）。
3. 用瀏覽器內建無障礙面板或線上對比度工具，檢查淺色主題下本文文字與背景、badge 文字與底色的對比度皆 ≥ 4.5:1（需求 2.2）。
4. 確認 Theme_Toggle 按鈕文字與 `aria-label` 隨主題正確更新；以鍵盤 Tab 聚焦按鈕、按 Enter 觸發切換，確認可正常運作（需求 1.2、1.4）。
5. 切換至淺色後重新整理頁面，確認畫面直接以淺色渲染、無深色閃爍（開啟瀏覽器 Network 節流或肉眼觀察）（需求 4.1、4.2）。
6. 於瀏覽器開發者工具停用／清空 `localStorage` 存取權限（或以無痕模式搭配封鎖網站資料），確認切換仍可運作、不拋出 JavaScript 錯誤，僅重新整理後會回到預設深色（需求 4.3）。
7. 縮小視窗至手機寬度（560px 以下），分別在深色與淺色主題下確認卡片化表格版型正常、不破版（需求 2.4）。
8. 並排比對 `docs/index.html` 與 Rails 版本的深色／淺色配色、Theme_Toggle 位置與外觀，確認視覺一致（需求 5.1、5.2）。
