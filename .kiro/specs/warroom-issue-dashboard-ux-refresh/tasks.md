# Implementation Plan: 306 議題資料表格 UX 改版

## Overview

使用者對「議題資料」分頁提出一版完整的 UX 改版需求：表格欄位重構、KPI 摘要卡、搜尋／快捷篩選、
分頁，外加一個新欄位 `total_hours`（花費時間）。

實作前先盤點資料源（任務 0），只查了程式碼裡目前讀取範圍（`A:K`）涵蓋到的欄位，確認範圍內不含
`total_hours`，一度誤判為「全新欄位、資料源不存在」。使用者後來直接貼出 Google Sheets 截圖
糾正：**`total_hours` 其實存在，只是在 L 欄，超出當時的讀取範圍**——這是本輪一個值得記住的
教訓：判斷「資料存不存在」要查實際試算表本身，不能只查程式碼目前讀到哪裡就下結論。確認後把
`ISSUE_RANGE` 從 `A:K` 擴大到 `A:L`，任務 6 從「阻塞中」變成可以直接做。

同樣因為這個 App 沒有登入／使用者身分機制（`assigned_to` 只是試算表裡的一個姓名字串，沒有
session/current_user 概念），原始需求的「[只看我的議題]」快捷篩選無法實作（沒有「我是誰」的
資訊來源），本輪只做「[只看客訴]」。

---

## Tasks

- [x] 0. 資料源盤點（total_hours 可行性確認，含一次誤判與更正）
  - 第一輪只查了 `app/actors/sheets/fetch_issue_dashboard.rb`、
    `app/clients/issue_sheets_client.rb`（讀取範圍 `A:K`）與既有測試 fixture，誤判
    `total_hours` 不存在於資料源
  - 使用者提供 Google Sheets 實際截圖更正：`total_hours` 存在於 **L 欄**（緊接在 K 欄
    project 後面），只是超出當時 `ISSUE_RANGE = "A:K"` 的讀取範圍，程式碼查詢自然找不到
  - 教訓：查「資料是否存在」要以實際試算表為準，程式碼目前讀到哪裡只代表「目前讀了什麼」，
    不代表「來源有什麼」——兩者是不同的問題，日後遇到類似「這個欄位存在嗎」的問題，優先
    請使用者截圖或提供試算表連結確認，不能只憑程式碼現況下結論

- [x] 1. 表格欄位重構（9 欄精簡為 7 欄）
  - [x] 1.1 議題編號／專案合併一欄
    - `app/views/issues/_issue_list.html.erb`：議題編號連結在上、專案文字在下（沿用既有
      `issue-id-link` 連結邏輯，不變更 Redmine 連結行為），新增 `.issue-project-sub` 樣式
  - [x] 1.2 類別標籤沿用既有 `attribution_badge`，調整「測試」的顏色為灰底
    - `.attribution-individual`（測試／TestingBug）從藍底（`--badge-progress-*`）改成灰底
      （`--badge-pending-*`），跟「處理中」狀態 badge 的藍色不再搶顏色語意；`.attribution-shared`
      （客訴）維持紅底不變
  - [x] 1.3 主旨超長截斷＋hover 顯示全文
    - 新增 `.issue-subject-truncate`：`max-width:26ch` + `text-overflow:ellipsis` +
      `white-space:nowrap`，配合原生 `title` 屬性顯示完整主旨，不用額外 JS tooltip
  - [x] 1.4 狀態改成圓角 Badge，修正「新 建 立」垂直疊字破版
    - 根因：純文字塞進窄欄位、沒有 `white-space:nowrap`，4 字狀態在欄寬不夠時逐字換行
      變成直排；包成 badge span（沿用既有 `.status-badge` 基礎樣式）並加 `white-space:nowrap`
      就解決
    - 新增 `IssuesHelper#issue_status_badge_class(status)`：關鍵字比對（非精確字串比對，
      真實 Redmine 狀態文字自由填寫，無法窮舉每一種可能值）——含「完成／確認／關閉／解決／
      結束」→ 綠（`.issue-status-done`）；含「處理／進行」→ 黃（`.issue-status-processing`，
      沿用 307 新增的 `--at-risk-*` token）；含「新建／新增」→ 藍（`.issue-status-new`）；
      其餘 → 灰（`.issue-status-other`）
    - `Sheets::FetchIssueDashboard::ISSUE_DONE_STATUS_PATTERN` 是同一套「完成／確認／關閉／
      解決／結束」關鍵字的**共用單一來源**（KPI 計算用的 `issue_done?` 也讀這個常數），
      避免 View 判斷顏色跟 Actor 判斷「是否已完成」各自維護一份、日後改一邊忘了改另一邊
      （初版一度真的各自寫了一份不同的 regex，後來發現重複才合併成一個常數）
  - [x] 1.5 負責人加小頭像
    - `.assignee-avatar`：圓形、`--color-accent` 底色、姓名第一個字（無圖片資源，不接外部
      圖床）
  - [x] 1.6 「開始／到期／工作天數」三欄合併成「時程與天數」一欄
    - 新增 `IssuesHelper#issue_timeline_label(issue)`：有到期日 → `開始 ~ 到期`；無到期日
      → `開始 ~ 未指定（已開 N 天）`，N 由 `Date.current - 開始日期` 算出；開始日期也缺
      → 顯示 `—`；捨棄原本獨立的 `work_days` 欄位（來源本來就常是空值，此合併欄位已涵蓋
      「這議題開了多久」的資訊）
  - [x] 1.7 `total_hours`（花費時間）第 7 欄，見任務 6（原本以為阻塞，實際可直接做）
  - [x] 1.8 測試：`spec/helpers/issues_helper_spec.rb` 新增
    `issue_status_badge_class`／`issue_timeline_label` 案例（含負責人、狀態關鍵字、
    有無到期日等邊界情況）

- [x] 2. 議題資料 KPI 摘要卡（4 張，含花費工時）
  - [x] 2.1 `Sheets::FetchIssueDashboard` 新增 `output :issue_kpis`
    - 依「議題資料」分頁目前的篩選結果（`filtered_issues`，含任務 3 的搜尋／快捷篩選，
      分頁之前的完整結果，不是分頁後的那一頁）計算四個數字：
      - `pending`：未完成議題數（`issue_done?` 為 false）
      - `urgent_complaints`：`pending` 中「歸屬類型為客訴（Complaint）且已逾期」的議題數
        （原始需求只說「緊急客訴」沒有明確定義，資料裡沒有「優先權／嚴重度」欄位，只能用
        「客訴 + 已逾期」這個可從既有資料算出的最接近定義，日後若有優先權欄位可以再調整）
      - `overdue_or_undated`：`pending` 中「到期日已過或到期日空白」的議題數
      - `total_hours_sum`：**不限 pending**——所有篩選結果（含已完成）的 `total_hours`
        加總，因為這張卡片算的是「投入成本」不是「還剩多少要做」，跟前三張卡片語意不同
    - `app/actors/sheets/fetch_issue_dashboard.rb`
  - [x] 2.2 View：`section.issue-section` 上方新增 4 格 KPI（沿用既有 `.summary-bar`／
    `.stat-item` 樣式），`urgent_complaints` 用 `.stat-overdue` 紅字，`overdue_or_undated`
    用新增的 `.stat-warning` 黃字（沿用 `--at-risk-text`）
  - [x] 2.3 測試：`spec/actors/sheets/fetch_issue_dashboard_spec.rb` 新增
    `issue_kpis` 案例（含「緊急客訴＝客訴+逾期」「逾期或未定到期日」「花費工時含已完成議題」
    的邊界案例）

- [x] 3. 搜尋框與快捷篩選 Tag
  - [x] 3.1 `Sheets::FetchIssueDashboard` 新增 `input :q`／`input :type`
    - `filter_issues` 擴充：`q` 比對主旨／議題編號／負責人（不分大小寫的子字串比對）；
      `type` 精確比對 `issue[:type]`（快捷篩選只會送出固定值 `"Complaint"`，非自由輸入）
  - [x] 3.2 `IssuesController`／View
    - 「議題資料」表單新增搜尋輸入框（`name="q"`）
    - 新增「只看客訴」快捷篩選：`.quick-filter-tag` 連結，點擊後帶上 `type=Complaint`
      （沿用既有 Turbo Frame GET 導覽模式，不用額外 JS）；已啟用時 `.is-active` 樣式反白，
      再點一次回到全部
    - 兩個分頁籤（統計摘要／議題資料）的表單都補上 `q`／`type` 的 hidden fields，避免切換
      分頁籤時把另一個分頁籤的搜尋／快捷篩選狀態重設掉（沿用既有 `project`／`status` 的
      跨分頁籤保留模式）
    - **不做「只看我的議題」**：這個 App 沒有登入／使用者身分機制，`assigned_to` 只是
      試算表裡的姓名字串，沒有「目前使用者是誰」的資訊來源，無法判斷「我的」是指誰
  - [x] 3.3 測試：`spec/actors/sheets/fetch_issue_dashboard_spec.rb` 涵蓋 `q`／`type`
    篩選案例

- [x] 4. 表格分頁
  - [x] 4.1 `IssuesController` 新增分頁邏輯
    - `ISSUE_PAGE_SIZE = 15`；`params[:page]` 轉整數、clamp 在 `1..總頁數`；對
      `IssueBlueprint.render_as_hash(result.filtered_issues)`（已含任務 3 的搜尋／快捷
      篩選，分頁前的完整結果）用 `each_slice` 切片
    - 分頁不做在 Actor 裡：Actor 的職責是「篩選出哪些議題」，分頁純粹是 Controller／View
      呈現方式，且 KPI 卡片（任務 2）需要「分頁前」的完整篩選結果才能算對總數，兩者共用
      同一份 `filtered_issues`、分頁在更後面才做，語意上比較乾淨
  - [x] 4.2 View：表格下方分頁列（`.pagination`）
    - 「顯示 X–Y 筆，共 Z 筆」文字＋頁碼按鈕，當前頁碼反白（`.is-current`）、非當前頁碼是
      連結
    - 分頁連結帶上目前的 `project`／`status`／`q`／`type`／`month`／`breakdown_sort`／
      `breakdown_dir`，換頁不會把篩選條件重設掉
  - [x] 4.3 分頁邏輯已透過整合驗證（任務 5）以真實資料確認正確（415 筆、每頁 15 筆、
    共 28 頁，頁碼列與筆數摘要皆正確顯示）

- [x] 5. 整合驗證
  - `bundle exec rspec` 395/395 全過（另有 1 個跟本次改動無關的既有 flaky 測試
    `project_history_helper_spec.rb:91`，浮點數捨入誤差 93.49 vs 93.48，用 `git stash`
    確認在本次改動之前就會失敗，非本次改動造成，不在本次範圍內修復）
  - Playwright 截圖＋真實資料驗證：4 張 KPI 卡片數字正確、狀態 badge 不再破版、主旨截斷、
    「只看客訴」連結正確帶參數、分頁正確運作；額外用搜尋議題編號 4551 交叉比對使用者提供
    的 Google Sheets 截圖，確認花費時間欄位（0.75h）與 KPI 卡片加總完全一致

- [x] 6. `total_hours`（花費時間）欄位與「累積總花費工時」KPI 卡
  - 使用者截圖確認：L 欄即是 `total_hours`，緊接在 K 欄（project）後面
  - `IssueSheetsClient::ISSUE_RANGE` 從 `A:K` 擴大為 `A:L`
  - `Sheets::FetchIssueDashboard#parse_issues` 多解析一個欄位（`safe_float`，沿用既有的
    浮點數轉換 helper，不必新寫）
  - `IssueBlueprint` 加上 `:total_hours` 欄位
  - 表格加回第 7 欄「花費時間」，`0h`（含 nil）套用 `.total-hours-empty` 淡灰色樣式，
    非零值用 `number_with_precision(precision: 2, strip_insignificant_zeros: true)` 顯示
    （例如 `8.25h`，整數值不多顯示無意義的 `.00`）
  - KPI 卡片補回「累積總花費工時」＝目前篩選結果（不限完成與否）的 `total_hours` 加總
  - 測試：`spec/clients/issue_sheets_client_spec.rb`（range 改成 `A:L`）、
    `spec/actors/sheets/fetch_issue_dashboard_spec.rb`（`parse_issues` 新增
    total_hours 轉換案例、`issue_kpis` 的 `total_hours_sum`）、
    `spec/blueprints/issue_blueprint_spec.rb`、`spec/requests/api/issue_dashboard_spec.rb`
    （欄位清單補上 `total_hours`）皆已更新

---

## Notes

- 表格欄位從 9 欄精簡為 7 欄：議題／專案（合併）、類別、主旨、狀態、負責人、時程與天數
  （合併）、花費時間
- 「緊急客訴」「累積總花費工時」等指標的精確定義，原始需求沒有給資料層面的計算方式，
  已在對應任務裡註明取捨依據（見任務 2.1），日後資料更豐富（例如有優先權欄位）時可以
  再調整定義，不是寫死不能改的規則
- 任務 0 的誤判／更正過程刻意完整記錄下來（而非事後改寫成「一次就查對」），因為這是這次
  協作中真正發生、且有明確教訓的一步：AI 查「資料存不存在」時容易只依賴程式碼現況（讀取
  範圍、既有 parse 邏輯），跟「試算表原始資料到底有什麼」是兩個不同層次的問題，日後遇到
  類似情境應該優先請使用者提供實際資料佐證，而不是憑程式碼現況斷言資料不存在
