# 305 專案任務進度 —— UX 待辦追蹤

`/dashboard`（305 專案任務進度）視覺／互動檢查累積出來的項目清單。與
`warroom-data-api-real-source` 的資料正確性驗算是不同階段：那邊管數字對不對，這裡管版面與
操作體驗。

檢查方式：`frontend-visual-qa` skill（Playwright 截圖 ＋ DOM 量測），實測寬度 1440／768／390，
淺色與深色兩種主題。每次修完一批就回來更新勾選狀態。

最後更新：2026/09/16

---

## 進行中

（目前沒有進行中項目——本輪 5 項已全部處理完成，見下方「已完成」。）

## 已完成

- [x] **摘要卡缺少「目前套用了哪些篩選」的說明** —— 摘要卡上方加一行 `.filter-summary`：
      「以上統計僅套用『專案』與『任務類型』篩選，不受下方『範圍』與『預計完成日期』
      影響；『逾期』計入目前仍逾期，或已完成但當初遲交的任務。」純文字說明，不需要動
      Actor／Controller。

- [x] **「已逾期」範圍與摘要卡「逾期」定義不同，同畫面沒有區分** —— 原計畫是替範圍選項
      改名分開兩種語意，實際採用另一個做法（跟使用者確認過）：把 305 頁的「逾期」統一成
      同一個較寬定義（目前仍逾期，或已完成但當初遲交），標籤／摘要卡／範圍篩選三處都改用
      `Sheets::FetchProjectProgress.overdue_or_completed_late?`，數字不再兜不起來（摘要卡
      逾期數 6 → 70，跟範圍篩選的 70 筆一致）。**刻意不動**共用的 `.overdue?`（executive_summary
      專案健康度分級、pm_weekly_report 任務分類都在用，只該影響 305 這頁）。
      副作用：完成但當初遲交的任務（例如「平台 前端」，狀態完成、延誤 +7 天）原本沒有
      「逾期」標籤，跟旁邊延誤天數的紅字對不起來，被使用者實測發現後一併修正，現在也會
      標「逾期」。新增涵蓋測試：`spec/actors/sheets/fetch_project_progress_spec.rb`
      「summary 的逾期數涵蓋完成但當初遲交的任務」、`spec/requests/dashboard_spec.rb`
      「逾期標籤涵蓋完成但遲交的任務」。

- [x] **單筆任務的專案卡片留白偏重** —— `.project-block:has(tbody tr:only-child)` 收緊下緣
      內距（1.5rem → 0.75rem）；實測 AMAS System（1 筆）卡片高度 172px → 160px，RAG／HRM
      （多筆）不受影響。

- [x] **390px 下日期區間換行，「～」孤立在行尾** —— 把「～」跟結束日期輸入框包成
      `.date-range-to`（inline-flex），兩者當成同一個 flex item 一起換行；實測 390px 下
      「～」與結束輸入框同一行，不再各自獨立換行。

- [x] **12px 文字對比壓線** —— `.filter-hint` 這個 class 在更早的重構中已經拿掉（起訖日期
      合併 fieldset 後改用純視覺分組，不再需要額外的提示文字），實際只剩表格表頭
      （`--color-text-faint`）需要處理；重新精確量測（非人工估算）發現深色主題其實已經
      跌破門檻（4.06:1 < 4.5:1），比原記錄的 4.70 更嚴重。調整
      `--color-text-faint`：淺色 #64748b→#54627a（4.76→6.17）、深色 #718096→#96a3ba
      （4.06→6.41），全站共用同一個 token，順帶修好其他 12 頁面用到同一個變數的地方。

- [x] **表格欄位跨專案區塊對不齊** —— `table-layout: fixed` ＋明訂各欄寬度；實測
      `misaligned = []`，三張表每一欄左邊界一致。
- [x] **手機／平板關鍵欄位被裁掉** —— 768px 以下改卡片式（表頭隱藏、`td::before` 讀
      `data-label`）；實測 390px 下七欄全可見、表格橫向溢出 0、頁面水平溢出 0。
- [x] **長任務名稱把短欄位擠成直向斷行** —— 固定欄寬後解決；以 line-height 為基準量測，
      無任何儲存格被擠成多行。
- [x] **主題切換鈕在 Turbo 換頁後失效** —— 補上 `turbo:load` 監聽；實測從入口頁點進後
      切換正常（`data-theme` 變更、背景換色、localStorage 寫入）。
- [x] **checkbox／連結點擊區過小** —— checkbox 本來就包在 `<label>` 裡（點文字一直有效），
      問題是 label 沒有 padding。現況：類型標籤 46×26、麵包屑 58×27（原 13×13、42×16），
      並加上 `@media (pointer: coarse)` 在觸控裝置補到 44px。
      ⚠️ 44px 那條規則無法在 headless Chrome 驗證（回報 `pointer: fine`），需實機確認。
- [x] **起訖日期看起來像兩個多餘欄位** —— 合併為單一「預計完成日期」fieldset，`～` 連接；
      共用 partial 加 `label:` 參數，306／307 沿用預設標籤，兩頁實測未跑版。（曾經另外加過
      `hint:` 參數在 fieldset 旁印一行提示文字，後續整理時拿掉了——同樣的說明現在併進上面
      「摘要卡缺少篩選說明」那則的 `.filter-summary`，不需要兩處各說一次。）
- [x] **日期區間方框比鄰居高 17px** —— 統一三種表單控制項高度為 34px 並移除 fieldset 上下
      padding；實測控制項 34px、方框 36px、兩行各自對齊在 1px 內。
- [x] **篩選群組的標籤間距不一致** —— `.filter-group-label` 的 padding 與 label 的水平負
      margin 讓「任務類型」「範圍」比其他群組窄 6px；移除後五個群組一律 12px。
- [x] **篩選區與統計卡之間沒有間距** —— 原本兩者 y 座標相同（0px），與頁面其他 20～24px
      的節奏對不上；補 `.project-selector + .summary-bar` 上邊距後為 20px。
- [x] **「年度」與「日期區間」功能重疊** —— 已移除年度，保留日期區間（表達力涵蓋年度，
      且為三頁共用元件）。連帶清掉 Actor 的 `year` input／`years_available`／`task_year`／
      `matches_year?`／`sorted_years` 與 Controller 的 `YearFilterable`。
- [x] **無法只看未完成任務** —— 移除獨立狀態篩選後失去入口（16 筆未完成中有 5 筆在預設
      檢視看不到）；改在「範圍」加入 `incomplete` 檢視，實測列出 16 筆，與摘要卡一致。

## 擱置

- [ ] **route `/dashboard` 改名為 `/project_progress`**
      目前 route 名稱與站內其他層（`/api/project_progress`、`FetchProjectProgress`、
      `ProjectProgressSheetsClient`）不一致。連帶要改 `DashboardController` →
      `ProjectProgressController`、view 目錄搬家、各頁連結與 spec，約 6 個檔案。
      **使用者決定等這輪 UX 調整收尾後再一起處理，現在不要動。**
