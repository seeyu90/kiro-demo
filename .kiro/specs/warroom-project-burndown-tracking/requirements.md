# Requirements Document

## Introduction

warroom-project-burndown-tracking（307）為 `warroom-data-api-prototype` 新增第三個 Google Sheets
資料來源與頁面：把「307_專案人時燃盡追蹤」試算表（`1A8L0a-5xZSkRpxeN7Gk2Z4O7ZOv4FIy9o2RjQ5odI8k`）
串接為 `/burndown` 頁面，呈現每個議題（來自 303 人時估算表的一列）的「預估人時」如何隨每週實際
登記工時遞減，並可依專案／人員／狀態篩選檢視。

與既有 305（`Sheets::FetchProjectProgress`）、306（`Sheets::FetchIssueDashboard`）資料流平行存在，
不修改兩者任何檔案。

**技術棧說明**：延續 `warroom-data-api-prototype` 既有例外（Ruby on Rails 獨立伺服器，
`google-apis-sheets_v4` + `googleauth` + `service_actor` + `blueprinter`），不受
[project-standards.md](../../steering/project-standards.md)「技術限制」「響應式設計」段落約束；
遵守 [rails-standards.md](../../steering/rails-standards.md) 分層慣例與統一錯誤格式。

**範圍**：讀取 307 試算表、解析每週人時欄位、計算「理想燃盡線」與「實際燃盡線」、單一議題燃盡圖
（依議題清單呈現，每筆可展開／收合查看完整燃盡圖）、依專案／人員／狀態篩選；比照 305
（`docs/project-progress.html`）／306（`docs/issues.html`）既有慣例，同步新增 `docs/burndown.html`
靜態展示頁（模擬資料，供 GitHub Pages 展示用，與 Rails `/burndown` 頁面外觀一致但資料來源各自
獨立）。

**不納入範圍**：JSON API endpoint（先做 HTML 頁面）、303/305/306 資料串接或比對、即時同步、資料庫
持久化、依專案彙總的燃盡圖（上線後移除，見需求 3 的修訂記錄）；`docs/burndown.html` 與 Rails
`/burndown` 兩者資料各自獨立（前者模擬資料、後者真實 Google Sheets），不互相呼叫，不共用程式碼。

> 原始 spec 曾把「單一議題燃盡圖的前端互動展開/收合」列為不納入範圍（規劃先以清單方式全部攤開
> 呈現），但實作最終改用 `<details>`/`<summary>` 讓每個議題可個別展開／收合（見需求 4.1），
> 這裡一併同步移除該項排除說明；「依專案彙總」則是原本規劃內、後來才移除的功能（見需求 3 的
> 修訂記錄），兩者性質不同，不要混淆。

---

## Glossary

- **BurndownSheetsClient**：封裝 307 試算表讀取的 Client（`app/clients/burndown_sheets_client.rb`），
  負責認證、讀取整份已用範圍、UTF-8 重標記。
- **ProjectBurndown_Actor**：`Sheets::FetchProjectBurndown` Actor，解析列資料並計算理想／實際燃盡序列。
- **固定欄位**：試算表 A~H 欄（剩餘人時、專案、議題、人員、議題ID、開案日期、完成日期、預估人時）。
- **週欄位**：I 欄起、表頭為 `MM/DD` 格式的欄位，代表某一週實際登記的人時；隨時間持續向右新增，
  最靠近固定欄位的一欄代表最近一週，往右依序更早。
- **理想剩餘人時**：以「開案日期」「完成日期」「預估人時」線性平均分攤推算出的每週應剩餘人時
  （非讀自試算表儲存格，本 spec 新增的計算邏輯）。
- **實際剩餘人時**：預估人時逐週扣減「週欄位」累積實際人時得到的每週剩餘人時。
- **燃盡圖**：同一張圖表內疊合「理想剩餘人時」與「實際剩餘人時」兩條折線的 SVG 圖表。
- **統一錯誤格式**：`{ "error": { "code": "<錯誤代碼>", "message": "<描述>" } }`（本 spec 僅 HTML 頁面，
  以 `@error` 呈現，不直接輸出此 JSON，但 failure_code 對應規則與既有 spec 一致）。
- **靜態展示頁**：`docs/burndown.html`＋`docs/js/burndown.js`，比照 `docs/issues.html`／
  `docs/js/issues.js` 的做法，純 HTML/CSS/JavaScript、以記憶體內模擬資料呈現燃盡圖，受
  [project-standards.md](../../steering/project-standards.md)「技術限制」「資料與語言」「響應式設計」
  段落約束（本 spec 中僅這部分適用，Rails 部分適用例外）。

---

## Requirements

### 需求 1：讀取 307 試算表

**使用者故事：** 身為後端開發者，我希望 Actor 能從 307 試算表讀取議題人時資料，以便提供給
`/burndown` 頁面呈現。

#### 驗收標準

1. WHEN **ProjectBurndown_Actor** 被呼叫，THE **BurndownSheetsClient** SHALL 對試算表 ID
   `1A8L0a-5xZSkRpxeN7Gk2Z4O7ZOv4FIy9o2RjQ5odI8k` 讀取整份已用範圍（先讀表頭列判斷實際欄數，
   再抓取對應寬度的資料範圍），並指定 `valueRenderOption: 'FORMATTED_VALUE'`。
2. WHEN **ProjectBurndown_Actor** 收到列陣列，THE **ProjectBurndown_Actor** SHALL 跳過第 1 列
   （表頭），並依固定欄位（A~I）對應 `reported_remaining_hours`／`project`／`issue_title`／
   `assignee`／`issue_id`／`start_date`／`due_date`／`status`／`estimated_hours`。
3. IF `project`、`issue_title` 或 `issue_id` 任一為空白，THEN THE **ProjectBurndown_Actor** SHALL 跳過
   該列，不納入輸出；其餘正常列不受影響。
4. WHEN 週欄位儲存格為空白，THE **ProjectBurndown_Actor** SHALL 將該週實際人時視為 0，不拋出例外。
5. WHEN 同一議題（同 `issue_id`）在試算表中拆成多列（例如分別填給不同人員），THE
   **ProjectBurndown_Actor** SHALL 先逐列解析、再依 `issue_id` 合併為單一議題：人員清單取聯集、
   `estimated_hours`／`reported_remaining_hours`／週人時皆加總，`start_date`／`due_date` 取所有
   「`due_date` 不早於 `start_date`」的合法列中最早的開案日與最晚的完成日。
6. THE **ProjectBurndown_Actor** SHALL 依 `status` 欄位（合法值：未開始／執行中／已完成）判斷議題是否
   進行中；合併後同一議題任一列為「未開始」或「執行中」即視為進行中，全部合法列皆為「已完成」才
   視為已完成；沒有任何合法值時，退回以 `due_date` 與目前日期比較（`due_date` 晚於今天視為進行中，
   缺漏或無法解析時一律視為進行中，避免資料不全的議題被誤藏）。

   > 這裡新增了兩則原始 spec 沒有的驗收標準：新增「狀態」欄位（H 欄）本身，以及依 `issue_id`
   > 合併多列的規則。原因是真實試算表資料常見同一議題被拆成多列分別填給不同協作者，且後續
   > 上線後新增了「狀態」欄位取代原本單純依 `due_date` 猜測進行中／已完成的做法（見
   > `tasks.md` task 12.2）；固定欄位也因此從 A~H（8 欄）變成 A~I（9 欄，狀態插在完成日期與
   > 預估人時之間）。

### 需求 2：解析週欄位與跨年份判斷

**使用者故事：** 身為後端開發者，我希望系統能正確判斷每個週欄位對應的實際日期（含年份），以便燃盡圖
的時間軸正確排序。

#### 驗收標準

1. WHEN 表頭列中某欄位符合 `MM/DD` 格式，THE **ProjectBurndown_Actor** SHALL 將其視為一個週欄位。
2. THE **ProjectBurndown_Actor** SHALL 以最靠近固定欄位的週欄位為「最近一週」，以系統目前日期
   （`Date.current`）為錨點推算其年份；若依當年年份推算出的日期晚於錨點 3 天以上，視為去年同週。
3. WHEN 逐一推算後續（更早的）週欄位年份時，IF 依目前推算年份組出的日期晚於前一欄（較近一週）的日期，
   THEN THE **ProjectBurndown_Actor** SHALL 將年份減 1 重新組出日期（代表跨過年底邊界）。
4. IF 某週欄位的 `MM/DD` 無法組成合法日期，THEN THE **ProjectBurndown_Actor** SHALL 跳過該欄位，不納入
   計算，不拋出例外。

### 需求 3：計算理想與實際燃盡序列

**使用者故事：** 身為 PM，我希望在燃盡圖上同時看到「理想進度」與「實際進度」，以便判斷議題是否超支
或落後。

#### 驗收標準

1. WHEN 議題有合法的 `start_date`、`due_date`（`due_date` 晚於 `start_date`）與 `estimated_hours`，
   THE **ProjectBurndown_Actor** SHALL 對每個週欄位日期，依起訖區間的時間比例線性計算「理想剩餘人時」
   （比例 0 時＝`estimated_hours`，比例 1 時＝ 0，早於起始日視為比例 0，晚於完成日視為比例 1）。
2. IF `start_date` 或 `due_date` 缺失或不合法、或 `due_date` 不晚於 `start_date`，THEN THE
   **ProjectBurndown_Actor** SHALL 回傳空的理想序列，不拋出例外；該議題的燃盡圖僅顯示實際線。
3. WHEN 計算「實際剩餘人時」，THE **ProjectBurndown_Actor** SHALL 依週欄位由舊到新的時間順序，將
   `estimated_hours` 逐週扣減累積實際人時。

> 原本這裡有第 4 條「依專案將所有議題的理想／實際剩餘人時序列逐週加總，作為『依專案彙總』燃盡
> 序列輸出」，對應的「依專案彙總燃盡圖」畫面功能已於上線後移除（見 `tasks.md` task 12.1）：
> 多個議題彼此起訖日、預估人時都不同，疊加後的曲線難以判讀，且對使用者沒有實際幫助，改以「依
> 議題呈現的燃盡圖清單」為唯一呈現方式。`Sheets::FetchProjectBurndown` 不再有 `project_series`
> 輸出，`BurndownController`／view 也移除對應區塊；需求文件本次一併同步刪除這條驗收標準。

### 需求 4：`/burndown` 頁面呈現與篩選

**使用者故事：** 身為 PM，我希望能在網頁上依專案、人員或狀態篩選，看到依議題呈現的燃盡圖清單。

#### 驗收標準

1. WHEN 使用者造訪 `/burndown`，THE 頁面 SHALL 顯示依議題呈現的燃盡圖清單（含摘要表與可展開的個別
   議題燃盡圖）。
2. WHEN 使用者選擇專案篩選並送出表單，THE 頁面 SHALL 只顯示該專案的議題燃盡圖。
3. WHEN 使用者選擇人員篩選並送出表單，THE 頁面 SHALL 只顯示該人員名下的議題燃盡圖。
4. WHEN 使用者同時選擇專案篩選、人員篩選與狀態篩選並送出表單，THE 頁面 SHALL 只顯示同時符合全部
   已選條件（交集）的議題燃盡圖。
5. THE 頁面 SHALL 提供狀態篩選（進行中／已完成／全部），未帶參數時預設「進行中」，聚焦目前仍在
   進行的議題，不預設顯示全部（與需求 1.6 判斷「是否進行中」的規則一致）。
6. IF **ProjectBurndown_Actor** 回傳失敗，THEN THE 頁面 SHALL 顯示錯誤訊息，不顯示任何燃盡圖或篩選表單
   中的專案／人員選項（比照 305/306 `@error` 呈現慣例）。

> 原本需求 4.1～4.4 提到的「彙總圖」皆已隨需求 3 的異動一併移除；本次新增第 5 條記載後來才加上、
> 原始 spec 未涵蓋的「狀態」篩選（見 `tasks.md` task 12.2），預設值「進行中」與需求 1.6 的
> 進行中判斷規則相呼應。

### 需求 5：錯誤對應

**使用者故事：** 身為 API 使用者，我希望 Google Sheets API 的各類錯誤能對應至與既有 spec 相同的
failure_code。

#### 驗收標準

1. IF Google Sheets API 回傳 HTTP 404，或分頁名稱不存在，THEN THE **ProjectBurndown_Actor** SHALL 以
   `failure_code: :sheet_not_found` 回傳失敗結果。
2. IF Google Sheets API 回傳 HTTP 403，THEN THE **ProjectBurndown_Actor** SHALL 以
   `failure_code: :access_denied` 回傳失敗結果。
3. IF 發生逾時、配額超過、憑證載入失敗或其他未預期例外，THEN THE **ProjectBurndown_Actor** SHALL 以
   `failure_code: :internal_error` 回傳失敗結果。

### 需求 6：`docs/burndown.html` 靜態展示頁

**使用者故事：** 身為課程/展示網站的訪客，我希望在不需要後端服務的靜態展示站也能看到 307 燃盡圖的
呈現方式，就像現有 305／306 的靜態頁面一樣。

#### 驗收標準

1. THE **靜態展示頁** SHALL 以純 HTML／CSS／JavaScript 實作於 `docs/burndown.html` 與
   `docs/js/burndown.js`，不呼叫任何外部 API，不使用建置工具（比照 `docs/issues.html`／
   `docs/js/issues.js` 的做法）。
2. THE **靜態展示頁** SHALL 使用記憶體內模擬資料（結構比照 307 試算表：專案、議題、人員、議題ID、
   開案日期、完成日期、預估人時、每週人時），模擬資料需涵蓋至少一個「進度落後於理想線」與一個
   「進度優於理想線」的議題範例，以便展示兩條線的視覺差異。
3. WHEN 使用者開啟 `docs/burndown.html`，THE 頁面 SHALL 以與 Rails `/burndown` 頁面相同的視覺呈現
   （依議題呈現的燃盡圖清單、理想線與實際線疊圖、專案／人員／狀態篩選）運作，篩選與圖表繪製邏輯
   全部在瀏覽器端以模擬資料計算完成，不依賴任何伺服器端運算。
4. THE **靜態展示頁** SHALL 支援桌機／平板／手機（CSS media query），並遵循「介面語言使用繁體中文」
   規則。
5. THE `docs/index.html` **入口頁** SHALL 新增一張連結至 `docs/burndown.html` 的入口卡片
   （比照現有「305 專案進度」「306 臭蟲議題」卡片樣式），文字標示「307 人時燃盡追蹤」。

> 第 3 條原本寫「依專案彙總燃盡圖＋議題燃盡圖清單」，比照需求 3、4 的修訂記錄同步移除彙總圖
> 描述；確認過 `docs/js/burndown.js` 本身也只有 `renderIssueSeries`（議題清單），從未實作過
> 依專案彙總，這裡單純是文件沿用了 Rails 端最初的規劃描述、沒有跟著移除的動作同步修正。
