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

試算表另有工程師負載表與專案清單表兩個分頁，經評估後**本頁面不呈現**（見「不納入範圍」）。

**不納入範圍**：Rails 後端、真實 Google Sheets API 串接、資料庫、任何跨頁面/跨次載入的持久化、
權限管理、多語系、工程師負載表與專案清單表呈現（評估後排除，Issue 明細已可呈現議題與專案的對應關係，
負載／清單表另需釐清資料維護方式，暫不列入）。

**技術棧說明**：本 spec 隸屬 `docs/` 靜態站主體，須遵守 `.kiro/steering/project-standards.md` 的
技術限制（純 HTML/CSS/JS、無框架、無建置工具、模擬資料、繁體中文、響應式設計），無例外。

---

## 詞彙表

- **Entry_Page**：`docs/index.html`，本 spec 改版後的極簡入口頁，列出可進入的戰情室頁面（305／306）。
- **ProjectProgress_Page**：`docs/project-progress.html`，由既有 `docs/index.html` 內容原樣搬移而來，
  呈現 305 專案進度（沿用既有邏輯，不在本 spec 變更行為）。
- **Issue_Dashboard_Page**：`docs/issues.html`，本 spec 新增的 306 臭蟲議題靜態 prototype 頁面。
- **模擬資料**：`docs/js/issues.js` 內的常數（`MONTH_KPI`、`DAILY_KPI`、`ISSUES`），依真實 306 試算表
  欄位結構仿造，非讀取自真實 API。
- **Redmine_Issue_URL**：議題編號對應的 Redmine 議題頁面連結，格式為
  `https://redmine.amastek.com.tw/issues/{issue_id}`。
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
4. THE **Issue_Dashboard_Page** SHALL 顯示「依專案分類」統計表（客訴／測試／其他數量與總計，依專案
   分組），不以負責人作為統計分類主軸——客訴問題影響範圍為整個專案（全專案成員共同承擔），測試階段
   發現的問題則歸屬個別開發者，兩者分類意義不同，故以「專案」而非「負責人」作為統計主軸。
5. THE **Issue_Dashboard_Page** SHALL 在月度 KPI 區塊顯示說明文字，明確告知：KPI 卡片為月結數字
   （當月進行中尚未結算），而依專案分類統計與議題明細清單皆為即時資料、不受月份選擇影響——避免
   使用者誤以為「當月無資料」（實際上當月議題仍即時顯示於下方，只是月度 KPI 統計要等月底才結算）。
6. THE **Issue_Dashboard_Page** SHALL 確保此說明文字僅出現在月度 KPI 區塊，不得重複出現在議題明細
   的專案／狀態篩選控制項附近，避免使用者誤解為「篩選功能未生效」（專案／狀態篩選實際上會影響下方
   議題明細清單，僅「月份」不影響）。

---

### 需求 3：每日趨勢圖

**使用者故事：** 身為戰情室使用者，我希望看到每日議題數量的趨勢，以便觀察近期是否有異常波動。

#### 驗收標準

1. THE **Issue_Dashboard_Page** SHALL 以簡易折線圖（純 SVG 或 `<canvas>`，不引入圖表框架）呈現每日
   趨勢資料（客訴／測試／其他／總計）。
2. THE **Issue_Dashboard_Page** SHALL 確保趨勢圖不需外部圖表函式庫或建置工具即可運作。
3. WHEN 使用者將滑鼠移至（或觸控點選）圖上某一資料點，THE **Issue_Dashboard_Page** SHALL 顯示該日期
   的詳細數值（tooltip 或等效呈現方式）。
4. THE **Issue_Dashboard_Page** SHALL 顯示縱軸數值刻度（0、中間值、最大值三條水平格線與對應數字）。
5. THE **Issue_Dashboard_Page** SHALL 顯示橫軸日期標籤；WHEN 資料點數量超過可清楚顯示的標籤數（6 個）
   時，THE **Issue_Dashboard_Page** SHALL 等距挑選標籤（含首尾資料點），避免標籤重疊。

---

### 需求 4：Issue 明細清單

**使用者故事：** 身為戰情室使用者，我希望能瀏覽並篩選逐筆議題明細，以便找到特定專案或狀態的議題。

#### 驗收標準

1. THE **Issue_Dashboard_Page** SHALL 顯示 Issue 明細表格，欄位依序為：議題編號、專案、主旨、
   歸屬類型、狀態、負責人、開始日期、到期日期、工作天數（不顯示 `type`／`tracker` 原始欄位，其
   分類意義已由「歸屬類型」徽章呈現，避免重複資訊）。
1a. THE **Issue_Dashboard_Page** SHALL 依 `type` 欄位為每筆議題標示「歸屬類型」徽章：
   `Complaint`（客訴）標示為「專案共同責任」，`TestingBug`（測試）標示為「個人責任」，其餘
   （`Other`）標示為「其他」。
1b. THE **Issue_Dashboard_Page** SHALL 將「議題編號」欄位渲染為可點擊連結，導向對應的
   **Redmine_Issue_URL**（`https://redmine.amastek.com.tw/issues/{issue_id}`），並以新分頁開啟
   （`target="_blank"`，含 `rel="noopener noreferrer"` 避免安全性問題）。
2. THE **Issue_Dashboard_Page** SHALL 提供依「專案」篩選的下拉選單，預設「全部專案」。
3. THE **Issue_Dashboard_Page** SHALL 提供依「狀態」篩選的下拉選單或多選控制項，未帶篩選條件時預設
   選中「新建立」，聚焦最需要處理的新進議題，不預設顯示全部狀態。
4. WHEN 使用者變更專案或狀態篩選，THE **Issue_Dashboard_Page** SHALL 只顯示符合條件的議題列。
5. WHEN 篩選後無符合條件的議題，THE **Issue_Dashboard_Page** SHALL 顯示「目前無符合條件的議題」，
   不留白。

---

### 需求 5：分頁籤呈現（統計摘要／議題資料）

**使用者故事：** 身為戰情室使用者，我希望「月結統計」與「即時明細資料」在畫面上明確分開，不要混在
一起，以便清楚知道哪些內容受月份篩選影響、哪些不受影響。

**背景：** 原設計將全部四個區塊（月度 KPI、每日趨勢、依專案分類、議題明細）依序排列在同一頁面，
頁首單一篩選列同時包含月份／專案／狀態三個下拉選單，容易讓使用者誤以為月份篩選會影響下方所有
區塊（實際上只有月度 KPI 受月份篩選影響，其餘三個區塊皆為即時全量資料）。改為兩個分頁籤呈現，
篩選控制項各自歸屬到其實際影響的分頁籤內，從畫面結構上就消除此歧義。

#### 驗收標準

1. THE **Issue_Dashboard_Page** SHALL 以兩個分頁籤呈現內容：「統計摘要」（月度 KPI ＋每日趨勢）與
   「議題資料」（依專案分類統計＋議題明細）。
2. THE **Issue_Dashboard_Page** SHALL 將月份篩選控制項置於「統計摘要」分頁籤內；THE
   **Issue_Dashboard_Page** SHALL 將專案／狀態篩選控制項置於「議題資料」分頁籤內，不與月份篩選
   共用同一個控制項群組。
3. THE **Issue_Dashboard_Page** SHALL 於頁面載入時預設顯示「統計摘要」分頁籤。
4. THE **Issue_Dashboard_Page** SHALL 確保分頁籤切換不需重新載入頁面或呼叫任何 API（純前端切換）。

---

### 需求 6：模擬資料、語言與響應式設計

**使用者故事：** 身為使用者，我希望頁面在各種裝置上都能正常顯示，且介面語言一致。

#### 驗收標準

1. THE **Issue_Dashboard_Page** SHALL 使用純前端模擬資料（hardcoded JavaScript 物件），不呼叫任何
   外部 API。
2. THE **Issue_Dashboard_Page** SHALL 使用繁體中文介面。
3. THE **Issue_Dashboard_Page** SHALL 支援桌機、平板、手機版面，使用 CSS media query 實作，沿用
   `docs/css/style.css` 既有斷點慣例（768px／560px）。
