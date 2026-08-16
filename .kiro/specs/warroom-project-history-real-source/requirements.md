# 需求文件

## 簡介

`warroom-project-history-static-prototype` 已在 `docs/` 完成「專案歷程」的靜態原型（橫向總覽＋縱向
歷程）。本 spec 是該原型的後續迭代：在既有 `warroom-data-api-prototype` Rails 專案中，比照 305
（`Sheets::FetchProjectProgress`）、306（`Sheets::FetchIssueDashboard`）、307
（`Sheets::FetchProjectBurndown`）既有資料流的模式，新增一組獨立的「專案歷程」資料流與頁面
（`/project_history`），改讀真實 Google Sheets 資料，取代靜態原型的模擬資料。

新增第四個資料來源：`300_員工專案` 試算表（`101fF0GlW2iwjC6TNQnNgKjUrxJg-3Ia5nCYox6haTNM`）「專案
清單」分頁，提供客戶／PM 對照（見需求 1）。與 305/306/307 平行存在，不修改任何一個既有檔案。

**技術棧說明**：延續 `warroom-data-api-prototype` 既有例外（Ruby on Rails 獨立伺服器），不受
`project-standards.md`「技術限制」「響應式設計」段落約束；遵守 `rails-standards.md` 分層慣例與統一
錯誤格式。

**範圍**：讀取 300_員工專案試算表取得客戶／PM；彙總 305 任務資料為橫向總覽（清單＋甘特圖，可依狀態
／客戶／PM 篩選）；彙總 307 燃盡議題資料為單一專案的花費工時趨勢與理想／實際剩餘人時燃盡圖；彙總
306 議題資料為單一專案的測試問題趨勢與客訴議題解決狀態。

**不納入範圍**：JSON API endpoint（比照 307，先做 HTML 頁面）；修改 305/306/307 既有 Client／Actor／
Controller／View／`docs/` 靜態頁；資料庫或任何持久化；`300_員工專案`「工程師負載表」分頁的呈現；
303/305/306/307 四個資料來源之間的專案名稱自動比對修正（目前假設「專案」欄位在各試算表拼寫完全一致，
join 失敗的專案僅是客戶／PM 顯示為空，不視為錯誤，不中斷整頁）。

**已知簡化**（見 design.md 詳細說明）：依專案彙總「花費工時」與「實際剩餘人時」時，若同專案下的議題
開案時間不同、燃盡序列涵蓋的週別範圍不一致，彙總僅加總各議題各自資料涵蓋到的週別，未涵蓋的週別視為
0（不會回推該議題開案前的滿額預估人時）。多數議題同期開案時準確，議題開案時間落差很大時，彙總結果
可能低估較早期的花費工時／剩餘人時。這是延續靜態原型已有的簡化，非本 spec 新增的限制。

---

## 詞彙表

- **ProjectHistory_Page**：`/project_history`，本 spec 新增的 Rails 頁面，同時涵蓋橫向總覽與（帶
  `project` 參數時的）縱向歷程兩種顯示模式，比照 `BurndownController` 單一 action 依參數切換的做法。
- **ProjectRosterSheetsClient**：封裝 `300_員工專案` 試算表讀取的 Client。
- **ProjectRoster_Actor**：`Sheets::FetchProjectRoster`，解析「專案清單」分頁為 `{project_name,
  customer, pm, status}` 陣列。
- **ProjectHistory_Actor**：`Sheets::FetchProjectHistory`，本 spec 的主要業務邏輯 Actor，呼叫上述
  Roster Actor 與既有 305/306/307 三個 Actor，依 `project` 輸入決定回傳總覽彙總或單一專案詳情彙總。
- **join**：以「專案」欄位的字串完全比對，將 Roster 的客戶／PM 資料對應到 305/306/307 各自的專案
  名稱。

---

## 需求

### 需求 1：讀取 300_員工專案「專案清單」

**使用者故事：** 身為後端開發者，我希望 Actor 能讀取 300_員工專案試算表的專案清單，取得客戶／PM
對照，以便橫向總覽頁可依此篩選。

#### 驗收標準

1. WHEN **ProjectRoster_Actor** 被呼叫，THE **ProjectRosterSheetsClient** SHALL 對試算表 ID
   `101fF0GlW2iwjC6TNQnNgKjUrxJg-3Ia5nCYox6haTNM` 讀取「專案清單」分頁（分頁名稱以環境變數
   `PROJECT_ROSTER_SHEET_NAME` 設定，未設定時退回程式碼內建預設值；比照 307
   `BurndownSheetsClient::SHEET_NAME` 的既有慣例，實際分頁名稱待串接時人工確認）。
2. THE **ProjectRoster_Actor** SHALL 依欄位對應解析每一列：`專案（A）, 專案縮寫（B）, 狀態（C）,
   客戶（H）, PM（I）`，跳過「比例／生效月份／失效月份／負責RD」等與本頁面呈現無關的欄位，以及 PM
   欄位後方意義不明的第 10 欄。
3. IF 「專案」欄位為空白，THEN THE **ProjectRoster_Actor** SHALL 跳過該列，不納入輸出；其餘正常列
   不受影響（真實試算表以空白列分隔不同客戶群組）。
4. Google Sheets API 錯誤對應規則與 305/306/307 既有 Actor 一致（`sheet_not_found`／`access_denied`／
   `internal_error`，見 rails-standards.md 對應表）。

---

### 需求 2：橫向總覽 — 篩選與清單

**使用者故事：** 身為戰情室使用者，我希望在 `/project_history` 能依狀態、客戶、PM 篩選多專案清單，
並看到每個專案的預計／實際完成日期。

#### 驗收標準

1. WHEN **ProjectHistory_Page** 未帶 `project` 參數，THE **ProjectHistory_Page** SHALL 顯示橫向總覽：
   以 305 `Sheets::FetchProjectProgress` 的 `grouped_data`（全量、未受任何篩選條件過濾的任務資料）
   依專案彙總「預計完成日期」（該專案任務中最晚的 `planned_completion_date`）與「實際完成日期」
   （該專案任務中最晚的 `actual_completion_date`；任一任務尚無實際完成日期時顯示「進行中」）。
2. THE **ProjectHistory_Page** SHALL 將 **ProjectRoster_Actor** 的客戶／PM／狀態資料，以「專案」欄位
   對應到 305 專案名稱後合併顯示；IF 305 專案名稱在 Roster 中找不到對應列，THEN 客戶／PM／狀態欄位
   顯示 `—`，不視為錯誤、不中斷其餘專案的顯示。
3. THE **ProjectHistory_Page** SHALL 提供依「狀態」（Roster 的「狀態」欄位值）、「客戶」、「PM」三個
   下拉選單篩選，各自預設「全部」；WHEN 使用者同時選取多個條件，THE **ProjectHistory_Page** SHALL
   只顯示同時符合已選條件（交集）的專案。
4. WHEN 篩選後無符合條件的專案，THE **ProjectHistory_Page** SHALL 顯示「目前無符合條件的專案」，
   不留白。

---

### 需求 3：橫向總覽 — 甘特圖

**使用者故事：** 身為戰情室使用者，我希望能切換甘特圖檢視，直接比較各專案任務的時間分佈。

#### 驗收標準

1. THE **ProjectHistory_Page** SHALL 提供清單／甘特圖切換（比照既有 305/306 頁面表單送出模式，切換
   為表單參數 `view=list`／`view=gantt`，送出後停留在同一頁）。
2. THE **ProjectHistory_Page** SHALL 於甘特圖檢視以 SVG 條狀圖呈現各專案任務的 `planned_completion_
   date` 至 `actual_completion_date`（或至今日，若尚未完成）區間，邏輯與 `docs/js/project-history-
   overview.js` 的 `renderGanttChart` 一致（各自獨立實作，Ruby／JS 不共用程式碼，同既有慣例）。

---

### 需求 4：縱向歷程 — 花費工時與燃盡

**使用者故事：** 身為戰情室使用者，我希望選定一個專案後，看到花費工時趨勢與人時燃盡圖。

#### 驗收標準

1. WHEN **ProjectHistory_Page** 帶 `project` 參數，THE **ProjectHistory_Page** SHALL 呼叫
   `Sheets::FetchProjectBurndown.result(project: project, status: "all")` 取得該專案全部燃盡議題
   （含已完成，涵蓋完整歷程而非僅進行中議題）。
2. THE **ProjectHistory_Page** SHALL 依各議題 `actual_series`（剩餘人時）相鄰兩點的差值，反推每週
   實際花費工時（第一週花費 = `estimated_hours − actual_series[0].hours`；第 N 週花費 =
   `actual_series[N-1].hours − actual_series[N].hours`），依日期加總全部議題後，繪製花費工時趨勢圖。
3. THE **ProjectHistory_Page** SHALL 依全部議題彙總「理想剩餘人時」與「實際剩餘人時」兩條序列
   （彙總邏輯見 design.md，需避免因不同議題起訖錨點日期不同而造成彙總線條出現不該有的凹陷——
   `warroom-project-history-static-prototype` 的 JS 版本已修正過同類 bug，本 Ruby 版本採用相同修正
   邏輯：理想線於彙總的每一個日期對每個議題各自算一次當天理想剩餘人時再加總，而非把各議題已含
   起訖錨點的序列直接相加），並疊合繪製為一張圖（重用既有 `docs/burndown.html` 對應的
   `app/views/burndown/_burndown_chart.html.erb` partial 與 `BurndownHelper`，不重寫繪圖邏輯）。
4. WHEN 所選專案於 307 無任何燃盡議題，THE **ProjectHistory_Page** SHALL 顯示「所選專案無工時資料」，
   不留白。

---

### 需求 5：縱向歷程 — 測試問題趨勢與客訴議題狀態

**使用者故事：** 身為戰情室使用者，我希望看到所選專案的測試問題趨勢，以及客訴議題目前解決了幾個、
還有哪些未解決。

#### 驗收標準

1. THE **ProjectHistory_Page** SHALL 呼叫 `Sheets::FetchIssueDashboard.result` 取得全量議題資料
   （不受該 Actor 預設的月份／狀態篩選影響），依 `project` 與 `type: "TestingBug"` 篩選後，依 ISO
   週分組計數，繪製測試問題趨勢圖。
2. THE **ProjectHistory_Page** SHALL 依 `project` 與 `type: "Complaint"` 篩選議題，依議題自己的
   `status` 欄位逐筆判斷已解決（`已結束`／`已解決`）／未解決，顯示統計數字，並列出未解決客訴清單
   （議題編號、主旨、狀態、`start_date`，議題編號連結至 Redmine，比照 306 既有規則）。
3. WHEN 所選專案於 306 無任何客訴議題，THE **ProjectHistory_Page** SHALL 顯示「所選專案無客訴議題」，
   不留白。

---

### 需求 6：錯誤處理

**使用者故事：** 身為使用者，我希望任一資料來源失敗時能看到清楚的錯誤訊息，而不是壞掉的頁面。

#### 驗收標準

1. IF **ProjectRoster_Actor**、305、306、307 四個 Actor 中任一失敗，THEN THE **ProjectHistory_Page**
   SHALL 顯示錯誤訊息，不顯示任何篩選表單或資料區塊（比照 305/306/307 既有 `@error` 呈現慣例），
   HTTP 狀態碼依失敗的 Actor 回傳的 `failure_code` 對應（見 rails-standards.md 對應表）。
