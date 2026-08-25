# 設計文件

## 概述

**架構決策（2026-08-20）**：原規劃是 Rails 直接接 Notion API（見 git 歷史），已改為 n8n workflow
先把 Notion「階段紀錄」資料庫同步進 Google Sheet，Rails 端比照既有 305/306/307 模式讀取該 Sheet
（理由見 requirements.md「簡介」）。

**階段 0／1 已於 2026-08-25 確認完成**：n8n workflow 已建立並實際同步中，目標 Sheet
（spreadsheet ID `1YQp4f-5v985W4EV59jhSAdhTKMn2Mc-0PW-qYc6vKpU`，標題「專案進度」）已直接讀取確認
欄位配置。詳見 requirements.md「前置條件」。確認過程衍生出三個比原本「等 schema」更複雜的問題，
**均已與使用者確認解決**：

1. `unique_key`（`project|issue|stage`）非唯一——代表同一 stage 的「重排程」，非資料錯誤。呈現規則
   已確認（見 requirements.md 需求 4.5）：最新一筆為主要呈現，其餘以次要樣式顯示於展開卡片。
2. **卡片分組單位確認為 `(project, issue_id)`**，不是 `project`——真實 Sheet 顯示一個 `project`
   代碼底下有多個獨立的 `issue` 生命週期，與 static prototype「一專案一卡片」假設不符。此決策已
   寫入 requirements.md 需求 4.3。
3. 三個年度區塊（`sheet_year` = 2024／2025／2026）確認為**同一份資料依時間分年度**，非三種不同
   來源——`PhaseRecordsSheetsClient` 讀出並合併全部三區塊。使用者也因此要求新增**年度篩選**功能
   （見 requirements.md 需求 4.6，比照既有 `project_history_controller` 慣例）。三個區塊在 Sheet
   裡實際是三個獨立分頁（分頁名稱就是年度字串本身），非同分頁內的三個表格（已用真實 Service
   Account 憑證直接查詢確認）。

**全部階段（0〜8）已於 2026-08-25 實作完成**，見下方「分階段實作與確認順序」表與「真實資料串接時
發現的重大修正」章節。不依賴 Sheet 結構的部分（純邏輯 Ruby 移植）與需要真實 Sheet 存取的部分
（Client／Actor／Controller／View）皆已完成並通過測試。

---

## 分階段實作與確認順序

| 階段 | 做什麼 | 狀態 |
|---|---|---|
| 0 | n8n workflow 建立完成，取得目標 Sheet 的 spreadsheet ID／分頁名稱 | ✅ 已完成 |
| 1 | 打開實際 Sheet，核對真實欄位配置、卡片分組單位、重排程記錄呈現規則、年度篩選需求 | ✅ 已完成 |
| 2 | 純邏輯 Ruby 移植（`ProjectPhaseTrackingHelper`：`compute_row_state`／`diff_days`／甘特圖幾何） | ✅ 已完成（2026-08-19） |
| 3 | 實作 `PhaseRecordsSheetsClient`，含重排程記錄的「最新為主、其餘次要」分組邏輯 | ✅ 已完成 |
| 4 | 實作 `ProjectProfilesSheetsClient`（讀 `300_員工專案`「專案」分頁） | ✅ 已完成 |
| 5 | 實作 `Sheets::FetchPhaseTracking` Actor，彙總階段 3/4 輸出，依 `(project, issue_id)` 分組 | ✅ 已完成 |
| 6 | Controller＋View（篩選／排序／清單／甘特圖／年度篩選／議題名稱-ID 搜尋） | ✅ 已完成 |
| 7 | 錯誤處理與降級（需求 5，沿用既有 Sheets 錯誤碼慣例） | ✅ 已完成 |
| 8 | 真實環境驗證，記錄「真實資料串接時發現的重大修正」 | ✅ 已完成，見下方章節 |

---

## 架構

```
warroom-data-api-prototype/
├── app/clients/
│   ├── phase_records_sheets_client.rb     ← 讀「專案進度」試算表 2024/2025/2026 三分頁並合併
│   └── project_profiles_sheets_client.rb  ← 讀 300_員工專案試算表「專案」分頁（客戶／PM）
├── app/actors/sheets/
│   └── fetch_phase_tracking.rb            ← Sheets::FetchPhaseTracking：分組、重排程、狀態推導
├── app/helpers/
│   └── project_phase_tracking_helper.rb   ← 階段 2：甘特圖 SVG 幾何＋完成狀態計算
├── app/blueprints/
│   └── phase_tracking_card_blueprint.rb   ← 單一 Blueprint 涵蓋整張卡片形狀（比照
│                                              ProjectHistoryRowBlueprint 慣例，不拆兩個 Blueprint）
├── app/controllers/
│   └── project_phase_tracking_controller.rb ← 篩選／排序／年度／搜尋
├── app/views/project_phase_tracking/
│   ├── index.html.erb
│   ├── _overview.html.erb        ← 篩選表單＋清單/甘特圖切換
│   ├── _overview_list.html.erb   ← 卡片＋階段表＋重排歷史次要列
│   ├── _overview_gantt.html.erb  ← SVG 甘特圖
│   └── _gantt_legend.html.erb
└── config/routes.rb                        ← `get "/project_phase_tracking", to: "project_phase_tracking#index"`
```

不修改任何既有 305/306/307／`project_history` 檔案（同既有慣例）。**沒有新的憑證模組**——
`PhaseRecordsSheetsClient`／`ProjectProfilesSheetsClient` 直接 `include GoogleSheetsCredentials`，
比照 `ProjectRosterSheetsClient`。兩個 Client 的 `SPREADSHEET_ID` 皆為程式碼常數（不用
`ENV.fetch` 包一層預設值）——比照既有 `ProjectRosterSheetsClient` 的實際慣例（規劃階段設想的
`ENV.fetch("...", 常數)` 寫法其實只是既有慣例的誤記，既有 Client 是直接寫死常數，沒有走
環境變數覆寫）。

`PhaseRecordsSheetsClient#fetch_rows` 對 `TABS = %w[2024 2025 2026]` 逐一呼叫
`get_spreadsheet_values("#{tab}!A1:J2000")`（A~J 十欄，2026-08-25 因 `issue_id`／`issue_name`
拆欄從九欄變十欄），各自丟掉第一列（該分頁自己的表頭）後合併成單一
陣列回傳，呼叫端（Actor）不需要知道背後其實是三個分頁。`ProjectProfilesSheetsClient` 讀
`300_員工專案`（spreadsheet ID `101fF0GlW2iwjC6TNQnNgKjUrxJg-3Ia5nCYox6haTNM`，與既有
`ProjectRosterSheetsClient` 同一份，不同分頁）的「專案」分頁（`SHEET_NAME` 可用
`PROJECT_PROFILES_SHEET_NAME` 環境變數覆寫，比照既有慣例），只解析
`Github/Notion, _, _, 客戶, PM, _` 六欄中的代碼／客戶／PM 三欄，不解析「303 專案」與「狀態」
（維運狀態，非本頁的議題狀態）。

`Sheets::FetchPhaseTracking` 比照 `Sheets::FetchProjectRoster` 的錯誤處理與 `filter_map`／
欄位跳過慣例；`ProjectProfilesSheetsClient` 讀取失敗時降級（`profiles_unavailable`），不擋整頁。

---

## Sheet 實際欄位（已確認，2026-08-25）

spreadsheet ID `1YQp4f-5v985W4EV59jhSAdhTKMn2Mc-0PW-qYc6vKpU`（標題「專案進度」）表頭：

| Notion 原始欄位（截圖顯示名稱） | 對應內部欄位 | n8n 同步後的 Sheet 欄名 | 備註 |
|---|---|---|---|
| 日期 | `planned_date` | `planned_date` | 已確認 |
| 實際完成 | `actual_date` | `actual_date` | 已確認 |
| 專案 | `project` | `project` | 已確認，為純文字代碼（如 `HRM`／`JZNPMS`），非 Notion relation 物件 |
| （新，static prototype 沒有的欄位） | `issue_id` | `issue_id` | 議題名稱或純 Redmine ID，與 `project` 共同組成一個獨立階段追蹤生命週期＝卡片分組單位。原本是單一 `issue` 欄，2026-08-25 使用者拆分後改名 |
| （新，2026-08-25 使用者新增） | `issue_name` | `issue_name` | 議題人類可讀名稱，只在 `issue_id` 是純 Redmine ID 時才會填，僅供顯示／搜尋，不是分組鍵 |
| 類型 | `stage` | `stage` | 已確認，但真實資料只觀察到 4／5 個合法值（缺 `需求確認`）；`STAGE_ORDER` 仍保留 5 個值 |
| 狀態 | `status` | `status` | 已確認，觀察到值：`完成`／`延誤已完成`／`延誤未完成`／`暫緩`／`未完成`（比 static prototype 假設的更多，Blueprint／View 不應假設只有 `完成` 一種） |
| 原因 | `reason` | `reason` | 已確認 |
| （新） | 不納入 `PHASE_RECORDS` 形狀 | `unique_key` | `project|issue_id|stage` 組成，⚠️ **非唯一**（代表重排程，不去重，見前置條件） |
| （新） | 不納入 `PHASE_RECORDS` 形狀 | `sheet_year` | 部分列為空字串，不可靠，不作為年度篩選依據 |

三個年度區塊（2024／2025／2026）在 Sheet 裡是**三個獨立分頁**（分頁名稱就是年度字串本身），非
同分頁內的三個表格；`PhaseRecordsSheetsClient` 讀出三個分頁後合併為單一陣列。

另有兩個實作階段才發現、原規劃沒預期到的欄位語意問題（皆已修正）：

1. **`status` 不是卡片的「狀態」欄位資料來源**：一開始誤把 `ProjectProfilesSheetsClient`「專案」
   分頁的「狀態」欄（值如「維護」，專案層級維運狀態）當成卡片的 `status`。使用者指正後改為：
   卡片 `status` = 依 `STAGE_ORDER` 由後往前找到的第一個有記錄的階段（即議題目前推進到的最新
   階段）之 `status` 欄位（來自階段紀錄 Sheet 本身，即上表的 `status` 欄——值域是
   `完成`／`延誤已完成`／`延誤未完成`／`暫緩`／`未完成`），與 `ProjectProfilesSheetsClient` 完全
   無關。`ProjectProfilesSheetsClient` 只提供客戶／PM，不再解析「狀態」欄。
2. **新增議題名稱／ID 搜尋（`q` 參數）**：真實 `issue_id` 值有時是描述性名稱（「202412 優化」），
   有時是純 Redmine ID（「4515」），對 `issue_id`／`issue_name`／`project` 三欄做不分大小寫子
   字串比對。此需求提出時 Sheet 還只有單一 `issue` 欄，`issue_name` 是後來才拆出來的新欄
   （見上表），拆分後 `matches_query?` 自動涵蓋。

---

## 純邏輯 Ruby 移植（階段 2，已完成，與資料來源無關）

`docs/js/project-phase-tracking.js` 的 `parseDateOnly`／`diffDays`／`computeRowState`／甘特圖
`stageBar` 幾何計算，其規則已在 static prototype 三輪審閱定案，與資料來源無關，已移植為 Ruby
（`ProjectPhaseTrackingHelper`，比照既有 `ProjectHistoryHelper` 的角色）：

- `parse_date_only(date_str)`：Ruby `Date.iso8601` 搭配 `rescue` 回傳 `nil`（等同 JS 版
  `parseDateOnly` 的容錯行為），不需要手刻 `Date.UTC` 等價邏輯——Ruby `Date` 物件本身無時區概念，
  直接比較日期部分即可，天生比 JS `Date` 安全，但仍以 `Date.iso8601` 嚴格解析（不用 `Date.parse`，
  其對不合法格式的容錯行為與 `Date.iso8601` 不同，可能誤判格式錯誤的字串為合法日期）。
- `diff_days(actual_date, planned_date)`：`(actual - planned).to_i`。
- `compute_row_state(planned_date, actual_date)`：與 JS 版邏輯一致的四狀態組合判斷（見 static
  prototype design.md）。
- 甘特圖幾何：比照既有 `project_history_helper.rb` 的 `xAt`／`monthTicks`／SVG padding 常數手法，
  改用 static prototype 已定案的錨點規則（`planned_date` 為左端點、提前完成畫「提前幅度」視覺
  標記、SVG 最小寬度 900px）。

**實作已完成（2026-08-19）**：`ProjectPhaseTrackingHelper` 已建立，`parse_date_only`／
`diff_days`／`compute_row_state` 與規劃一致；RSpec unit test（`spec/helpers/
project_phase_tracking_helper_spec.rb`，20 cases）已通過。

**實作與規劃的一處差異（發現於實作階段，非規劃階段可預見）**：甘特圖幾何方法一律加上 `phase_`
前綴（`phase_gantt_chart_domain`／`phase_gantt_chart_svg_width`／`phase_gantt_chart_x`／
`phase_gantt_chart_month_ticks`／`phase_gantt_chart_today_x`／`phase_gantt_chart_stage_bar`），
未依原規劃直接使用與 `project_history_helper.rb` 相同的 `gantt_chart_*` 命名。原因：Rails
`ActionController::Base` 預設 `include_all_helpers = true`，`app/helpers/` 下所有 helper module
會被混入同一個 view/helper context；`ProjectHistoryHelper` 已定義簽名不同的
`gantt_chart_domain(rows)`／`gantt_chart_svg_width(min_date, max_date)`／`gantt_chart_x(date_str,
min_date, max_date)`／`gantt_chart_month_ticks(min_date, max_date)`／`gantt_chart_today_x(min_date,
max_date)`，同名但簽名不同會依 module include 順序互相覆蓋，導致其中一頁的甘特圖在執行期靜默壞掉
或丟出 `ArgumentError`（實測：加入未加前綴版本後，`project_history_spec.rb` 的甘特圖相關測試從
全數通過變成 6 個失敗，`project_history_helper_spec.rb` 另外 7 個失敗）。加前綴後兩組 helper
互不干擾，`bundle exec rspec`（386 examples）僅剩 1 個與本次變更無關的既有浮點捨入 flaky test
（`project_history_helper_spec.rb:91`，非本次引入）。後續階段 6（Controller／View）串接時，
View 需呼叫 `phase_gantt_chart_*` 而非 `gantt_chart_*`。

---

## 錯誤處理

沿用既有 `Sheets::FetchProjectRoster` 的 `Google::Apis::ClientError` 處理慣例（見 requirements.md
需求 5）：404 或訊息含 `"Unable to parse range"` → `sheet_not_found`；403 → `access_denied`；其餘
→ `internal_error`。不需要 Notion 專屬的 429 重試邏輯——Google Sheets API 既有 Client 慣例已涵蓋
配額錯誤（回傳 403，走既有 `access_denied` 分支）。

---

## 測試策略（已完成）

- 階段 2（純邏輯 Ruby 移植）：`spec/helpers/project_phase_tracking_helper_spec.rb`（20 cases）。
- Client（`spec/clients/phase_records_sheets_client_spec.rb`／
  `spec/clients/project_profiles_sheets_client_spec.rb`）：`double` stub
  `Google::Apis::SheetsV4::SheetsService`，比照既有 `project_roster_sheets_client_spec.rb`
  慣例，驗證真實欄位配置（不是臆測的假設值）。
- Actor（`spec/actors/sheets/fetch_phase_tracking_spec.rb`，15 cases）：`(project, issue_id)` 分組、
  重排程 primary／history 分組與排序、`STAGE_ORDER` 過濾、狀態推導（從階段紀錄而非 Roster）、
  年度篩選、Roster 失敗降級、三種錯誤碼對應。
- Controller／View 沒有另外寫 RSpec（比照既有 `project_history` 慣例，該頁面也沒有 controller
  spec），改用 `RAILS_ENV=development` 搭配真實 Service Account 憑證直接啟動伺服器 smoke test
  （`curl` 確認 HTTP 200、卡片數量、無錯誤訊息、清單／甘特圖／篩選／搜尋皆正常）。
- 全套 `bundle exec rspec`（405 examples）與 `rubocop`（本次新增／修改的檔案）皆通過；唯一失敗
  是 `fetch_project_history_spec.rb` 一個與本次變更無關、日期相依的既有 flaky test（`due_date`
  隨系統時間推進而由未逾期變逾期，非本次引入）。

---

## 真實資料串接時發現的重大修正（階段 8，比照既有 real-source spec 慣例）

規劃階段的假設與實際串接後的落差，供未來同類 spec 借鏡：

1. **架構決策本身錯了一次，之後才修正**：最初規劃是 Rails 直接接 Notion API；後來發現 n8n 早已
   把資料同步進 Google Sheets，改為沿用既有 Sheets 慣例，前置條件大幅減輕（見概述）。
2. **三個「情境」的猜測有落差**：規劃階段列了「客戶／PM／狀態」資料來源的三種可能情境
   （獨立 Sheet／階段紀錄自帶欄位／複用既有 `ProjectRosterSheetsClient`），實際情況是第四種：
   同一份既有 `300_員工專案` 試算表裡有一個先前沒發現的「專案」分頁，用完全不同的鍵（`Github/
   Notion` 代碼）對應——不屬於規劃時列出的任三種情境之一。
3. **`unique_key` 不唯一，且不是資料錯誤**：一開始以為是資料品質問題，後來確認是「重新排程」的
   正常語意（同一階段被延誤時新增一筆而非覆蓋），連帶影響卡片呈現規則（最新為主、其餘次要顯示，
   且要新舊排序）。
4. **卡片分組單位整個錯了**：規劃／static prototype 都假設「一個 `project` 一張卡片」，實際
   `project` 底下有多個獨立 `issue`，正確單位是 `(project, issue_id)`。
5. **「狀態」欄位語意搞錯一次**：第一版實作把專案層級的維運狀態（「維護」）當成卡片狀態，使用者
   實際看畫面後才發現不對，改為議題目前所在階段的完成狀態。**教訓**：即使欄位名稱字面相同
   （Roster 的「狀態」vs 議題的「完成狀態」），語意可能完全不同，光靠欄名配對容易誤判，
   應該先確認資料的實際業務意涵，而非假設「有欄位就是要用的那個」。
6. **只讀真實資料還不夠，要看使用者怎麼用畫面**：搜尋欄位（議題名稱／ID）、重排歷史排序（新到舊）
   這兩項都是使用者實際看到跑起來的畫面後才提出的需求，static prototype／規劃階段完全沒設想到，
   因為單看 Sheet 資料本身看不出使用情境上的需要。
