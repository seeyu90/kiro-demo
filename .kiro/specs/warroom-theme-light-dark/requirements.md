# 需求文件

## 簡介

戰情室目前有兩個獨立實作、視覺結構相同但技術棧不同的 Dashboard 頁面：
1. `docs/index.html`（純前端靜態展示站，GitHub Pages 發布）
2. `warroom-data-api-prototype` 的 `dashboard#index`（Ruby on Rails，真實 Google Sheets 資料）

兩者目前都是寫死的深色配色（背景 `#0f1117`、卡片 `#1a202c` 等），無法切換樣式。本 spec
為這兩個頁面新增「深色／淺色主題切換」功能：提供一顆切換鈕，讓使用者可在深色（維持現況）與
新增的淺色主題之間切換，並記住選擇。

**不納入範圍**：新增「跟隨系統設定」自動偵測（本 spec 固定預設深色，見需求 3）、新增其他配色
主題（僅深色／淺色兩者）、離線頁面（`pwa/manifest.json.erb` 等 PWA 相關資源）的主題色調整、
不改動任務篩選／摘要等既有互動邏輯與功能。

**技術棧說明**：
- `docs/index.html` 對應的變更須遵守 `.kiro/steering/project-standards.md`：純 HTML／CSS／JS、
  不使用建置工具、不呼叫外部 API。
- `warroom-data-api-prototype` 對應的變更沿用該 spec 既有技術棧（Rails view + Sprockets
  `application.css`），不引入前端框架或建置工具，且不得變動任務資料存取邏輯。
- 兩處實作各自獨立（不共用程式碼、不共用 `localStorage` key），但視覺規格（配色、切換行為）
  須一致，以維持品牌一致性。

---

## 詞彙表

- **Dashboard_Static**：`docs/index.html`，純前端靜態展示頁。
- **Dashboard_Rails**：`warroom-data-api-prototype` 的 `app/views/dashboard/index.html.erb`。
- **Theme_Toggle**：新增的深色／淺色切換按鈕控制項。
- **Theme_Preference**：使用者切換後、以瀏覽器 `localStorage` 儲存的主題選擇值（`"dark"` 或
  `"light"`）。
- **主題屬性**：套用於根元素（`<html>` 或 `<body>`）的屬性（例如 `data-theme="light"`），CSS
  依此屬性切換對應的 CSS 變數值。

---

## 需求

### 需求 1：主題切換控制項

**使用者故事：** 身為戰情室使用者，我希望畫面上有明顯的切換鈕可以在深色與淺色樣式間切換，以便依環境或個人偏好調整畫面。

#### 驗收標準

1. THE **Dashboard_Static** 與 **Dashboard_Rails** SHALL 在頁首（header）區域提供一個 **Theme_Toggle** 按鈕。
2. THE **Theme_Toggle** SHALL 同時以圖示與文字（或 `aria-label`）標示目前可切換的目標主題（例如顯示「切換至淺色模式」），不得僅以顏色或純圖示表達。
3. WHEN 使用者點擊 **Theme_Toggle**，THE 對應頁面 SHALL 立即（不重新整理頁面）切換主題屬性並套用新配色，且已渲染的任務列表、摘要列、篩選控制項、狀態 badge 等既有元件的內容與互動狀態維持不變。
4. THE **Theme_Toggle** SHALL 可透過鍵盤操作（Tab 聚焦、Enter／Space 觸發），符合基本無障礙可操作性。

---

### 需求 2：淺色主題配色

**使用者故事：** 身為戰情室使用者，我希望切換到淺色主題後，畫面上所有既有元件（狀態 badge、逾期標示、摘要列、表格、篩選控制項）都清楚可讀，而不是只有背景變白、文字仍是淺色看不清楚。

#### 驗收標準

1. THE 淺色主題 SHALL 為以下既有視覺元件定義對應的淺色配色：頁面背景、卡片背景（`.stat-item`、`table.project-tasks`）、邊框（`#2d3748` 等）、主要文字、次要文字（`.subtitle`、`.stat-label`）、狀態 badge（completed／in_progress／pending 三種）、逾期標示（`.overdue-tag`）、delay 正負色（`.delay-positive`／`.delay-negative`）。
2. THE 淺色主題 SHALL 確保前景文字與背景色的對比度達到可正常閱讀的程度（一般文字與背景對比度不低於 WCAG AA 標準 4.5:1，可用瀏覽器內建無障礙檢查工具或線上對比度計算工具驗證）。
3. THE 淺色主題 SHALL 保留狀態 badge 現有的「顏色＋文字」雙重辨識方式（不因換色而移除文字內容）。
4. WHEN 使用者切換至淺色主題並縮小視窗至手機寬度，THE 對應頁面 SHALL 維持既有響應式版型（卡片化表格、篩選控制項換行）正常顯示，不因配色調整而破版。

---

### 需求 3：預設主題

**使用者故事：** 身為戰情室使用者，我希望頁面第一次載入時維持目前熟悉的深色畫面，不因瀏覽器或作業系統設定而預設跳成淺色。

#### 驗收標準

1. WHEN 使用者第一次造訪頁面且尚無任何已儲存的 **Theme_Preference**，THE 對應頁面 SHALL 預設套用深色主題，不依據瀏覽器 `prefers-color-scheme` 系統設定自動判斷。
2. THE 深色主題的視覺呈現 SHALL 與目前既有畫面（重構前）保持一致，不因本次 CSS 變數化重構而產生視覺差異。

---

### 需求 4：記住使用者選擇

**使用者故事：** 身為戰情室使用者，我希望切換主題後，之後重新整理或重新造訪同一個頁面時，能維持我上次選擇的主題，不必每次都重新切換。

#### 驗收標準

1. WHEN 使用者點擊 **Theme_Toggle** 完成切換，THE 對應頁面 SHALL 將選擇的主題值寫入該頁面所屬網域的 `localStorage`。
2. WHEN 使用者重新整理頁面或重新造訪，且該網域的 `localStorage` 已有 **Theme_Preference**，THE 對應頁面 SHALL 在頁面渲染時套用已儲存的主題，不先短暫顯示預設深色主題再切換（避免畫面閃爍，即 FOUC）。
3. IF `localStorage` 無法存取（例如使用者關閉相關瀏覽器權限）導致讀寫拋出例外，THEN THE 對應頁面 SHALL 攔截例外並回退為需求 3 的預設深色主題，不得造成頁面渲染中斷或 JavaScript 錯誤阻擋其他功能。
4. THE **Dashboard_Static** 與 **Dashboard_Rails** 的 **Theme_Preference** SHALL 各自獨立儲存與套用（不同網域，`localStorage` 天然隔離），使用者在一處的選擇不需同步至另一處。

---

### 需求 5：兩站視覺一致性

**使用者故事：** 身為戰情室使用者，不論我看的是靜態展示站還是接真實資料的 Rails 版本，我希望深色／淺色主題的配色與切換方式看起來是同一套設計。

#### 驗收標準

1. THE **Dashboard_Static** 與 **Dashboard_Rails** SHALL 使用相同的深色／淺色配色數值（色碼一致）。
2. THE **Dashboard_Static** 與 **Dashboard_Rails** 的 **Theme_Toggle** SHALL 放置於頁首相同的相對位置（標題列右側），外觀與互動行為一致。
3. THE 兩處實作 SHALL 各自以該技術棧慣用的方式實作相同效果（`docs/` 使用純 JS 操作 `localStorage` 與 DOM 屬性；Rails 版本使用等效的原生 JS，不引入前端框架），不要求共用程式碼檔案。
