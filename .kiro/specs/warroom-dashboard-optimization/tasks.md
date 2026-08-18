# Implementation Plan: 305/306/307 優化（bug 修正 + 快取 + 視覺體驗）

## Overview

起因是 305「只顯示未完成」checkbox 取消勾選沒有作用的回報，順勢盤點三個 Dashboard 頁面
（305 專案進度、306 臭蟲議題、307 人時燃盡追蹤）共通的快取與載入體驗，並用 Playwright
搭配真實 Google Sheets 資料實際截圖三個頁面，依畫面呈現提出後續優化方向。

任務 1–6 已於本分支（`claude/warroom-dashboard-optimization`）實作完成；任務 5 是使用者看過
307 實際截圖後，覺得燃盡圖「不易理解、不確定用途」而提出的重新設計，改成狀態表為主、圖表為輔，
過程中又經過兩次迭代（合併圖表、每人各自理想線）；任務 6 是 305 篩選列的視覺對齊修正；任務 7
是使用者要求三頁篩選都加時間區間，屬於下一輪規劃，尚未動工。

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

- [x] 5. 307 燃盡圖表兩次迭代：合併圖表 → 每人各自理想線＋並排長條
  - [x] 5.1 燃盡折線圖＋人員堆疊面積圖合併成單一長條＋雙軸線圖
    - 起因：使用者反饋「各人員累積消耗人時」堆疊圖只看得出誰花的人時多，看不出誰進度
      落後——份量本來就不一樣，花得多可能只是負責範圍大；另外參考使用者提供的週別長條＋
      累積線範例圖
    - 長條＝每人當週實際消耗人時（左軸），線＝議題整體累積消耗人時（虛線理想／實線實際，
      右軸），兩軸共用同一段繪圖高度、數值範圍不同（`burndown_chart_y` 本身就是通用的
      value/min/max 映射，兩個軸都能重用，不用另外寫一套）
    - 長條在資料週數很少時，兩端的長條會有一半寬度伸出繪圖區域跟軸刻度文字重疊，
      `burndown_combo_bars` 內 clamp 在繪圖區域內
    - 移除舊的 `_burndown_chart.html.erb`／`_burndown_stacked_chart.html.erb` 與專屬的
      `burndown_chart_range`／`burndown_stacked_chart_*` helper 方法，改用新的
      `_burndown_combo_chart.html.erb`
  - [x] 5.2 使用者進一步要求「三條預估線＋各自的直方圖」：長條改成並排（非堆疊），
    理想線從「議題整體共用一條」改成「每人各自一條」
    - 新增 `burndown_per_assignee_ideal_series`：每人自己的理想累積軌跡，用同一份議題的
      開案／完成日期換算時間比例，乘上這個人自己的預估人時（跟 `burndown_per_assignee_status`
      同一套公式，只是這裡算出整條線而非只算最新一點）
    - `burndown_combo_bars` 改成並排長條（`slot_width` 依人數均分），`burndown_combo_bar_max`
      改成取「單一根長條」的最高單週人時（不是堆疊時的加總）
    - `burndown_combo_line_max` 簽名改成接受多條序列的陣列（`series_list`, `extra_values`），
      因為現在是 N 個人各自一組理想／實際線，不是固定兩條
    - 線的顏色改用 inline `stroke` 屬性（跟長條同一份 `BURNDOWN_STACK_COLORS` 色盤），不用
      CSS class 固定顏色，才能讓同一人的理想線／實際線／長條顏色一致，方便比對
    - `app/helpers/burndown_helper.rb`、`app/views/burndown/_burndown_combo_chart.html.erb`
  - [x] 5.3 驗證
    - `bundle exec rspec` 383/383 全過（含 rebase 到 origin/main 後新增的專案歷程相關測試）
    - Playwright 截圖驗證：3 人協作議題「亞炬 Else／[AG2026] 智慧烘箱」正確顯示 3 組並排
      長條與 3 對理想／實際線，燈號與線的落差方向一致（陳謹皓、周詩御實線在虛線上方＝
      超支，邱珮玲兩線接近＝略慢），跟摘要表燈號結果一致

- [x] 6. 305 篩選列視覺對齊修正
  - 起因：使用者截圖回報篩選列「有高有低的」，`任務類型`／`範圍` 兩個 `<fieldset>` 明顯比
    `選擇專案`／`只顯示未完成`／`套用篩選` 等其他控制項高一截，即使外層 `.project-selector`
    已經有 `align-items: center`
  - 根因（用 Playwright 讀取實際 DOM bounding box 量測後才確認，不是憑空猜測）：瀏覽器對
    `<fieldset><legend>` 有特殊版面配置，即使 fieldset 設了 `display:flex`，legend 仍會被
    渲染成獨立一行、疊在 checkbox／radio 那一列「上面」，把 fieldset 的高度撐到 49.78px，
    其他純 `div`／`button` 只有 34px；外層 flex 的 `align-items:center` 確實有把每個 item
    的外框置中（量測後 5 個項目的外框中心點都在同一個 y 座標），但因為 fieldset 的額外高度
    集中在「上面」，導致裡面真正的 checkbox／radio 那一列看起來偏低，視覺上跟其他控制項
    的內容對不齊
  - 修法：`<legend>` 保留（螢幕閱讀器仍需要）但視覺上隱藏（`clip-path` 式的
    visually-hidden 寫法），另外加一個 `<span class="filter-group-label" aria-hidden="true">`
    當作看得到的標籤，跟 checkbox／radio 同一列排列，fieldset 因此只剩單行高度，
    跟其他控制項一致
    - `app/assets/stylesheets/application.css`（`.type-filter legend`／`.scope-filter legend`／
      `.filter-group-label`）、`app/views/dashboard/index.html.erb`
  - 驗證：Playwright 重新量測 DOM bounding box，五個項目高度都變成 33–34px、頂部對齊在
    同一條線上；`bundle exec rspec spec/requests/dashboard_spec.rb` 19/19 全過

- [ ] 7. 305／306／307 篩選加上時間區間設定（本年度／本月／多個月）
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

- [x] 8. 307 圖表細部打磨（多軸／圖例互動／說明文字）與 305 篩選列版面修正
  - [x] 8.1 每人一條右軸，取代原本共用一條右軸
    - 起因：3 人估計人時差很多時（例如 167／63／20），共用一條線性右軸會把估計少的人壓扁
      在底部，看不出他自己的進度細節
    - `burndown_chart_plot_width`／`burndown_chart_points`／`burndown_chart_x_labels`／
      `burndown_combo_bars` 改成接受 `padding_right` 參數；新增
      `burndown_combo_padding_right(assignee_count)` 依人數動態計算右邊界（每人一欄軸
      寬度），右軸刻度文字顏色對應該人的長條／折線顏色
    - `app/helpers/burndown_helper.rb`
  - [x] 8.2 點圖例可切換顯示/隱藏該人資料
    - 新增 `app/javascript/controllers/burndown_legend_controller.js`（Stimulus），圖例
      按鈕 `data-action="click->burndown-legend#toggle"`，透過 `data-assignee` 比對同一張
      圖裡的長條／折線／端點，切換 `.is-dimmed`（純顯示層級切換，不影響底層資料或燈號）
  - [x] 8.3 圖表說明文字改成置中標題 + i 圖示 tooltip
    - 原本 `.chart-caption` 是每張圖都常駐顯示的一段文字，議題一多、展開多張圖時很佔版面；
      改成標題置中，右邊掛一個 `ⓘ` 圖示，hover／focus 才顯示完整說明（純 CSS，無額外 JS）
  - [x] 8.4 305 篩選列版面修正（三個獨立問題，一起處理）
    - 套用篩選／重新整理資料按鈕包進 `.filter-actions`，`margin-left:auto` 推到所在那一行
      最右側（篩選項目一多時常自己換到下一行、靠左黏著不好看，右對齊比較符合慣例）
    - `type-filter`／`scope-filter` 的 `<legend>` 視覺隱藏、改用同一列的
      `.filter-group-label` span 當看得到的標籤，修正 fieldset 因為 legend 佔掉獨立一行
      而比其他篩選控制項高一截、對不齊的問題（用 Playwright 讀 DOM bounding box 確認
      根因：外層 `align-items:center` 確實把每個 item 的外框置中，但 fieldset 額外高度
      集中在「上面」，導致裡面的 checkbox 列看起來偏低）
    - `.issue-section` 補上 `margin-top`（306/307/專案歷程共用這個 class），修正篩選表單
      跟下方標題完全沒有間距、黏在一起的問題
    - `app/assets/stylesheets/application.css`、`app/views/dashboard/index.html.erb`
  - [x] 8.5 loading 動畫至少顯示 1 秒
    - 起因：篩選送出時的轉圈圈完全依賴 Turbo 原生 `busy` 屬性生命週期，快取命中或本機
      測試時常常快到只閃一下就消失，感覺像畫面故障
    - 讀 Turbo 原始碼確認：`turbo:before-frame-render` 的 `preventDefault()+resume()`
      只會延後「換上新內容」，`busy` 屬性是在 `FormSubmission#requestFinished` 呼叫
      `formSubmissionFinished` 時就移除，跟 render/resume 是兩條獨立路徑，delay render
      不會 delay busy 消失；在 `turbo:submit-end` 監聽器裡直接 `setAttribute` 也沒用，
      因為 Turbo 緊接在同一個呼叫堆疊裡就會呼叫 `formSubmissionFinished` 把它蓋掉——要
      延到下一個 tick（`setTimeout(fn, 0)`）才補得上，補上後再排時間親手移除
    - `app/views/layouts/application.html.erb`
  - [x] 8.6 驗證
    - `bundle exec rspec` 383/383 全過
    - Playwright 截圖＋DOM bounding box 量測驗證：307 多軸刻度與圖例顏色一致、點擊圖例
      正確切換 `.is-dimmed`（單一人，不會誤觸其他人）、負值剩餘的超支迴歸測試仍過；305
      五個篩選控制項高度從 34/34/49.78/49.78/18 統一成 33～34px、頂部對齊同一條線；
      loading 動畫實測從快取命中時的 55～92ms 延長到穩定 1046ms（含少量 setTimeout 排程
      誤差），冷快取（真正需要等 API 回應）時不受影響、不會反而變更慢

---

## Notes

- 三個頁面（305/306/307）目前快取策略已一致：`Rails.cache.fetch` + 5 分鐘 TTL，快取鍵
  皆含各自的試算表 ID（307 另含年度分頁名稱）
- 本機／新 worktree 驗證步驟需要 `config/credentials/development.key`（見
  `warroom-data-api-prototype/README.md` 「在新的 git worktree 開發」段落），該檔案已
  `.gitignore`，需從既有 checkout 複製
- 任務 5（時間區間篩選）待與使用者確認 305/306/307 各自的日期篩選語意後，才拆解成可執行的
  子任務；三頁目前的「年度」概念都綁在資料來源分頁／試算表上，不是單純的 UI 元件問題
