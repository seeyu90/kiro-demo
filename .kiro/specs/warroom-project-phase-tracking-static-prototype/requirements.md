# 需求文件

## 簡介

既有「專案歷程」（`warroom-project-history-static-prototype` / `warroom-project-history-real-source`）
以 305/306/307 三份 Google Sheets 為資料來源，用「自由文字狀態」＋307 燃盡議題（人時）呈現專案進度，
沒有固定的階段（stage）欄位。

本 spec 新增一個**完全獨立**的新功能「專案階段追蹤」：以固定的 5 個交付階段（需求確認／開案／開發／
測試／發布）呈現每個專案在時間軸上的預計 vs 實際完成日期，資料來源改為 **Notion 資料庫**（而非
Google Sheets）。

真實 Notion 資料庫欄位結構（使用者提供截圖，範例專案「內控調整2510」）：
`日期（目標/預計日期）, 實際完成, 專案（relation）, 議題, 類型（對應「階段」：觀察到 開案／開發／
測試／發布 四種值）, 狀態（觀察到「完成」）, 原因（選填備註，例如「與內控調整2511一起發布」）`。

本階段是**靜態 prototype 階段**：在 `docs/` 新增純前端頁面，使用依上述真實 Notion 欄位結構仿造的
模擬資料，不呼叫任何 API，之後才另立 spec 規劃真實 Notion API 串接（比照
`warroom-issue-dashboard-static-prototype` → `warroom-issue-dashboard-real-source` 的既有兩階段模式）。

本文件下方需求已針對容易被實作者（人類或 AI coding agent）自行腦補的細節（5 階段補齊規則、
`null`／空字串慣例、日期差異計算方式、甘特圖方向與樣式、「今日」定義、排序規則、空值容錯）逐一訂出
明確規則；資料形狀的完整字面範例（Prototype Data Contract）見 `design.md`「元件與介面 → Prototype
Data Contract」章節，實作時 SHALL 直接依該範例的欄位與型別撰寫模擬資料，不另行設計。

**與使用者已確認的範圍決策**：
1. 本功能為**獨立新頁面／新 spec**，不修改既有「專案歷程」總覽頁或其 Rails 後端。
2. 畫面設計稿中的「預估工時」「實際工時」欄位與長條圖，因目前提供的 Notion 截圖無對應欄位，**本階段
   拿掉**，只做日期追蹤（預計完成日期／實際完成日期／差異天數）。

### 待確認事項

以下項目目前無法從使用者提供的單一 Notion 截圖確認。**為避免實作時自行腦補，prototype 階段已針對
每一項訂出明確、可直接執行的規則**（見對應需求編號），僅「真實資料的實際來源」留待後續 real-source
spec 確認；prototype 本身的行為不受未確認狀態影響：

1. **五個固定階段的「預計完成日期」來源**：截圖範例「內控調整2510」僅有開案／開發／測試／發布
   四筆已建立的階段紀錄（無需求確認），且每筆建立時「日期」與「實際完成」已同時存在，較像是「階段
   完成後才登錄」的紀錄，而非「專案一開始就排定五階段預計日期」。**Prototype 明確規則**（見需求
   4.3）：模擬資料中每個專案一律建立完整 5 筆 `STAGE_ORDER` 階段紀錄，尚未發生的階段也要建立紀錄，
   僅 `actual_date` 為 `null`。真實 Notion 是否真的一開始就有 5 階段排程、或需要另一份排程資料 join
   出來，留待 real-source spec 確認；不影響 prototype 實作。
2. **專案卡片標頭欄位（客戶／PM／專案狀態／專案層級預計完成日期）的真實來源**：截圖中的階段紀錄
   database 未包含這些欄位。本 prototype **假設**另有一個「專案」Notion database（性質類似既有
   `300_員工專案` 試算表），以「專案」relation 對應提供這些欄位，prototype 以獨立的
   `PROJECT_PROFILES` 模擬資料表示（見資料模型）。真實對應方式留待 real-source spec 確認。
3. **「類型」欄位的完整合法值**：目前僅觀察到 開案／開發／測試／發布 四種；「需求確認」是否為真實
   合法值，屬於**尚未驗證的 prototype 展示假設**。**Prototype 明確規則**：固定使用 `STAGE_ORDER =
   ["需求確認","開案","開發","測試","發布"]` 五階段，不因真實資料只有四種類型而動態增減。real-source
   spec 需再次確認 Notion 是否真的有「需求確認」這個類型值，或改用其他方式標示。
4. 工時（預估／實際）資料來源尚未確認是否存在於其他 Notion database 或其他系統（如 Redmine）；本階段
   不處理，待確認後可另立需求納入。

### 不納入範圍

- 修改既有 `docs/project-history-overview.html` 及其對應 JS，或既有 Rails
  `warroom-data-api-prototype/app/controllers/project_history_controller.rb` 等專案歷程功能
  （本 spec 只新增獨立頁面，不動既有程式碼）
- 真實 Notion API 串接、Notion Token／資料庫 ID 等設定與後端（留待後續 real-source spec）
- 工時（預估／實際）呈現與比較圖表（使用者已確認本階段拿掉，見簡介）
- 資料寫回 Notion：畫面上「實際完成日期」欄位即使可互動編輯，本階段僅影響前端當下畫面狀態，不
  持久化、不寫回任何後端
- 權限管理、多語系
- 任何跨頁面／跨次載入的持久化（篩選、排序、展開狀態等重新整理後不需保留）

**技術棧說明**：本 spec 隸屬 `docs/` 靜態站主體，須遵守 `.kiro/steering/project-standards.md` 的技術
限制（純 HTML/CSS/JS、無框架、無建置工具、模擬資料、繁體中文、響應式設計），無例外。

---

## 詞彙表

- **Phase_Tracking_Page**：`docs/project-phase-tracking.html`，本 spec 新增的獨立頁面（總覽篩選／排序
  ＋專案卡片，展開後顯示階段追蹤表與甘特圖切換）。
- **Entry_Page**：`docs/index.html`，既有入口頁，本 spec 新增一張卡片連結到 **Phase_Tracking_Page**，
  不變更既有卡片。
- **STAGE_ORDER**：固定順序的 5 個專案交付階段常數：`需求確認, 開案, 開發, 測試, 發布`（見待確認
  事項 3）。
- **階段紀錄（Phase_Record）**：對應未來 Notion 階段紀錄 database 的一列，模擬資料欄位為
  `project`（專案，**純字串**，值等於對應 Project_Profile 的 `project_name`，用來模擬 Notion
  relation；prototype 階段不建立 Notion page ID 或物件結構）、`stage`（對應 Notion「類型」，值必為
  `STAGE_ORDER` 之一）、`planned_date`（對應 Notion「日期」，`"YYYY-MM-DD"` 字串）、`actual_date`
  （對應 Notion「實際完成」，**尚未完成時一律為 `null`，禁止使用空字串 `""`**）、`status`（對應
  Notion「狀態」原始文字）、`reason`（對應 Notion「原因」，無備註時為空字串 `""`）。每個專案固定有
  **STAGE_ORDER** 5 筆階段紀錄，包含尚未發生的階段（見待確認事項 1、需求 4.3）。
  > **`status` 欄位的 prototype-only 慣例**：本 prototype 模擬資料遵循「`actual_date === null` 時
  > `status` 也一律為 `null`，不得自行發明『進行中』等真實資料未觀察到的狀態值」這條規則，**僅適用
  > 於本 prototype 的模擬資料撰寫**，不代表未來真實 Notion 資料一定滿足此約束（真實資料可能出現
  > `status` 有值但 `actual_date` 為空、或反之的情況）。畫面上「已完成／未完成／—」的顯示邏輯一律
  > 由 `planned_date`／`actual_date` 是否存在衍生（見需求 4.5 對照表），**不讀取 `status` 欄位**，
  > 因此不受此慣例是否成立影響。real-source spec 串接真實 Notion 資料時，應以真實 database schema
  > 與資料一致性為準，不受本條 prototype 假設約束。
- **專案基本資料（Project_Profile）**：模擬資料欄位為 `project_name, customer（客戶）, pm（PM）,
  status（專案狀態）, planned_completion_date（專案層級預計完成日期，見待確認事項 2）`。**注意**：
  `planned_completion_date`（專案層級）與 `PHASE_RECORDS[].planned_date`（階段層級）是兩個不同欄位，
  不得混用（見需求 2.3 排序規則）。
- **完成狀態（衍生值，非資料欄位）**：畫面上每一階段列的「已完成／未完成／—」標示與「差異」，一律
  依需求 4.5 的 `planned_date`／`actual_date` 對照表衍生，不得讀取 `status` 欄位文字做為判斷依據。

---

## 需求

### 需求 1：入口頁新增連結

**使用者故事：** 身為戰情室使用者，我希望能從入口頁找到「專案階段追蹤」功能。

#### 驗收標準

1. THE **Entry_Page** SHALL 新增至少一張卡片／連結，導向 **Phase_Tracking_Page**。
2. THE **Entry_Page** SHALL 保留既有卡片，內容與行為不變。
3. THE **Phase_Tracking_Page** SHALL 提供返回 **Entry_Page** 的連結。

---

### 需求 2：總覽 — 篩選與排序

**使用者故事：** 身為戰情室使用者，我希望能依客戶、狀態、PM 篩選並排序專案清單，以便快速找到特定
專案。

#### 驗收標準

1. THE **Phase_Tracking_Page** SHALL 提供依「客戶」「狀態」「PM」篩選的下拉選單，各自預設「全部」，
   選項取自模擬資料中 **Project_Profile** 的唯一值。
2. WHEN 使用者變更狀態、客戶或 PM 任一篩選，THE **Phase_Tracking_Page** SHALL 只顯示同時符合已選
   條件（交集）的專案。
3. THE **Phase_Tracking_Page** SHALL 提供「排序」下拉選單，選項與規則如下，預設「不排序」：

   | 排序選項 | 規則 |
   |---|---|
   | 不排序（預設） | 維持模擬資料 `PROJECT_PROFILES` 原始順序 |
   | 依預計完成日期 | 依 `PROJECT_PROFILES.planned_completion_date`（**專案層級**，非任一階段的 `PHASE_RECORDS[].planned_date`）由早到晚（升冪） |
   | 依狀態 | 依 `PROJECT_PROFILES.status` 文字升冪（字典序） |
   | 依客戶 | 依 `PROJECT_PROFILES.customer` 文字升冪（字典序） |

   此排序僅作用於總覽的「專案清單／專案卡片順序」，不影響單一專案展開後階段追蹤表內的 **STAGE_ORDER**
   固定順序。

4. WHEN 排序鍵值相同（例如兩個專案 `customer` 相同），THE **Phase_Tracking_Page** SHALL 維持該兩者
   在模擬資料中的原始相對順序（穩定排序），不得因重新排序而使鍵值相同的專案彼此跳動。
5. WHEN 篩選後無符合條件的專案，THE **Phase_Tracking_Page** SHALL 顯示「目前無符合條件的專案」，
   不留白。

---

### 需求 3：總覽 — 清單／甘特圖切換

**使用者故事：** 身為戰情室使用者，我希望能在清單與甘特圖兩種檢視間切換，以便用適合的方式比較各
專案的階段進度。

> **命名澄清**：本頁「甘特圖」檢視本質是**「階段進度差異圖」**，並非傳統依任務起訖日排列的甘特圖
> （固定 5 階段、以「預計完成日期」為基準點，呈現的是「準時／延遲／提前」關係，而非任務排程）。以下
> 驗收標準已明確定義方向與樣式規則，實作時不得自行套用傳統甘特圖（以起始日為左端點）的理解方式。

#### 驗收標準

1. THE **Phase_Tracking_Page** SHALL 提供「清單」與「甘特圖」兩種檢視模式的切換控制項，頁面載入時
   預設顯示「清單」檢視。
2. WHEN 使用者切換檢視模式，THE **Phase_Tracking_Page** SHALL 不重新載入頁面（純前端切換）。
3. THE **Phase_Tracking_Page** SHALL 於甘特圖檢視以簡易 SVG 呈現每個專案 **STAGE_ORDER** 5 個固定
   階段，每個階段色塊一律以「預計完成日期」為時間軸基準點（左端點固定），依下列規則向右延伸：
   - IF 該階段 `actual_date !== null`（已完成）AND 實際完成日期**晚於或等於**預計完成日期，THEN
     色塊由「預計完成日期」延伸至「實際完成日期」，以代表「延遲」的樣式呈現（比照既有
     `.gantt-task-actual-delayed` 色系；差異為 0 時樣式比照準時，見下一條）。
   - IF 該階段 `actual_date !== null` AND 實際完成日期**早於**預計完成日期（提前完成），THEN 色塊
     **不得以「預計完成日期→實際完成日期」的真實時間區間繪製**（那會畫出右端點小於左端點的反向／
     負寬度圖形）。SHALL 改以「預計完成日期」為左端點，往右繪製一段與提前天數（`|diffDays|`）等比例
     的色塊，套用與「延遲」明顯不同的視覺樣式（例如不同顏色，比照既有 `.gantt-task-actual-ontime`
     色系新增專屬 class）；此色塊**代表「提前幅度」的視覺標記，並非該階段的實際完成日期區間**，
     實作與程式碼註解應明確標示此點，避免被誤認為繪圖錯誤。
   - IF 該階段 `actual_date === null`（未完成），THEN 色塊由「預計完成日期」延伸至「今日」（見
     需求 3.4），以代表「進行中／未完成」的樣式呈現（比照既有 `.gantt-task-planned` 或
     `.gantt-task-actual-track` 色系）。
4. THE 「今日」定義 SHALL 一律使用頁面執行當下瀏覽器的當地日期（`new Date()`），不得於程式碼中寫死
   固定日期字串（例如 `"2026-08-19"`），以免頁面日後顯示過期的「今日」標記。
5. THE 甘特圖檢視 SHALL 允許水平捲動（比照既有 `.gantt-scroll` 慣例）；SVG 實際寬度不得低於
   `900px`，時間範圍較短（例如全部階段集中在 10 天內）時，仍 SHALL 維持至少 `900px` 寬度並讓比例
   自然拉開，不得將 SVG 寬度壓縮為容器寬度以致色塊過度擁擠；於手機等窄螢幕，SHALL 透過
   `.gantt-scroll` 讓使用者橫向捲動查看，不得造成頁面整體（`body`）出現水平捲動軸。

---

### 需求 4：專案卡片 — 展開顯示階段追蹤表

**使用者故事：** 身為戰情室使用者，我希望展開一個專案卡片後，能看到它 5 個階段的預計與實際完成
日期，以便掌握進度是否落後。

#### 驗收標準

1. THE **Phase_Tracking_Page** SHALL 於清單檢視以卡片呈現每個專案（比照既有專案歷程總覽的卡片式
   呈現慣例），卡片標頭顯示：專案名稱、客戶、PM、狀態、專案層級預計完成日期。
2. WHEN 使用者展開專案卡片，THE **Phase_Tracking_Page** SHALL 顯示固定 5 列的階段追蹤表（依
   **STAGE_ORDER** 順序：需求確認／開案／開發／測試／發布），每列顯示：階段名稱、預計完成日期、
   實際完成日期、差異、完成狀態標示；完成狀態標示與差異的判斷規則見需求 4.5。
3. THE 模擬資料 `PHASE_RECORDS` SHALL 為每個專案建立完整 5 筆 **STAGE_ORDER** 階段紀錄；尚未發生的
   階段仍需建立該筆紀錄（`stage` 正確對應、`planned_date` 有值），僅 `actual_date`／`status` 為
   `null`（不得省略該階段的紀錄、不得只建立已發生的階段）。模擬資料中 `actual_date` 表示「尚未
   完成」時 SHALL 一律使用 `null`，禁止使用空字串 `""`（兩者不得混用）；UI 對應顯示空白
   `<input type="date">`。
4. 「差異」天數 SHALL 以「實際完成日期－預計完成日期」的**日曆天數**整數計算（可為負值，代表提前
   完成），計算 SHALL 僅以 `"YYYY-MM-DD"` 字串的年/月/日部分進行，不得受瀏覽器所在時區的 UTC 偏移
   影響（例如不得直接以 `new Date("2026-08-10")` 建構後相減，需改以拆解年月日再用 `Date.UTC(...)`
   等方式計算，避免時區造成的日期偏移誤差）。範例：預計 `2026-08-10`、實際 `2026-08-12` → `+2`；
   預計 `2026-08-10`、實際 `2026-08-08` → `-2`。
5. THE 每一階段列的「完成狀態標示」與「差異」欄位 SHALL 僅依該列 `planned_date`／`actual_date` 是否
   存在（含缺失或格式不合法，視同不存在）判斷，依下表呈現，不得讀取 `status` 欄位文字判斷、不得
   自行發明「進行中」等真實 Notion 資料未觀察到的狀態值：

   | `planned_date` | `actual_date` | 完成狀態標示 | 差異 |
   |---|---|---|---|
   | 存在 | 存在 | 已完成 | 依需求 4.4 計算天數 |
   | 存在 | `null` | 未完成 | — |
   | 缺失／格式不合法 | 存在 | 已完成 | — |
   | 缺失／格式不合法 | `null` | — | — |

   即：完全無法判斷排程與完成與否時（`planned_date`、`actual_date` 皆缺失），完成狀態標示 SHALL 顯示
   「—」，不得顯示「未完成」（因為根本不知道該階段是否已被排程，「未完成」語意不正確）。
6. IF 某專案在模擬資料中找不到任何對應的 `PHASE_RECORDS`（例如新專案尚未建立任何階段紀錄），THEN
   THE **Phase_Tracking_Page** SHALL 仍顯示固定 5 列階段表，每列視為 `planned_date`／`actual_date`
   皆缺失，依需求 4.5 對照表顯示「—」，不得讓卡片渲染失敗或省略階段列。
7. IF 單一階段紀錄的 `planned_date` 缺失或格式不合法（但 `actual_date` 存在），THEN THE
   **Phase_Tracking_Page** SHALL 依需求 4.5 對照表處理該列（完成狀態標示「已完成」、差異「—」），
   不拋出例外、不影響同一專案其他階段列或其他專案卡片的渲染。
8. IF 差異天數為正（實際晚於預計），THEN THE **Phase_Tracking_Page** SHALL 以醒目樣式（例如紅色文字）
   顯示該差異值；差異為負（提前完成），THEN SHALL 以另一種可辨識的樣式呈現（例如綠色文字，與需求
   3.3 甘特圖的提前完成樣式呼應）；差異為 0（準時）或「—」，THEN 以一般樣式顯示。
9. THE **Phase_Tracking_Page** SHALL 讓「實際完成日期」欄位以 `<input type="date">` 呈現，可互動編輯；
   WHEN 使用者變更該欄位，THE **Phase_Tracking_Page** SHALL 即時重新計算並顯示該列「差異」與完成
   狀態標示。編輯後的值 SHALL 儲存於**獨立的 UI state**（不得直接修改 `PHASE_RECORDS` 陣列中的
   物件或其欄位），不持久化、不寫回任何後端；WHEN 使用者重新整理頁面，THE 所有編輯值 SHALL 恢復為
   模擬資料原始值（見「不納入範圍」）。

---

### 需求 5：模擬資料、語言與響應式設計

**使用者故事：** 身為使用者，我希望頁面在各種裝置上都能正常顯示，且介面語言一致。

#### 驗收標準

1. THE **Phase_Tracking_Page** SHALL 使用純前端模擬資料（hardcoded JavaScript 物件），欄位結構對齊
   簡介所述真實 Notion 欄位結構與待確認事項中的假設，不呼叫任何外部 API。
2. THE **Phase_Tracking_Page** SHALL 使用繁體中文介面。
3. THE **Phase_Tracking_Page** SHALL 支援桌機、平板、手機版面，使用 CSS media query 實作，沿用
   `docs/css/style.css` 既有斷點慣例（768px／560px）。
4. THE **Phase_Tracking_Page** SHALL 沿用既有 `warroom-theme` 深色/淺色主題切換機制，不另建獨立
   主題邏輯。
