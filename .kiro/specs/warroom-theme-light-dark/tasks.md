# Implementation Plan: 戰情室深色／淺色主題切換

## Overview

為 `docs/index.html`（靜態站）與 `warroom-data-api-prototype`（Rails）兩處既有 Dashboard，
將寫死色碼改為 CSS 變數，新增 Theme_Toggle 按鈕與 `localStorage` 記憶邏輯。兩處實作平行、
互不依賴，可分別開發與驗證。每項任務均可獨立完成並於瀏覽器手動驗證後 Commit。

---

## Tasks

- [x] 1. CSS 變數基礎（`docs/` 靜態站）
  - [x] 1.1 於 `docs/css/style.css` 頂部新增 `:root` 深色變數與 `html[data-theme="light"]` 淺色變數
    - 依 [design.md](design.md) 的「CSS 變數規格」定義兩組變數，此步驟先只新增變數，不動既有規則
    - _需求：3.2, 5.1_
  - [x] 1.2 將既有規則的寫死色碼改為 `var(--xxx)`
    - 依 design.md「既有樣式規則改寫對照表」逐一替換 body／`.stat-item`／`table.project-tasks`／
      badge／`.overdue-tag`／`.delay-negative`／`.delay-positive` 等色碼
    - 額外調整（使用者追加需求，超出原 design.md 範圍）：同步套用目前 `warroom-data-api-prototype`
      的視覺樣式（卡片式 `.project-block`、實心 badge 底色、`.apply-filters-btn`、自訂下拉選單箭頭、
      table hover、標題列 `space-between` 排版），細節見下方 Notes
    - _需求：2.1, 3.2_

- [x] 2. Theme_Toggle 與切換邏輯（`docs/` 靜態站）
  - [x] 2.1 於 `docs/index.html` 的 `<head>` 加入防閃爍內聯 script
    - 依 design.md「避免 FOUC」段落加入同步 script，讀取 `localStorage["warroom-theme"]`
    - _需求：4.2, 4.3_
  - [x] 2.2 於 `.dashboard-header` 新增 `#theme-toggle` 按鈕
    - HTML 結構依 design.md「Theme_Toggle 按鈕」段落
    - _需求：1.1_
  - [x] 2.3 於 `docs/js/app.js` 新增 `getCurrentTheme` / `applyThemeToggleLabel` / `toggleTheme`
    - 依 design.md 對應程式碼；`DOMContentLoaded` 內呼叫 `applyThemeToggleLabel` 並綁定按鈕 `click`
    - `localStorage` 讀寫以 `try/catch` 包裹
    - _需求：1.2, 1.3, 1.4, 4.1, 4.3_
  - [x] 2.4 新增 `.theme-toggle` 樣式
    - 使用既有變數（`--color-surface`／`--color-border`／`--color-text`），確保深淺主題下皆可讀
    - _需求：1.1_

- [x] 3. 檢查點 — `docs/` 靜態站驗證
  - 依 [design.md](design.md) Testing Strategy 第 1–7 項於瀏覽器手動驗證通過（僅需驗證 `docs/index.html`）
  - **狀態**：使用者已於瀏覽器實際開啟 `docs/index.html` 驗證通過。

- [ ] 4. CSS 變數基礎（`warroom-data-api-prototype`）
  - [ ] 4.1 於 `app/assets/stylesheets/application.css` 頂部新增相同的深色／淺色變數組
    - 數值須與 `docs/css/style.css` 完全一致（需求 5.1）
    - _需求：3.2, 5.1_
  - [ ] 4.2 將既有規則的寫死色碼改為 `var(--xxx)`
    - 對照 `docs/` 的替換表，套用到 `application.css` 對應選擇器（`.dashboard-title`／
      `.stat-item`／`table.project-tasks`／badge／`.overdue-tag`／delay 色等）
    - _需求：2.1, 3.2_

- [ ] 5. Theme_Toggle 與切換邏輯（`warroom-data-api-prototype`）
  - [ ] 5.1 於 `application.html.erb` 的 `<head>` 加入與 `docs/` 相同邏輯的防閃爍內聯 script
    - _需求：4.2, 4.3_
  - [ ] 5.2 於 `dashboard/index.html.erb` 的 `.dashboard-header` 新增 `#theme-toggle` 按鈕
    - 放置於標題列右側，外觀與 `docs/` 版本一致（需求 5.2）
    - _需求：1.1_
  - [ ] 5.3 新增 `app/javascript/theme_toggle.js`（經 importmap 引入）
    - 內容對應 `docs/js/app.js` 的三個函式與事件綁定，`localStorage` key 沿用 `"warroom-theme"`
    - _需求：1.2, 1.3, 1.4, 4.1, 4.3_
  - [ ] 5.4 新增 `.theme-toggle` 樣式（沿用 `application.css` 內既有變數）
    - _需求：1.1_

- [ ] 6. 檢查點 — `warroom-data-api-prototype` 驗證
  - 依 [design.md](design.md) Testing Strategy 第 1–7 項於瀏覽器手動驗證通過（僅需驗證 Rails `dashboard#index`）

- [ ] 7. 最終檢查點 — 兩站一致性驗證
  - 依 [design.md](design.md) Testing Strategy 第 8 項，並排比對兩處實作的配色與 Theme_Toggle 外觀／位置，確認一致（需求 5.1, 5.2）

---

## Notes

- 兩處實作互相獨立，可任選順序開發（任務 1–3 與任務 4–6 之間無相依性），但變數數值須保持一致（需求 5.1）
- 每項任務參照對應需求編號以利追溯
- 依 karpathy-guidelines：每項工作開始前先確認可驗證標準（對照本檔任務描述與 [design.md](design.md) Testing Strategy），完成後才勾選

### `docs/` 視覺同步 Rails 樣式（使用者於任務 1 執行期間追加的範圍）

- `docs/css/style.css` 的元件視覺（卡片式 `.project-block`＋hover 邊框、實心 badge 底色、
  `.apply-filters-btn`、下拉選單自訂箭頭、表格 hover 列、標題列改 `space-between` 排版）已對齊
  `warroom-data-api-prototype/app/assets/stylesheets/application.css` 目前樣式。
- **刻意保留、未跟 Rails 對齊的部分**：手機寬度（≤560px）沿用 `docs/` 原本的「表格轉卡片堆疊」
  版型，而非 Rails 的橫向捲動表格 — 前者是既有較佳的行動裝置體驗，改成 Rails 的橫向捲動屬於體驗
  退步，因此不跟進。
- `docs/index.html` 新增的「套用篩選」按鈕（`#apply-filters`）為**視覺對齊**用途：`docs/` 無伺服器
  可送出表單，點擊僅呼叫既有 `render()`（等同各欄位 `change` 事件已即時觸發的行為），不做頁面重載，
  篩選仍維持即時生效。
- Rails 端（任務 4–5，尚未開始）套用同一套需求時，仍以 `warroom-data-api-prototype` 現況為準即可，
  不需再從 `docs/` 回頭同步。

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "4.1"] },
    { "id": 1, "tasks": ["1.2", "4.2"] },
    { "id": 2, "tasks": ["2.1", "2.2", "5.1", "5.2"] },
    { "id": 3, "tasks": ["2.3", "5.3"] },
    { "id": 4, "tasks": ["2.4", "5.4"] },
    { "id": 5, "tasks": ["3", "6"] },
    { "id": 6, "tasks": ["7"] }
  ]
}
```
