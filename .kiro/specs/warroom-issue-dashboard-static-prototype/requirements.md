# 需求文件

## 簡介

戰情室目前只呈現 305 專案進度資料。306（臭蟲議題紀錄）在 `warroom-data-api-prototype` 與
`warroom-data-api-real-source` 兩份 requirements.md 中皆明確列為「不納入範圍，留待後續迭代再議」。
本 spec 是該後續迭代的第一階段：在 `docs/` 靜態展示站新增一個 306 臭蟲議題的**靜態 prototype 頁面**
（模擬資料），讓使用者先確認畫面呈現方式，之後才另立 spec 規劃真實 Google Sheets 306 試算表
（`306_臭蟲議題紀錄`）串接進 Rails（`warroom-data-api-prototype` 架構）。

真實 306 試算表分頁結構（供本 spec 設計模擬資料欄位參考，本階段不呼叫任何 API）：
- `month_kpi`：`year_month, 客訴, 測試, 總Bug, 攔截率, 完成數, 未結案, 平均天數, SLA達標率, Top3`
- `daily_kpi`：`日期, 客訴, 測試, 其他, 總計, 未結束數量, 未結束IDs, slack_message`
- `raw_2023`〜`raw_2026`（逐筆 issue 明細，欄位一致）：
  `issue_id, subject, type, tracker, status, assigned_to, start_date, due_date, work_days, sheet_name, project`
- 工程師負載表：`工程師姓名, 負責專案, 配置比例(%), 生效月份, 失效月份, 工程師姓名(總負載), 當月配置總佔比合計`
- 專案清單表：`專案, 專案縮寫, 狀態, 比例, 生效月份, 失效月份, 負責RD`

**不納入範圍**：Rails 後端、真實 Google Sheets API 串接、資料庫、任何跨頁面/跨次載入的持久化、
權限管理、多語系。

**技術棧說明**：本 spec 隸屬 `docs/` 靜態站主體，須遵守 `.kiro/steering/project-standards.md` 的
技術限制（純 HTML/CSS/JS、無框架、無建置工具、模擬資料、繁體中文、響應式設計），無例外。

---

## 詞彙表

- **Entry_Page**：`docs/index.html`，本 spec 改版後的極簡入口頁，列出可進入的戰情室頁面（305／306）。
- **ProjectProgress_Page**：`docs/project-progress.html`，由既有 `docs/index.html` 內容原樣搬移而來，
  呈現 305 專案進度（沿用既有邏輯，不在本 spec 變更行為）。
- **Issue_Dashboard_Page**：`docs/issues.html`，本 spec 新增的 306 臭蟲議題靜態 prototype 頁面。
- **模擬資料**：`docs/js/issues.js` 內的常數（`MONTH_KPI`、`DAILY_KPI`、`ISSUES`、`ENGINEER_LOAD`、
  `PROJECT_LIST`），依真實 306 試算表欄位結構仿造，非讀取自真實 API。
- **月度 KPI**：對應真實試算表 `month_kpi` 分頁的單月統計列。
- **每日趨勢**：對應真實試算表 `daily_kpi` 分頁的逐日統計列。
- **Issue 明細**：對應真實試算表 `raw_2023`〜`raw_2026` 分頁合併後的逐筆議題紀錄。

---

## 需求

### 需求 1：入口頁改版

**使用者故事：** 身為戰情室使用者，我希望有一個入口頁可以選擇要看 305 專案進度還是 306 臭蟲議題，以便快速前往需要的頁面。

#### 驗收標準

1. THE **Entry_Page** SHALL 以 `docs/index.html` 提供，內容改為極簡入口頁，不包含任何資料邏輯。
2. THE **Entry_Page** SHALL 提供至少兩個明顯的連結／卡片，分別導向 **ProjectProgress_Page**
   （`project-progress.html`）與 **Issue_Dashboard_Page**（`issues.html`）。
3. THE **ProjectProgress_Page** SHALL 呈現與既有 `docs/index.html`（搬移前）完全相同的內容與互動行為，
   不因搬移而改變任何既有功能。

---

### 需求 2：KPI 摘要卡片

**使用者故事：** 身為戰情室使用者，我希望一打開 306 頁面就能看到當月關鍵指標，以便快速掌握整體狀況。

#### 驗收標準

1. THE **Issue_Dashboard_Page** SHALL 顯示月度 KPI 摘要卡片，欄位涵蓋：客訴、測試、總Bug、攔截率、
   完成數、未結案、平均天數、SLA達標率。
2. THE **Issue_Dashboard_Page** SHALL 提供月份選擇（下拉選單），預設選中模擬資料中最新月份。
3. WHEN 使用者切換月份，THE **Issue_Dashboard_Page** SHALL 更新 KPI 摘要卡片為所選月份的數值。
4. THE **Issue_Dashboard_Page** SHALL 顯示所選月份的 Top3 責任人排行（姓名與數量）。

---

### 需求 3：每日趨勢圖

**使用者故事：** 身為戰情室使用者，我希望看到每日議題數量的趨勢，以便觀察近期是否有異常波動。

#### 驗收標準

1. THE **Issue_Dashboard_Page** SHALL 以簡易折線圖（純 SVG 或 `<canvas>`，不引入圖表框架）呈現每日
   趨勢資料（客訴／測試／其他／總計）。
2. THE **Issue_Dashboard_Page** SHALL 確保趨勢圖不需外部圖表函式庫或建置工具即可運作。
3. WHEN 使用者將滑鼠移至（或觸控點選）圖上某一資料點，THE **Issue_Dashboard_Page** SHALL 顯示該日期
   的詳細數值（tooltip 或等效呈現方式）。

---

### 需求 4：Issue 明細清單

**使用者故事：** 身為戰情室使用者，我希望能瀏覽並篩選逐筆議題明細，以便找到特定專案或狀態的議題。

#### 驗收標準

1. THE **Issue_Dashboard_Page** SHALL 顯示 Issue 明細表格，欄位涵蓋：issue_id、subject、type、
   tracker、status、assigned_to、start_date、due_date、work_days、project。
2. THE **Issue_Dashboard_Page** SHALL 提供依「專案」篩選的下拉選單，預設「全部專案」。
3. THE **Issue_Dashboard_Page** SHALL 提供依「狀態」篩選的下拉選單或多選控制項，預設顯示全部狀態。
4. WHEN 使用者變更專案或狀態篩選，THE **Issue_Dashboard_Page** SHALL 只顯示符合條件的議題列。
5. WHEN 篩選後無符合條件的議題，THE **Issue_Dashboard_Page** SHALL 顯示「目前無符合條件的議題」，
   不留白。

---

### 需求 5：工程師負載與專案清單

**使用者故事：** 身為戰情室使用者，我希望看到工程師目前的配置負載與專案清單，以便了解人力分配狀況。

#### 驗收標準

1. THE **Issue_Dashboard_Page** SHALL 顯示工程師負載表格，欄位涵蓋：工程師姓名、負責專案、
   配置比例、生效月份、失效月份、當月配置總佔比合計。
2. THE **Issue_Dashboard_Page** SHALL 顯示專案清單表格，欄位涵蓋：專案、專案縮寫、狀態、比例、
   生效月份、失效月份、負責RD。
3. 此兩張表格 SHALL 各自獨立區塊呈現，不與 Issue 明細清單共用篩選條件。

---

### 需求 6：模擬資料、語言與響應式設計

**使用者故事：** 身為使用者，我希望頁面在各種裝置上都能正常顯示，且介面語言一致。

#### 驗收標準

1. THE **Issue_Dashboard_Page** SHALL 使用純前端模擬資料（hardcoded JavaScript 物件），不呼叫任何
   外部 API。
2. THE **Issue_Dashboard_Page** SHALL 使用繁體中文介面。
3. THE **Issue_Dashboard_Page** SHALL 支援桌機、平板、手機版面，使用 CSS media query 實作，沿用
   `docs/css/style.css` 既有斷點慣例（768px／560px）。
