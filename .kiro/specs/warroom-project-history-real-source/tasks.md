# 實作計畫：專案歷程 Real Source

## 概述

在 `warroom-data-api-prototype` 新增 `Sheets::FetchProjectRoster`（300_員工專案）與整合型
`Sheets::FetchProjectHistory`，新增 `ProjectHistoryController` 與 `/project_history` 頁面，改讀真實
Google Sheets 資料。不修改 305/306/307 既有檔案，燃盡圖直接重用既有 `_burndown_chart.html.erb`。

**狀態**：已完成實作，且已用真實 Google Service Account 憑證對真實試算表驗證過（不只 RSpec stub）。
`bundle exec rspec` 全專案 344/344 通過，`bundle exec rubocop` 全部新檔案無違規。

實作過程中依序發現並修正了 4 個規劃階段沒預料到的真實資料問題：
1. `ProjectHistoryRowBlueprint` 漏了 `:tasks` 欄位，甘特圖渲染時噴例外（RSpec 階段發現）。
2. `300_員工專案`「專案清單」實際存放在分頁「專案工程師對照表」，不是規劃時猜測的「專案清單」。
3. 305 與 Roster 的專案名稱字串完全比對只對得上 2/8（後改用 9 個活躍專案驗證），加上「兩欄都查找
   （專案全名／專案縮寫）」後才 9/9 全部對上。
4. 307 是跟 305/306/Roster 完全獨立的第三套命名系統，且顆粒度更細（一對多），無法用任何自動規則
   （字串比對、客戶名稱前綴）安全對應，最終請使用者在 `300_員工專案` 人工新增「307對應專案」欄，
   改用子字串比對（不拆解分隔符）讀取這份人工對照。
5.（追加）Roster 試算表與 305/306/307 是不同擁有者、不同共用權限設定，實測遇過「Roster 存取被拒、
   其餘三者正常」的狀況，故把 Roster 失敗的處理方式從「整頁報錯」改為「降級顯示，客戶/PM 顯示
   `—`」，避免非核心資料來源拖累核心功能。

以真實資料驗證的最終結果：9 個目前在 305 有進度資料的專案，客戶/PM 9/9 對應成功，縱向歷程四個區塊
（花費工時／燃盡圖／測試趨勢／客訴狀態）皆有非空資料。

---

## 任務

- [x] 1. ProjectRosterSheetsClient
  - [x] 1.1 新增 `app/clients/project_roster_sheets_client.rb`
    - _需求：1.1_
  - [x] 1.2 `spec/clients/project_roster_sheets_client_spec.rb`
    - _需求：1.1_

- [x] 2. Sheets::FetchProjectRoster
  - [x] 2.1 新增 Actor，解析專案／狀態／客戶／PM 欄位，跳過空白專案列
    - _需求：1.2, 1.3_
  - [x] 2.2 錯誤處理（三種 failure_code）
    - _需求：1.4_
  - [x] 2.3 `spec/actors/sheets/fetch_project_roster_spec.rb`
    - _需求：1.2, 1.3, 1.4_

- [x] 3. Sheets::FetchProjectHistory — 橫向總覽彙總
  - [x] 3.1 呼叫四個子 Actor，任一失敗即整體失敗
    - _需求：6.1_
  - [x] 3.2 `build_overview_rows`：305 專案彙總 + Roster join（找不到對應時客戶/PM/狀態為 nil）
    - _需求：2.1, 2.2_

- [x] 4. Sheets::FetchProjectHistory — 縱向歷程彙總
  - [x] 4.1 `issue_weekly_spent` + `aggregate_work_hours`（依 actual_series 差值反推花費工時）
    - _需求：4.2_
  - [x] 4.2 `ideal_hours_at` + `aggregate_ideal_series`（逐日期即時計算再加總，不可直接加總各議題
        含錨點的 ideal_series——見 design.md 附註的凹陷 bug）+ `aggregate_actual_series`
    - _需求：4.3_
    - 迴歸測試（`fetch_project_history_spec.rb`）以兩個 `due_date` 錯開的議題驗證彙總後的序列
      單調不遞增；並驗證缺少合法起訖日期的議題被排除、不會以 0 拉低彙總值
  - [x] 4.3 `weekly_testing_counts` + `complaint_status`
    - _需求：5.1, 5.2_
  - [x] 4.4 `spec/actors/sheets/fetch_project_history_spec.rb`：含理想線彙總無凹陷的迴歸測試
    - _需求：4.2, 4.3, 5.1, 5.2, 6.1_
    - 15 項通過（`#aggregate_ideal_series`／`#aggregate_work_hours`／`#complaint_status`／
      `#weekly_testing_counts`／`#build_overview_rows`／`#call` 分派邏輯）

- [x] 5. ProjectHistoryController + 路由
  - [x] 5.1 `config/routes.rb` 新增 `/project_history`
    - _需求：2.1_
  - [x] 5.2 `index` action：依 `params[:project]` 分派總覽／詳情；總覽篩選（狀態/客戶/PM 交集）+
        檢視模式（`view=list`/`view=gantt`）
    - _需求：2.3, 2.4, 3.1_
  - [x] 5.3 失敗時 `build_failure`
    - _需求：6.1_

- [x] 6. Blueprint
  - [x] 6.1 `app/blueprints/project_history_row_blueprint.rb`
    - _需求：2.1, 2.2_
    - **修正**：初版漏掉 `:tasks` 欄位，甘特圖檢視渲染時 `r[:tasks]` 為 nil 而噴 500，request spec
      跑出來才發現；已補上欄位並在 spec 加了甘特圖渲染的迴歸測試（見任務 10.1）

- [x] 7. View — 橫向總覽
  - [x] 7.1 `app/views/project_history/index.html.erb`（總覽/詳情分派）+ `_overview_list.html.erb`
    - _需求：2.1〜2.4_
  - [x] 7.2 `_overview_gantt.html.erb` + `ProjectHistoryHelper` 甘特圖座標計算
    - _需求：3.1, 3.2_

- [x] 8. View — 縱向歷程
  - [x] 8.1 花費工時趨勢：重用 `IssuesHelper.trend_chart_*`
    - **實作變更**：未各自新增 `_work_hours_trend.html.erb`／`_testing_trend.html.erb` 兩份幾乎
      相同的樣板，改為單一共用的 `_simple_trend_chart.html.erb`（locals: `records`／`empty_text`／
      `aria_label`／`tooltip_label`），花費工時與測試問題趨勢共用同一份樣板、傳入不同資料與文案；
      新增 `ProjectHistoryHelper#to_trend_records(series, value_key)` 把 `:hours`／`:count` 鍵轉成
      `IssuesHelper.trend_chart_*` 方法要求的 `:total` 鍵
    - _需求：4.2, 4.4_
  - [x] 8.2 燃盡圖：`render partial: "burndown/burndown_chart"`（重用既有 partial，不重寫）
    - _需求：4.3, 4.4_
  - [x] 8.3 測試問題趨勢：重用 `_simple_trend_chart.html.erb`（見 8.1 附註）
    - _需求：5.1_
  - [x] 8.4 `_detail.html.erb` 內客訴議題狀態區塊（含未解決客訴清單、Redmine 連結）
    - **實作變更**：未獨立拆成 `_complaint_summary.html.erb`，直接寫在 `_detail.html.erb` 內（區塊
      邏輯簡單，拆分獨立檔案不會增加可讀性，比照 karpathy-guidelines 最簡方案）
    - _需求：5.2, 5.3_

- [x] 9. 入口頁連結
  - [x] 9.1 `app/views/home/index.html.erb` 新增「專案歷程」卡片
    - _需求：（同靜態原型入口卡片慣例）_

- [x] 10. `spec/requests/project_history_spec.rb`
  - [x] 10.1 總覽：篩選交集、甘特圖切換、Roster 找不到對應專案時顯示 `—`
    - _需求：2.1〜2.4, 3.1, 3.2_
  - [x] 10.2 詳情：四個區塊渲染、空狀態文字、未解決客訴 Redmine 連結
    - _需求：4.1〜4.4, 5.1〜5.3_
  - [x] 10.3 任一子 Actor 失敗時的錯誤頁面
    - _需求：6.1_
    - 13 項通過。除錯過程中修正了本測試檔自己的一個假陽性：初版斷言錯誤頁面 body 不含「套用篩選」
      字串，但該字串其實也出現在 layout 裡一段跟本頁面無關的 Stimulus controller 程式碼註解中，
      改為只檢查 `<turbo-frame id="project-history-content">` 區塊內沒有 `<form>`／
      `apply-filters-btn`，避免誤判整頁其他地方的巧合字串

- [x] 11. 檢查點 — 全面驗證
  - `bundle exec rspec`：337/337 通過（全專案，含既有 305/306/307 測試零回歸）；`bundle exec rubocop`
    對全部 10 個新檔案無違規；`git status` 確認僅新增本 spec 相關檔案，`config/routes.rb`／
    `app/views/home/index.html.erb`／`app/assets/stylesheets/application.css` 為預期內的擴充修改
    （新增路由、入口卡片、CSS class），未修改任何 305/306/307 既有檔案

---

## Notes

- 全部工作侷限於 `warroom-data-api-prototype/`，不動 `docs/` 靜態原型
- 無真實憑證，僅能以 RSpec stub 驗證邏輯正確性，無法端對端驗證真實 Google Sheets 串接
- `PROJECT_ROSTER_SHEET_NAME` 分頁名稱、300_員工專案的欄位對應皆待實際串接時人工核對一次（比照 307
  `BurndownSheetsClient::SHEET_NAME` 既有的「先合理假設、留人工確認」取捨）
