# Implementation Plan: 305/306/307 優化（bug 修正 + 快取 + 視覺體驗）

## Overview

起因是 305「只顯示未完成」checkbox 取消勾選沒有作用的回報，順勢盤點三個 Dashboard 頁面
（305 專案進度、306 臭蟲議題、307 人時燃盡追蹤）共通的快取與載入體驗，並用 Playwright
搭配真實 Google Sheets 資料實際截圖三個頁面，依畫面呈現提出後續優化方向。

任務 1–3 已於本分支（`claude/warroom-dashboard-optimization`）實作完成；任務 4 是這次截圖
複查後發現的新項目，尚未動工。

---

## Tasks

- [x] 1. 修正 305「只顯示未完成」取消勾選無效的 bug
  - [x] 1.1 `index.html.erb` 的 `incomplete_only` checkbox 補上隱藏欄位
    - 根因：`check_box_tag` 未勾選時瀏覽器不會送出該參數，Controller 用
      `params[:incomplete_only] != "0"` 判斷，`nil != "0"` 恆為 true，取消勾選形同無效
    - 比照同表單 `task_type[]` 既有作法（`app/views/dashboard/index.html.erb:23`），在
      checkbox 前加 `<input type="hidden" name="incomplete_only" value="0">`
    - `app/views/dashboard/index.html.erb:39-44`
    - _驗證：`bundle exec rspec spec/requests/dashboard_spec.rb` 17/17 全過_

- [x] 2. 篩選送出時的轉圈圈 loading 動畫
  - [x] 2.1 `turbo-frame[busy]` 加上 CSS 轉圈圈（取代原本只有淡化灰底）
    - 純 CSS `::after` 偽元素 + `@keyframes spin`，不需額外 JS/Stimulus
    - 選擇器為通用 `turbo-frame[busy]`，305（`project-content`）、306
      （`issue-content`）、307（`burndown-content`）三個頁面同時生效
    - `app/assets/stylesheets/application.css:308-333`

- [x] 3. `BurndownSheetsClient`（307）補上快取
  - [x] 3.1 `fetch_rows` 包一層 `Rails.cache.fetch`，比照 305/306 既有作法
    - 快取鍵含 `SPREADSHEET_ID` 與 `SHEET_NAME`（年度分頁切換時不會誤用舊分頁快取），
      TTL 沿用 5 分鐘
    - `app/clients/burndown_sheets_client.rb:20-33`
    - 新增快取命中測試：`spec/clients/burndown_sheets_client_spec.rb`
      「caches the result so a second call within the TTL does not hit the API again」
    - _驗證：`bundle exec rspec` 308/308 全過_
    - 盤點結論：305、306 皆已有快取，307 是唯一遺漏的一個，已補齊，三頁快取策略一致

---

## 截圖複查發現（Playwright + 真實 Google Sheets 資料，1400×1000 viewport）

用 `.kiro/specs/warroom-dashboard-optimization/README` 開發流程截圖 `/dashboard`、
`/issues`、`/burndown` 三頁，觀察到的視覺／資料呈現問題：

- [ ] 4. 307 燃盡圖：資料點稀疏的議題仍佔滿整張圖表高度，頁面過長
  - 現象：`/burndown` 預設篩選「狀態：進行中」時，剛開案、只有 1 個資料點的議題（例如
    「亞炬 Wms／整合 RFID 標籤」）Y 軸範圍幾乎是 0～1，畫面上幾乎全空白，但仍套用跟
    資料完整的議題相同的固定圖表高度（`BurndownHelper::BURNDOWN_HEIGHT = 250` viewBox，
    實際渲染 ~450px 高，見 `app/helpers/burndown_helper.rb:5-10`）
    - 每個議題有 2 張圖（燃盡圖 + 各人員累積人時堆疊圖），目前 6 個「進行中」議題就撐出
      6480px 高的頁面，資料點少的議題讓使用者要捲動過一大片幾乎空白的圖表才能看到下一個
      議題
  - 建議方向：資料點數低於某門檻（例如 ≤ 1 個實際資料點）時，改用精簡的文字摘要卡片
    （議題名稱＋「剛開案，尚無足夠資料繪圖」＋預估人時），取代滿版空白圖表；有足夠資料點
    再顯示完整燃盡圖
  - 待確認：門檻值（資料點數）與精簡卡片的呈現方式，需與使用者確認後再排入下一輪任務
  - _相關檔案：`app/views/burndown/_burndown_chart.html.erb`、
    `app/views/burndown/_burndown_stacked_chart.html.erb`、`app/helpers/burndown_helper.rb`_

---

## Notes

- 三個頁面（305/306/307）目前快取策略已一致：`Rails.cache.fetch` + 5 分鐘 TTL，快取鍵
  皆含各自的試算表 ID（307 另含年度分頁名稱）
- 本機／新 worktree 驗證步驟需要 `config/credentials/development.key`（見
  `warroom-data-api-prototype/README.md` 「在新的 git worktree 開發」段落），該檔案已
  `.gitignore`，需從既有 checkout 複製
- 任務 4 是本次截圖複查的產出，屬於下一輪待確認項目，尚未實作
