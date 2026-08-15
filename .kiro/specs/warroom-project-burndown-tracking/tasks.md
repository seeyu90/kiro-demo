# 實作計畫：307 專案人時燃盡追蹤

## 概述

把 307 試算表（`1A8L0a-5xZSkRpxeN7Gk2Z4O7ZOv4FIy9o2RjQ5odI8k`）串接為 `/burndown` 頁面，實作於
`warroom-data-api-prototype`，遵循 [rails-standards.md](../../steering/rails-standards.md) 分層。
與既有 305／306 資料流平行存在，不修改兩者任何檔案。範圍涵蓋固定欄位解析、週欄位年份推算、理想／
實際燃盡序列計算、依專案彙總、依專案／人員篩選；JSON API endpoint 不納入本次範圍。同時比照
305／306 慣例，新增 `docs/burndown.html` 純靜態展示頁（模擬資料，供 GitHub Pages 展示，與 Rails
`/burndown` 各自獨立，見 Task 11）。

---

## 任務

- [x] 1. `BurndownSheetsClient`
  - [x] 1.1 新增 `app/clients/burndown_sheets_client.rb`
    - 依 [design.md](design.md) 實作動態欄寬讀取（先讀表頭列換算最後一欄字母，再讀整份資料範圍）
    - 沿用既有 UTF-8 重標記、憑證讀取（Rails credentials → ENV fallback）邏輯
    - `SHEET_NAME` 常數先以佔位值 `"工作表1"` 實作，並加註解說明需在實際串接時確認真實分頁名稱
    - _需求：1.1_
  - [x] 1.2 單元測試：`spec/clients/burndown_sheets_client_spec.rb`
    - stub `SheetsService`，驗證動態欄寬換算（含欄數超過 26 需要雙字母欄位代號的邊界情況）、
      UTF-8 重標記、憑證 fallback、Google API 錯誤原樣拋出

- [x] 2. `Sheets::FetchProjectBurndown` — 固定欄位解析
  - [x] 2.1 新增 `app/actors/sheets/fetch_project_burndown.rb`，實作固定欄位（A~H）解析
    - `project`／`issue_title`／`issue_id` 任一空白則跳過該列；空列跳過
    - _需求：1.2, 1.3_
  - [x] 2.2 週欄位空白視為 0 人時
    - _需求：1.4_

- [x] 3. 週欄位年份推算
  - [x] 3.1 實作表頭週欄位解析（`MM/DD` 格式偵測）與年份推算演算法
    - 第一欄（最近一週）以 `Date.current` 為錨點；若依當年年份組出的日期**晚於錨點 3 天以上**才視為
      去年同週（年份減 1），3 天內仍算今年（容錯窗口，避免週初填表時的邊界誤判）
    - 後續欄位「依目前推算年份組出的日期晚於前一欄（較近一週）的日期」時年份減 1 重新組出日期
    - 無法組成合法日期的欄位整欄跳過，不拋出例外
    - _需求：2.1, 2.2, 2.3, 2.4_
  - [x] 3.2 單元測試：涵蓋跨年邊界（例如 01/05 → 12/29）、非法日期（如 2/30）跳過

- [x] 4. 理想／實際燃盡序列計算
  - [x] 4.1 實作實際序列：依日期由舊到新排序後累加人時，`estimated_hours` 逐週扣減
    - _需求：3.3_
  - [x] 4.2 實作理想序列：線性比例分攤，起訖日缺失或不合法時回傳空陣列
    - _需求：3.1, 3.2_
  - [x] 4.3 實作依專案彙總（依日期加總同專案所有議題的兩條序列）
    - _需求：3.4_
  - [x] 4.4 單元測試：涵蓋起訖日缺失、單一議題序列計算、多議題彙總

- [x] 5. 錯誤處理
  - [x] 5.1 在 `call` 補上 `rescue Google::Apis::ClientError` 三段式對應與 `rescue => e`
    - _需求：5.1, 5.2, 5.3_
  - [x] 5.2 單元測試：404／403／其他例外皆對應正確 `failure_code`

- [x] 6. `BurndownIssueBlueprint`
  - [x] 6.1 新增 `app/blueprints/burndown_issue_blueprint.rb`（依 design.md 欄位清單）

- [x] 7. `BurndownController`
  - [x] 7.1 新增 `app/controllers/burndown_controller.rb`：呼叫 Actor、篩選（含專案＋人員同時篩選時
    取交集）、`build_failure`
    - _需求：4.2, 4.3, 4.4, 4.5_
  - [x] 7.2 `config/routes.rb` 新增 `get "/burndown", to: "burndown#index"`

- [x] 8. View 與 Helper
  - [x] 8.1 新增 `app/helpers/burndown_helper.rb`（燃盡圖座標計算，仿 `IssuesHelper` trend chart）
  - [x] 8.2 新增 `app/views/burndown/_burndown_chart.html.erb`（雙折線 SVG partial）
  - [x] 8.3 新增 `app/views/burndown/index.html.erb`（篩選表單＋專案彙總圖＋議題燃盡圖清單）
    - _需求：4.1_
  - [x] 8.4 CSS：於 `app/assets/stylesheets/application.css` 新增理想線／實際線樣式類別

- [x] 9. Request spec
  - [x] 9.1 新增 `spec/requests/burndown_spec.rb`：stub `BurndownSheetsClient.fetch_rows`，驗證成功／
    失敗渲染、專案與人員篩選（含兩者同時篩選的交集情境）、空資料 empty state
    - _需求：4.4, 4.5_

- [x] 10. 全專案回歸
  - [x] 10.1 執行 `bundle exec rspec`，確認全數通過、不影響既有 305／306 測試

- [x] 11. `docs/burndown.html` 靜態展示頁
  - [x] 11.1 新增 `docs/js/burndown.js`：模擬資料常數（比照 design.md「docs/ 靜態展示頁」段落的欄位
    結構），至少一筆落後範例、一筆超前範例
    - _需求：6.2_
  - [x] 11.2 實作 `computeIdealSeries`／`computeActualSeries`／`sumProjectSeries`（純 JS，邏輯對齊
    Ruby Actor 版本但各自獨立實作）
    - _需求：6.3_
  - [x] 11.3 實作雙折線 SVG 繪圖函式（比照 `docs/js/issues.js` 的 `renderTrendChart`，新增理想線
    `stroke-dasharray` 虛線樣式），專案彙總與單一議題共用同一函式
    - _需求：6.1, 6.3_
  - [x] 11.4 新增 `docs/burndown.html`：header／返回入口頁／深色淺色切換（比照 `docs/issues.html`）、
    專案／人員 `<select>` 篩選（change 事件即時重繪，不需送出按鈕）、專案彙總圖區塊、議題燃盡圖清單
    - _需求：6.1, 6.3, 6.4_
  - [x] 11.5 CSS：於 `docs/css/style.css` 新增燃盡圖兩條線樣式類別（與 Rails 端同名，維持視覺一致）
  - [x] 11.6 `docs/index.html` 新增連結至 `burndown.html` 的入口卡片（「307 人時燃盡追蹤」）
    - _需求：6.5_

- [ ] 12. 上線後修正（依真實試算表資料與人工驗證回饋，補在 Task 1~11 之後）
  - [x] 12.1 移除「依專案彙總燃盡圖」：多議題不同起訖日／預估人時疊加後曲線難以判讀，且對使用者
    沒有實際幫助，改以「議題燃盡圖」清單為唯一呈現方式（`Sheets::FetchProjectBurndown` 移除
    `project_series` output／`aggregate_project_series`；`BurndownController` 移除
    `@project_series`；view 移除對應區塊）
  - [x] 12.2 依 `issue_id` 合併議題多列＋狀態欄位判斷進行中：真實資料常見同一議題拆給多位人員
    分別填一列，改為先逐列解析（`parse_row`）再依 `issue_id` 合併（`merge_rows`：人員清單、
    預估／剩餘人時加總、週人時加總、起訖日取合法列 min/max）；試算表新增「狀態」欄位（H 欄，
    未開始／執行中／已完成），優先依此判斷進行中／已完成，欄位無法辨識時退回 `due_date` 與
    今天比較；新增狀態篩選（進行中／已完成／全部），預設只顯示進行中
  - [ ] 12.3 燃盡圖繪製修正：單一議題燃盡圖裁切為只顯示「開案週（正規化到當週週一）」之後的
    週次，不套用整份試算表的完整週範圍；理想線頭尾補上開案／完成錨點（正規化到當週週一），
    確保斜線一定完整畫到底，不受試算表目前週欄位範圍侷限；Y 軸改為同時考慮最小值（可為負，
    支援實際超支情境）與最大值，並在跨越 0 時額外補一條 0 格線；篩選表單改用 Turbo Frame
    （比照 305／306 既有做法），送出篩選不再讓瀏覽器網址列被填入 query string
  - [ ] 12.4 新增多人議題的累積消耗人時堆疊圖：同一議題有多位人員時，卡片下方新增堆疊面積圖
    （每人一色，依 `per_assignee` 累積消耗人時堆疊，另附總預估人時參考虛線與圖例），取代
    「各自剩餘人時 vs. 議題整體理想線」基準不一致、容易誤導判讀進度落後的方案
  - [ ] 12.5 `docs/burndown.html` 靜態展示頁同步：比照 Rails 端上述修正（移除專案彙總圖、
    模擬資料補狀態欄位與合併邏輯、燃盡圖裁切與錨點、Y 軸負值支援、堆疊圖），JS 端各自獨立
    實作（不與 Ruby Actor 共用程式碼，維持既有慣例）
  - [ ] 12.6 README／規範文件同步更新目前功能與進度
