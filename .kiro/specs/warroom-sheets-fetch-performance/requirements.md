# 需求文件

## 簡介

warroom-sheets-fetch-performance 是 [warroom-data-api-real-source](../warroom-data-api-real-source/requirements.md)
的延續。背景：即時向 Google Sheets 5 個類型分頁分別發起 API 請求，每次 Dashboard／API 請求都重打
一輪，速度慢；但實際資料（305 進度表）並非快速變動的內容，不需要每次請求都即時抓取最新值。

本階段範圍：為 `SheetsApiClient` 加入短期快取以降低重複請求造成的延遲，並補齊快取生效後使用者
需要的體驗調整（篩選不寫入網址、載入狀態回饋、資料時效提示、手動重新整理）。

**不納入範圍**：資料庫或 Redis 等外部快取後端（沿用 Rails.cache 既有設定，環境各自的 cache_store
不在本 spec 調整）、即時同步／Webhook、多人協作下的快取一致性、OAuth 使用者登入。

**技術棧說明**：延續 `warroom-data-api-real-source` 的技術選型（Ruby on Rails + Turbo Frame），
不受 `.kiro/steering/project-standards.md` 中「純 HTML/CSS/JS 靜態站」限制約束。

---

## 詞彙表

- **SheetsClient**：`SheetsApiClient`，封裝 Google Sheets API 呼叫，見
  [warroom-data-api-real-source](../warroom-data-api-real-source/requirements.md)。
- **Dashboard_Page**：`GET /dashboard`，`app/views/dashboard/index.html.erb`。
- **篩選表單**：Dashboard 頁面上的專案／任務類型／範圍／只顯示未完成篩選控制項與送出按鈕。
- **project-content frame**：Dashboard 頁面上包裹摘要列與任務清單的 Turbo Frame（`id="project-content"`）。
- **快取存活時間（TTL）**：`SheetsApiClient::CACHE_EXPIRY`，目前為 5 分鐘。

---

## 需求

### 需求 1：Google Sheets 讀取結果快取

**使用者故事：** 身為戰情室使用者，我希望重複開啟 Dashboard 或呼叫 API 不會每次都要等待 5 個分頁
的即時 API 請求，以便更快看到頁面內容。

#### 驗收標準

1. THE **SheetsClient** SHALL 將 `fetch_rows` 的成功結果快取，快取鍵包含目標試算表 ID，快取存活
   時間（TTL）為 5 分鐘。
2. WHEN 快取存在且未過期，THE **SheetsClient** SHALL 直接回傳快取內容，不對 Google Sheets API
   發起任何請求。
3. WHEN 快取不存在或已過期，THE **SheetsClient** SHALL 對 Google Sheets API 發起請求，成功後寫入
   快取並回傳結果。
4. IF 讀取過程拋出例外（額度超過、權限不足、網路錯誤等），THEN THE **SheetsClient** SHALL 不將本次
   結果寫入快取，例外照常向外拋出，下次請求會重新嘗試讀取真實 API（不會被舊錯誤結果卡住）。
5. THE 快取行為 SHALL 使用 Rails 各環境既有的 `Rails.cache` 設定（例如測試環境的 `:null_store`
   會使快取實質停用），不強制指定快取後端。

**狀態**：已實作（見 `app/clients/sheets_api_client.rb` 的 `CACHE_KEY` / `CACHE_EXPIRY`）。

---

### 需求 2：篩選送出不寫入網址

**使用者故事：** 身為戰情室使用者，我希望套用篩選時網址列不要被塞入一長串查詢參數，以便網址保持
簡潔、也不會誤以為篩選結果可以直接分享連結。

#### 驗收標準

1. WHEN 使用者送出篩選表單，THE **Dashboard_Page** SHALL 僅更新 **project-content frame** 的內容
   （摘要列與任務清單），不觸發整頁導覽。
2. WHEN 篩選表單送出後，THE 瀏覽器網址列 SHALL 維持在送出前的網址，不附加或變更任何查詢參數。
3. THE 篩選表單本身（專案下拉選單、任務類型勾選、範圍單選、只顯示未完成開關）的畫面狀態 SHALL 不
   因篩選送出而被重置，維持使用者當下選擇的值。

**狀態**：已實作（`form_with` 加上 `data: { turbo_frame: "project-content" }`）。

---

### 需求 3：篩選送出時的載入狀態回饋

**使用者故事：** 身為戰情室使用者，我希望按下「套用篩選」後能看到畫面正在處理中，以便不會因為快取
過期需要重打 API、回應變慢而誤以為按鈕沒有反應、重複點擊。

#### 驗收標準

1. WHEN 篩選表單送出、等待 **project-content frame** 回應期間，THE **Dashboard_Page** SHALL 顯示
   明確的載入中視覺提示（例如按鈕文字變化、loading 樣式或遮罩）。
2. WHILE **project-content frame** 等待回應，THE 「套用篩選」按鈕 SHALL 停用（disabled），避免使用
   者重複點擊送出多次請求。
3. WHEN **project-content frame** 完成更新（成功或失敗回應皆算），THE 載入中提示 SHALL 消失，
   「套用篩選」按鈕 SHALL 恢復可點擊狀態。
4. THE 載入狀態實作 SHALL 使用 Turbo 既有的 frame 載入事件或 CSS busy 狀態（例如
   `turbo-frame[busy]` / `turbo:submit-start` / `turbo:frame-render`），不需引入額外前端框架或套件。

---

### 需求 4：資料時效提示（選用）

**使用者故事：** 身為戰情室使用者，我希望知道目前畫面上的資料是多久以前抓取的，以便判斷要不要手動
刷新以取得最新內容。

#### 驗收標準

1. WHEN **Dashboard_Page** 顯示任務清單，THE **Dashboard_Page** SHALL 顯示一段文字提示目前資料的
   快取時間（例如「資料更新於 3 分鐘前」）。
2. IF 本次回應為即時讀取（快取未命中，剛從 Google Sheets API 取得），THEN THE 提示文字 SHALL 反映
   資料為剛剛更新（例如「資料剛剛更新」），不得誤顯示為快取多分鐘前的舊資訊。
3. THE 資料時效判斷 SHALL 以 **SheetsClient** 寫入快取的時間點為準，不需額外資料庫或外部儲存。

---

### 需求 5：手動重新整理（選用）

**使用者故事：** 身為戰情室使用者，我希望在快取尚未過期時也能主動要求抓取最新資料，以便剛在
Google Sheet 上改完東西後能立刻在 Dashboard 上看到，而不用等待最長 5 分鐘的快取存活時間。

#### 驗收標準

1. THE **Dashboard_Page** SHALL 提供一個「重新整理資料」控制項（按鈕）。
2. WHEN 使用者點擊「重新整理資料」，THE **SheetsClient** SHALL 略過現有快取，對 Google Sheets API
   發起即時請求，並以新結果覆寫快取。
3. WHEN 「重新整理資料」觸發的請求進行中，THE **Dashboard_Page** SHALL 套用需求 3 定義的載入狀態
   回饋。
4. WHEN 「重新整理資料」的請求失敗，THE **Dashboard_Page** SHALL 顯示既有的錯誤訊息呈現方式
   （沿用 `Sheets::FetchProjectProgress` 既有的 `failure_code` / `message` 錯誤處理），不因手動
   刷新失敗而讓快取內的舊資料被清除或遺失。
