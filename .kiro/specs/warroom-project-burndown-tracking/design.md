# Design Document

## 概述

比照 305/306 的四層架構（Controller → Actor → Client → Blueprint），新增第三條平行資料流，讀取
307 試算表並在 `/burndown` 呈現燃盡圖。不共用 305/306 的 Client／Actor 檔案，僅共用憑證讀取慣例與
View 層的 inline SVG 折線技巧（`IssuesHelper` 的做法）。

同時比照 305（`docs/project-progress.html`）／306（`docs/issues.html`）既有慣例，新增
`docs/burndown.html` 純靜態展示頁（模擬資料，見本文件末段「docs/ 靜態展示頁」）。兩份實作
（Rails `/burndown` 與 `docs/burndown.html`）視覺呈現一致，但資料來源與程式碼完全獨立。

## 元件與介面

### BurndownSheetsClient（`app/clients/burndown_sheets_client.rb`）

- `SPREADSHEET_ID = "1A8L0a-5xZSkRpxeN7Gk2Z4O7ZOv4FIy9o2RjQ5odI8k"`
- 分頁名稱常數 `SHEET_NAME`：目前以 Google Sheets 新試算表預設分頁名稱 `"工作表1"` 佔位；
  串接時若與實際分頁名稱不符需修正（同 306 real-source spec Task 1 的做法，本 spec 未走「解析
  xlsx workbook.xml 確認官方分頁清單」流程，留待實際串接／人工開啟試算表時修正）。
- **動態欄寬**：先以 `A1:ZZ1` 讀表頭列，取該列陣列中**最後一個非空元素的索引**（而非非空元素的
  「數量」）換算出最後一欄的 A1 表示法字母，再以 `A1:<last_col><MAX_DATA_ROWS>` 讀整份資料
  （`MAX_DATA_ROWS = 500`，足夠涵蓋可預期的議題列數）。取此索引而非計數的原因：Sheets API
  回傳的列陣列僅省略「尾端」空白儲存格，中間若出現空白仍會保留為空字串佔位，若改用「非空欄數」
  換算會在表頭中間有空白時算出過窄的欄位範圍，靜默漏掉後面的週欄位資料。
  取捨：不做「每次呼叫都精準抓取實際列數」的第二次探測，改用固定上限列數換取實作簡單
  （karpathy-guidelines 最簡方案），500 列遠大於現有 307 試算表的實際列數。
- 沿用 `IssueSheetsClient` 的 UTF-8 重標記（`force_encoding(Encoding::UTF_8)`）與憑證讀取
  （Rails credentials → ENV fallback）邏輯，維持獨立實作不抽共用 module（同既有取捨）。

### Sheets::FetchProjectBurndown（`app/actors/sheets/fetch_project_burndown.rb`）

`output :issues`（Array<Hash>）、`output :project_series`（Hash，`project_name => { ideal_series:,
actual_series: }`）。

**列解析**：固定欄位 A~H → `reported_remaining_hours, project, issue_title, assignee, issue_id,
start_date, due_date, estimated_hours`；`project`／`issue_title`／`issue_id` 任一空白則跳過整列。
每一列解析完成後，需依下方「理想／實際序列計算」規則計算該議題自己的 `ideal_series`／
`actual_series`，一併寫入該議題的 Hash（`BurndownIssueBlueprint` 的 `:actual_series`／
`:ideal_series` 欄位即取自這裡，並非只在 `project_series` 彙總階段才產生）；`project_series`
是把所有議題已算好的兩條序列，再依專案、依日期加總一次。

**週欄位解析與年份推算**（見 requirements.md 需求 2）：

```
週欄位（表頭 MM/DD）→ 由左到右（最近→最早）逐一推算年份：
  第一欄：year = Date.current.year；若組出日期 > Date.current + 3天 → year -= 1
  後續欄：先沿用目前 year 組日期；若該日期 > 前一欄（較近一週）的日期 → year -= 1 重新組
```

無法組成合法日期（如 2/30）的欄位整欄跳過，不納入任何議題的週序列。

**理想／實際序列計算**（見 requirements.md 需求 3）：

- 實際序列：週欄位依日期由舊到新排序後，逐週累加該欄位人時，`remaining = estimated_hours -
  累積人時`。
- 理想序列：`due_date` 需晚於 `start_date` 且兩者皆合法才計算，否則回傳空陣列（不拋例外）；
  以線性比例 `(week_date - start_date) / (due_date - start_date)`（clamp 至 0..1）算出理想剩餘人時。
- 專案彙總序列：因所有議題共用同一份週欄位（同一張試算表、同一表頭），彙總時可直接依「日期」為 key
  將同專案議題的序列逐週加總，不需額外做日期對齊/插值。

**錯誤處理**：`rescue Google::Apis::ClientError` 三段式（404/403/其他）+ `rescue => e` 皆對應
`failure_code`，比照既有 `Sheets::FetchIssueDashboard` 的做法
（`warroom-data-api-prototype/app/actors/sheets/fetch_issue_dashboard.rb`）。

### BurndownIssueBlueprint（`app/blueprints/burndown_issue_blueprint.rb`）

`identifier :issue_id`；`fields :project, :issue_title, :assignee, :start_date, :due_date,
:estimated_hours, :reported_remaining_hours, :actual_series, :ideal_series`。與既有 `IssueBlueprint`
一樣直接對 Hash 物件（Actor 輸出）渲染。`reported_remaining_hours`（A 欄，PM 手動填寫的剩餘人時）
僅供頁面顯示參考，不參與 `ideal_series`／`actual_series` 的計算，也不做兩者的交叉校驗；本 spec
不處理「手填剩餘人時」與「計算出的剩餘人時」不一致的情況。

### BurndownController（`app/controllers/burndown_controller.rb`）

呼叫 `Sheets::FetchProjectBurndown.result`；成功時計算 `@projects`／`@assignees`（供篩選下拉選單）、
依 `params[:project]`／`params[:assignee]` 篩選 `@filtered_issues`（**兩者皆有值時取交集 AND**，
只有同時符合所選專案與所選人員的議題才會出現在議題燃盡圖清單中），並依 `@selected_project` 篩選
`@project_series`（未選則顯示全部專案彙總圖；`@selected_assignee` 不影響 `@project_series`，
比照 requirements.md 需求 4.3）。失敗時比照 305/306 `build_failure` 慣例清空所有 instance variable
並設定 `@error`。

### View（`app/views/burndown/`）

- `index.html.erb`：沿用 dashboard 頁 header／篩選表單（按鈕送出，非逐項自動送出）樣式；先列出專案
  彙總燃盡圖，再列出（依篩選後的）議題燃盡圖清單。
- `_burndown_chart.html.erb`：單一 partial，接受 `ideal_series`／`actual_series`／`title` 三個
  local，同一張 SVG 內畫兩條 `polyline`（`actual` 實線、`ideal` 虛線 `stroke-dasharray`），供專案彙總
  與單一議題共用。
- `BurndownHelper`：仿 `IssuesHelper` 的 trend chart 座標計算方法，新增 `burndown_chart_points`／
  `burndown_chart_polyline`／`burndown_chart_max`／`burndown_chart_y_ticks`／`burndown_chart_x_labels`。
  CSS 沿用既有 `.trend-svg`／`.trend-gridline`／`.trend-axis-label`，僅新增兩條線各自的樣式類別。

### Route

`config/routes.rb` 新增 `get "/burndown", to: "burndown#index"`。本次不新增 JSON API endpoint
（見 requirements.md「不納入範圍」）。

### docs/ 靜態展示頁（`docs/burndown.html` ／ `docs/js/burndown.js`）

與 Rails `/burndown` 完全獨立的第二份實作，資料、篩選、繪圖邏輯皆在瀏覽器端以純 JavaScript
完成，比照 `docs/issues.html`／`docs/js/issues.js` 的做法（IIFE、`createElementNS` 手繪 SVG，不用
任何框架或建置工具）。

- **模擬資料**：`docs/js/burndown.js` 內以陣列常數 `BURNDOWN_ISSUES` 模擬 307 試算表列（每筆含
  `project, issue_id, issue_title, assignee, start_date, due_date, estimated_hours, weekly_actual:
  [{date, hours}, ...]`），週資料直接以陣列存放（不需要模擬「MM/DD 表頭＋跨年推算」這個 Rails
  端特有的解析步驟，因為模擬資料可以直接寫成完整 ISO 日期）。至少包含一筆「累積實際人時超過理想
  進度」（落後／超支）與一筆「累積實際人時低於理想進度」（超前）的範例，用來在展示頁上直接看出
  兩條線分岔的視覺效果。
- **理想／實際序列計算**：JS 版重寫一次 `computeIdealSeries`／`computeActualSeries`／
  `sumProjectSeries`，邏輯與 design.md「Sheets::FetchProjectBurndown」段落的 Ruby 版本一致（線性比例
  分攤、依日期累加），但兩邊各自獨立實作（不共用程式碼——一邊是瀏覽器 JS、一邊是 Rails Ruby，本來就
  無法共用；也符合 project-standards.md 靜態站不呼叫外部服務的限制）。
- **繪圖**：比照 `docs/js/issues.js` 的 `renderTrendChart`（`createElementNS` 建立 `<svg>`、格線、
  座標軸標籤、`<polyline>`、`<circle>` 資料點），新增第二條 `<polyline>`（理想線，`stroke-dasharray`
  虛線樣式）疊在同一張 SVG 上；同一份繪圖函式供「專案彙總」與「單一議題」兩種呼叫情境共用（傳入
  不同的 series 資料）。
- **頁面結構**：`docs/burndown.html` 比照 `docs/issues.html` 的 header／`back-link` 返回入口頁／
  `theme-toggle` 深色淺色切換；篩選區使用 `<select>`（專案／人員）＋即時（change 事件）重繪，不需要
  表單送出按鈕（靜態頁沒有伺服器往返成本，比照 `docs/issues.html` 現有的即時篩選模式，而非 Rails
  `/burndown` 因表單送出才重新查詢 API 的按鈕送出模式）。
- **CSS**：沿用 `docs/css/style.css` 既有的 `.trend-svg`／`.trend-gridline`／`.trend-axis-label`／
  `.dashboard-header`／`.entry-card` 等類別，僅新增燃盡圖兩條線各自的樣式類別（與 Rails 端
  `application.css` 新增的類別同名，維持視覺一致）。
- **入口頁**：`docs/index.html` 的 `.entry-grid` 新增一張 `.entry-card`，連結至 `burndown.html`，
  文案比照現有兩張卡片的風格（標題「307 人時燃盡追蹤」＋一行描述）。

## 測試策略

- `spec/actors/sheets/fetch_project_burndown_spec.rb`：直接測試私有方法（`.send`，比照既有慣例）—
  週欄位年份推算（含跨年邊界、非法日期跳過）、理想/實際序列計算（含起訖日缺失時理想序列為空）、
  專案彙總加總、必要欄位空白跳過、三種 failure_code 情境。
- `spec/requests/burndown_spec.rb`：stub `BurndownSheetsClient.fetch_rows`，驗證頁面成功/失敗渲染、
  專案與人員篩選生效、無資料時的 empty state。
