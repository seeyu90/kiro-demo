# Implementation Plan: 305/306/307 優化（bug 修正 + 快取 + 視覺體驗）

## Overview

起因是 305「只顯示未完成」checkbox 取消勾選沒有作用的回報，順勢盤點三個 Dashboard 頁面
（305 專案進度、306 臭蟲議題、307 人時燃盡追蹤）共通的快取與載入體驗，並用 Playwright
搭配真實 Google Sheets 資料實際截圖三個頁面，依畫面呈現提出後續優化方向。

任務 1–4 已於本分支（`claude/warroom-dashboard-optimization`）實作完成；任務 5 是使用者看過
307 實際截圖後，覺得燃盡圖「不易理解、不確定用途」而提出的重新設計，改成狀態表為主、圖表為輔；
任務 6 是使用者要求三頁篩選都加時間區間，屬於下一輪規劃，尚未動工。

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

- [x] 4. 307 議題燃盡狀態改成「狀態摘要表 + 收合式趨勢圖」
  - 起因：使用者看過 `/burndown` 真實截圖後反饋「資料呈現很難懂，不知道有什麼用途」；
    原設計是敏捷燃盡圖（理想線／實際線疊圖、剩餘人時可為負值），對不熟悉這套圖表語言的人
    門檻偏高，且資料點稀疏的議題仍佔滿整張圖表高度，6 個「進行中」議題就撐出 6480px 高的
    頁面（見前版截圖）
  - [x] 4.1 `BurndownHelper` 新增燈號與人時欄位計算
    - `burndown_status(issue)`：比較「最新一週實際剩餘人時」與「理想線同一天應剩餘人時」
      的落差，換算成佔預估人時的比例（相對值而非絕對小時數），分三檔：🟢正常
      （落差 ≤ 5%）／🟡略慢（≤ 25%）／🔴超支（> 25%）；estimated_hours 為 0 或序列缺資料
      時回傳「資料不足」
    - 剩餘人時本身已是負值（花費超過整份預估）時一律強制判定超支，不看理想線落差（負值
      落差原本會被誤判為「領先進度」，見 `spec/helpers/burndown_helper_spec.rb` 的迴歸測試）
    - `burndown_remaining_hours`／`burndown_consumed_hours`：優先採用試算表 PM 手動填寫的
      `reported_remaining_hours`，缺漏才退回 `actual_series` 最新一筆推算
    - `app/helpers/burndown_helper.rb:114-158`
  - [x] 4.2 View 改版：`app/views/burndown/index.html.erb`
    - 議題燃盡狀態改為表格（議題／負責人／預估人時／已消耗／剩餘／燈號），一眼掃過所有
      議題找出誰卡住了
    - 每一列本身就是 `<details>`：點整列（不是另外的連結）就在原地展開該議題的燃盡圖／
      堆疊圖，不需要跳到頁面下方另一個區塊——第一版做成表格 + 「查看趨勢圖 ↓」錨點連結
      跳到頁尾另一份收合清單，使用者反饋這樣沒有直覺（為什麼不是點列表就顯示），改成
      列本身可展開
    - CSS 新增 `.status-on_track/.status-at_risk/.status-over/.status-unknown` 燈號樣式與
      `.burndown-status-table/.burndown-status-row/.burndown-status-details` 系列樣式
      （`app/assets/stylesheets/application.css`）；`<summary>` 內層用一個額外的
      `.burndown-status-row` grid 容器包住 6 個欄位，展開箭頭（▸/▾）放在 summary 本身用
      flex 排版，避免 `::before` 被當成 grid item 擠壓欄位、跟表頭對不齊
  - [x] 4.3 測試更新
    - 新增 `spec/helpers/burndown_helper_spec.rb`（10 案例，含負值剩餘的迴歸測試）
    - `spec/requests/burndown_spec.rb` 既有斷言改配合新標題「議題燃盡狀態」
      （原「議題燃盡圖」），319/319 全過
    - Playwright 截圖驗證兩輪：第一版（表格＋頁尾收合清單）與改版後（點列原地展開）皆
      實際截圖確認，頁面高度從 6480px 降到約 600px（全部收合時），點列展開後圖表正確
      顯示在該列正下方、欄位對齊不跑版，狀態燈號經真實資料驗證（含超支案例）

- [ ] 5. 305／306／307 篩選加上時間區間設定（本年度／本月／多個月）
  - 起因：使用者希望三個頁面的篩選條件都能設定時間區間，例如「今年度」「當月」或「多個
    月份」，而不是現在各頁各自不同的日期篩選邏輯
  - 現況盤點（下一輪動工前需要先確認，三頁目前的日期篩選語意互不相同，不是單純複製貼上）：
    - 305（`/dashboard`）：`scope` 單選（全部／本週到期含逾期／已逾期），無「年度」或
      「月份」概念，資料本身只到「本年度」試算表（見 `PROJECT_PROGRESS_SPREADSHEET_ID`
      環境變數，每年換一份新試算表，本來就無法跨年查詢）
    - 306（`/issues`）：`月度 KPI` 分頁已有單一月份下拉（`app/views/issues/index.html.erb`），
      但只能選一個月，不支援「多個月」或「本年度」彙總
    - 307（`/burndown`）：目前完全沒有時間篩選，只有專案／人員／狀態；資料來源是「單一
      年度分頁」（`BURNDOWN_SHEET_NAME`），同樣無法跨年查詢，但年度內的週欄位範圍可以做
      「本月」「多個月」篩選（依週欄位日期篩選 `actual_series`／`ideal_series` 的顯示範圍）
  - 待確認方向：
    - 「本年度」在 305/307 現有架構下本來就等於「不篩選」（資料本身按年度分表），是否還
      需要在 UI 上放一個形式上的「本年度」選項，或只需要「本月」「多個月」兩種
    - 306 的「多個月」是否要做成彙總（加總多個月的 KPI）還是趨勢圖延伸涵蓋範圍
    - UI 統一走同一種元件（例如月份多選下拉、或起訖日期兩個 `date` input）還是各頁維持
      現有元件、只是加一個共用的時間區間 partial
  - _尚未實作，需先與使用者確認上述待確認方向，再排入下一輪任務拆解_

---

## Notes

- 三個頁面（305/306/307）目前快取策略已一致：`Rails.cache.fetch` + 5 分鐘 TTL，快取鍵
  皆含各自的試算表 ID（307 另含年度分頁名稱）
- 本機／新 worktree 驗證步驟需要 `config/credentials/development.key`（見
  `warroom-data-api-prototype/README.md` 「在新的 git worktree 開發」段落），該檔案已
  `.gitignore`，需從既有 checkout 複製
- 任務 5（時間區間篩選）待與使用者確認 305/306/307 各自的日期篩選語意後，才拆解成可執行的
  子任務；三頁目前的「年度」概念都綁在資料來源分頁／試算表上，不是單純的 UI 元件問題
