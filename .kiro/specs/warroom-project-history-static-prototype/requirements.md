# 需求文件

## 簡介

戰情室目前有三個獨立頁面：305 專案進度（`docs/project-progress.html`，任務清單，現已支援
`task_type`／逾期／本週到期等篩選與摘要）、306 臭蟲議題（`docs/issues.html`，月/日 KPI ＋議題明細）、
307 人時燃盡追蹤（`docs/burndown.html`，依專案彙總與逐議題呈現「理想剩餘人時」vs「實際剩餘人時」
燃盡圖，資料來源為獨立的「307_專案人時燃盡追蹤」試算表）。三者都是「當下狀態」或「單一面向趨勢」的
呈現，缺少「跨三個資料來源、隨時間演進」的縱向歷程視角，也沒有跨專案的橫向總覽比較介面。

307 的加入直接補上了本 spec 原本規劃階段「待確認事項」中「花費工時」與「每週進度達成率」兩項的真實
資料來源；另外 `300_員工專案` 試算表（`101fF0GlW2iwjC6TNQnNgKjUrxJg-3Ia5nCYox6haTNM`）提供了「客戶」
「PM」欄位，補上最後一項待確認事項（見下方「待確認事項」，已全數確認完畢）。

本 spec 新增一個**獨立**的「專案歷程」功能，包含兩個新頁面：
- **橫向總覽**：多專案比較，篩選＋甘特圖，比對各專案目前進度
- **縱向歷程**：選定單一專案後，沿時間軸呈現花費工時、每週進度達成率、測試問題數量、客訴議題
  解決狀態的變化

本階段是**靜態 prototype 階段**：在 `docs/` 新增純前端頁面，使用依真實 Google Sheets 欄位結構仿造
的模擬資料，不呼叫任何 API，讓使用者先確認畫面呈現方式，之後才另立 spec 規劃真實 Google Sheets 串接
進 Rails（比照 `warroom-issue-dashboard-static-prototype` → `warroom-issue-dashboard-real-source` 的
既有兩階段模式）。

真實試算表分頁結構（供本 spec 設計模擬資料欄位參考，本階段不呼叫任何 API）：
- 305 專案進度（`功能`／`PR`／`調整`／`遺漏`／`臭蟲` 分頁，經 `task_type` 標記）：
  `project_name, task_name, status, owner, planned_completion_date, actual_completion_date, delay_days, task_type`
  （`status` 為自由輸入中文文字，實際觀察僅 `完成`／`已確認`／`未完成` 三種，前兩者皆視為完成狀態）
- 306 臭蟲議題 `month_kpi`：
  `year_month, complaint, testing, total_bug, block_rate, completed, unresolved, avg_days, sla_rate`
- 306 臭蟲議題 `daily_kpi`：`date, complaint, testing, other, total`
- 306 臭蟲議題 `raw_YYYY`（逐筆 issue 明細）：
  `issue_id, subject, type, tracker, status, assigned_to, start_date, due_date, work_days, project`
- 307 人時燃盡追蹤（獨立試算表 `307_專案人時燃盡追蹤`，固定欄位 A~H ＋ 逐週人時欄位）：
  `project, issue_id, issue_title, assignee, start_date, due_date, status, estimated_hours` ＋
  每週一欄（表頭 `MM/DD`）代表當週實際登記人時。同一 `issue_id` 可能因多人分別填寫而拆成多列，
  需先依 `issue_id` 合併（比照 `docs/js/burndown.js` 的 `mergeRows()`／Rails
  `Sheets::FetchProjectBurndown` 的合併邏輯）。`status` 值為 `未開始`／`執行中`／`已完成`。
- `300_員工專案`（獨立試算表 `101fF0GlW2iwjC6TNQnNgKjUrxJg-3Ia5nCYox6haTNM`，提供客戶／PM 對照）：
  - 「專案清單」表：`專案（全名）, 專案縮寫, 狀態, 比例, 生效月份, 失效月份, 負責RD, 客戶, PM`。
    以「專案」全名欄位為 join key，對應 305/306/307 的 `project_name`／`project` 欄位（實際比對
    `AG 亞炬`、`Virtuous HRM` 等專案名稱與 307 模擬資料一致）。少數列在 PM 欄之後還有一個未標頭的
    第 10 欄含零星人名（例如 `舊振南 PMS` 列的 `邱珮玲`），意義不明（可能是協同 PM 或備註），
    **本 spec 不使用該不明欄位**。
  - 「工程師負載表」：`工程師姓名, 負責專案, 配置比例(%), 生效月份, 失效月份` ＋ 依工程師彙總的
    總負載欄。與 306 static prototype 之前排除的「工程師負載表」為同一性質資料，**本 spec 同樣不
    納入呈現**（見「不納入範圍」）。

### 待確認事項

以下項目已全數確認完畢（307、`300_員工專案` 上線／提供後，皆已改用真實資料結構，不再是假設）：

1. 「客戶」「PM 負責人」欄位**改用 `300_員工專案` 試算表「專案清單」表的 `客戶`／`PM` 欄位**，以
   `專案` 全名對應 305/306/307 的專案名稱（見需求 2）
2. 「花費工時」**改用 307 的 `estimated_hours`（預估人時）與逐週實際登記人時**，不使用 306 頁
   Issue 明細的 `work_days` 欄位（`work_days` 為工作天數，與「花費工時」語意不符；307 才是真正逐週
   記錄實際投入工時的資料來源，見需求 5）
3. 「每週進度達成率」**改為重用 307 既有的「理想剩餘人時」vs「實際剩餘人時」燃盡序列**（依專案彙總，
   或依議題），不再由 305 任務的 `planned_completion_date`／`actual_completion_date` 即時計算完成率
   （307 已有經測試驗證的計算邏輯與视覺化，語意也更精確：「剩餘人時」比「任務筆數達成率」更能反映
   實際進度，見需求 6）
4. 「客訴議題」已解決／未解決的判斷，**不使用** `month_kpi.completed`／`unresolved` 月度彙總欄位，
   改為讀取議題明細清單中每筆客訴議題（`type: Complaint`）自己的 `status` 欄位逐筆判斷（見需求 7）

**不納入範圍**：
- 修改既有 `docs/project-progress.html`、`docs/issues.html`、`docs/burndown.html` 及其對應 JS/邏輯
  （本 spec 只新增獨立頁面，不動 305/306/307 任一既有頁面與程式碼）
- Rails 後端、真實 Google Sheets API 串接、資料庫（留待後續 real-source spec，含 `300_員工專案`
  試算表的串接）
- 新增 Google Sheets 以外的資料來源（如 GitHub commits/PR、Redmine API）
- `300_員工專案` 試算表的「工程師負載表」呈現，以及該表 PM 欄位後方意義不明的第 10 欄
- 任何跨頁面/跨次載入的持久化（篩選狀態、排序狀態等重新整理後不需保留）
- 權限管理、多語系

**技術棧說明**：本 spec 隸屬 `docs/` 靜態站主體，須遵守 `.kiro/steering/project-standards.md` 的技術
限制（純 HTML/CSS/JS、無框架、無建置工具、模擬資料、繁體中文、響應式設計），無例外。

---

## 詞彙表

- **History_Overview_Page**：`docs/project-history-overview.html`，本 spec 新增的多專案橫向總覽頁面。
- **History_Detail_Page**：`docs/project-history-detail.html`，本 spec 新增的單一專案縱向歷程頁面。
- **Entry_Page**：`docs/index.html`，既有入口頁，本 spec 新增兩張卡片連結到上述兩個新頁面，不變更
  既有卡片。
- **模擬資料**：新增 JS 檔案內的常數，依真實 305/306 試算表欄位結構仿造，非讀取自真實 API。
- **任務**：對應 305 專案進度 Sheet 的一列，欄位為 `project_name, task_name, status, owner,
  planned_completion_date, actual_completion_date, delay_days, task_type`。
- **議題**：對應 306 `raw_YYYY` 分頁的一列（同 `warroom-issue-dashboard-static-prototype` 定義）。
- **每日趨勢／月度 KPI**：同 `warroom-issue-dashboard-static-prototype` 定義，分別對應 `daily_kpi`／
  `month_kpi` 分頁。
- **燃盡議題**：對應 307 試算表合併後的一筆議題，欄位為 `project, issue_id, issue_title, assignee,
  start_date, due_date, status, estimated_hours, weekly_actual`（`weekly_actual` 為逐週實際人時陣列）。
  定義同 `warroom-project-burndown-tracking` spec。
- **理想剩餘人時／實際剩餘人時**：同 `warroom-project-burndown-tracking` spec 定義，分別為依起訖日期
  線性分攤、與依逐週實際人時累減得出的每週剩餘人時序列。
- **專案基本資料**：對應 `300_員工專案` 試算表「專案清單」表的一列，欄位為 `project_name（對應
  該表「專案」欄）, customer（客戶）, pm（PM）`，以專案名稱與 305/306/307 資料 join。

---

## 需求

### 需求 1：入口頁新增歷程功能連結

**使用者故事：** 身為戰情室使用者，我希望能從入口頁找到「專案歷程」功能，以便查看跨專案總覽或單一
專案的時間軸。

#### 驗收標準

1. THE **Entry_Page** SHALL 新增至少一張卡片／連結，導向 **History_Overview_Page**。
2. THE **Entry_Page** SHALL 保留既有導向 305、306 頁面的卡片，內容與行為不變。
3. THE **History_Overview_Page** 與 **History_Detail_Page** SHALL 各自提供返回 **Entry_Page** 的連結。

---

### 需求 2：橫向總覽 — 篩選

**使用者故事：** 身為戰情室使用者，我希望能依狀態、客戶、PM 篩選多專案清單，以便快速找到特定條件的
專案。

#### 驗收標準

1. THE **History_Overview_Page** SHALL 提供依「狀態」篩選的下拉選單，預設「全部狀態」。
2. THE **History_Overview_Page** SHALL 提供依「客戶」與依「PM」篩選的下拉選單，各自預設「全部」，
   選項與對應值取自 `300_員工專案` 試算表「專案清單」表的 `客戶`／`PM` 欄位（依專案名稱 join，見
   詞彙表「專案基本資料」）。
3. WHEN 使用者變更狀態、客戶或 PM 任一篩選，THE **History_Overview_Page** SHALL 只顯示同時符合已選
   條件（交集）的專案。
4. WHEN 篩選後無符合條件的專案，THE **History_Overview_Page** SHALL 顯示「目前無符合條件的專案」，
   不留白。

---

### 需求 3：橫向總覽 — 清單／甘特圖檢視切換

**使用者故事：** 身為戰情室使用者，我希望能在清單與甘特圖兩種檢視間切換，以便用適合的方式比較各
專案進度。

#### 驗收標準

1. THE **History_Overview_Page** SHALL 提供「清單」與「甘特圖」兩種檢視模式的切換控制項。
2. THE **History_Overview_Page** SHALL 於清單檢視顯示每個專案的：專案名稱、狀態、預計完成日期、
   實際完成日期（或「進行中」）。
3. THE **History_Overview_Page** SHALL 於甘特圖檢視以簡易 SVG 條狀圖呈現各專案任務的
   `planned_completion_date` 至 `actual_completion_date`（或至今日，若尚未完成）區間，不引入圖表
   框架。
4. THE **History_Overview_Page** SHALL 於頁面載入時預設顯示「清單」檢視。
5. WHEN 使用者切換檢視模式，THE **History_Overview_Page** SHALL 不重新載入頁面（純前端切換）。

---

### 需求 4：縱向歷程 — 專案選擇

**使用者故事：** 身為戰情室使用者，我希望能選擇一個專案查看它的完整歷程。

#### 驗收標準

1. THE **History_Detail_Page** SHALL 提供依「專案」選擇的下拉選單。
2. THE **History_Overview_Page** SHALL 讓使用者可從清單／甘特圖中點擊某專案，直接導向
   **History_Detail_Page** 並預選該專案（透過 URL query string 傳遞專案名稱）。
3. WHEN 使用者變更專案選擇，THE **History_Detail_Page** SHALL 重新渲染需求 5〜7 的所有區塊。
4. IF **History_Detail_Page** 於載入時未帶有效的專案 query string，THEN THE **History_Detail_Page**
   SHALL 預設選中模擬資料中的第一個專案。

---

### 需求 5：縱向歷程 — 花費工時趨勢

**使用者故事：** 身為戰情室使用者，我希望看到所選專案的花費工時隨時間變化，以便掌握投入資源趨勢。

#### 驗收標準

1. THE **History_Detail_Page** SHALL 依所選專案篩選 307 燃盡議題（依 `project` 欄位），以簡易折線圖
   或長條圖（純 SVG，不引入圖表框架）呈現這些議題 `weekly_actual` 逐週實際人時，依專案彙總
   （逐週加總所有議題該週的 `hours`）後的趨勢。
2. WHEN 所選專案於 307 燃盡議題中無任何資料，THE **History_Detail_Page** SHALL 顯示
   「所選專案無工時資料」，不留白。

---

### 需求 6：縱向歷程 — 每週進度達成率（依人時燃盡）

**使用者故事：** 身為戰情室使用者，我希望看到所選專案每週的進度是否符合預期，以便掌握進度是否落後。

#### 驗收標準

1. THE **History_Detail_Page** SHALL 依所選專案彙總 307 燃盡議題的「理想剩餘人時」與「實際剩餘人時」
   週序列（計算邏輯重用 `warroom-project-burndown-tracking` spec 既有定義：理想剩餘人時依議題
   `start_date`／`due_date`／`estimated_hours` 線性分攤，實際剩餘人時依 `estimated_hours` 逐週扣減
   `weekly_actual` 累積人時），依專案將所有議題的兩條序列逐週加總。
2. THE **History_Detail_Page** SHALL 以同一張折線圖疊合呈現「理想剩餘人時」與「實際剩餘人時」兩條線
   （比照 307 燃盡圖的呈現方式，實際線用實線、理想線用虛線）。
3. IF 所選專案任一議題缺少合法 `start_date`／`due_date`（`due_date` 需晚於 `start_date`），THEN THE
   **History_Detail_Page** SHALL 將該議題的理想序列排除在彙總之外，不拋出例外（同 307 既有規則）。

---

### 需求 7：縱向歷程 — 測試問題數量與客訴議題狀態

**使用者故事：** 身為戰情室使用者，我希望看到所選專案的測試問題數量趨勢，以及目前有哪些客訴議題、
已解決幾個，以便掌握品質狀況。

#### 驗收標準

1. THE **History_Detail_Page** SHALL 依所選專案篩選 `daily_kpi`／議題明細中 `type: TestingBug` 的
   議題，呈現測試問題數量隨時間變化的趨勢圖。
2. THE **History_Detail_Page** SHALL 依所選專案篩選議題明細中 `type: Complaint` 的議題，逐筆讀取
   其 `status` 欄位，統計「已解決客訴數」（`status` 為「已結束」或「已解決」）與「未解決客訴數」
   （其餘狀態），不使用 `month_kpi.completed`／`unresolved` 月度彙總欄位。
3. THE **History_Detail_Page** SHALL 列出所選專案目前「未解決」的客訴議題清單（議題編號、主旨、
   狀態、建立日期），議題編號渲染為可點擊連結導向 Redmine 議題頁面
   （`https://redmine.amastek.com.tw/issues/{issue_id}`），比照 306 頁既有連結規則。
4. WHEN 所選專案無任何客訴議題，THE **History_Detail_Page** SHALL 顯示「所選專案無客訴議題」，
   不留白。

---

### 需求 8：模擬資料、語言與響應式設計

**使用者故事：** 身為使用者，我希望頁面在各種裝置上都能正常顯示，且介面語言一致。

#### 驗收標準

1. THE **History_Overview_Page** 與 **History_Detail_Page** SHALL 使用純前端模擬資料（hardcoded
   JavaScript 物件，欄位結構對齊本文件開頭列出的真實試算表分頁結構，含 307 燃盡議題結構），不呼叫
   任何外部 API。
2. THE **History_Overview_Page** 與 **History_Detail_Page** SHALL 使用繁體中文介面。
3. THE **History_Overview_Page** 與 **History_Detail_Page** SHALL 支援桌機、平板、手機版面，使用 CSS
   media query 實作，沿用 `docs/css/style.css` 既有斷點慣例（768px／560px）。
4. THE **History_Overview_Page** 與 **History_Detail_Page** SHALL 沿用既有 `warroom-theme` 深色/淺色
   主題切換機制，不另建獨立主題邏輯。
