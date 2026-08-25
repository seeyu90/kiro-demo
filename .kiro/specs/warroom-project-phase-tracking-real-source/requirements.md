# 需求文件

## 簡介

`warroom-project-phase-tracking-static-prototype` 已在 `docs/` 完成「專案階段追蹤」的靜態原型
（`docs/project-phase-tracking.html`），使用依單一 Notion 截圖仿造的模擬資料。本 spec 是該原型的
後續迭代：在既有 `warroom-data-api-prototype` Rails 專案中，比照 305/306/307／
`warroom-project-history-real-source` 既有資料流的模式，新增一組獨立的「專案階段追蹤」資料流與頁面
（`/project_phase_tracking`），改讀真實資料，取代靜態原型的模擬資料。

**架構決策（2026-08-20，取代原規劃）**：真實資料源頭是 Notion（截圖所見的「階段紀錄」資料庫），但
Rails 端**不直接呼叫 Notion API**。改由既有 n8n workflow（已確認對該 Notion workspace 有存取權）
定期將 Notion 資料同步進一組新的 Google Sheet，Rails 端比照 305/306/307 既有模式讀取該 Sheet。
原規劃（Rails 直接接 Notion API，見 git 歷史）已放棄，原因：

1. 本專案已有三個 spec（305/306/307）建立起「`GoogleSheetsCredentials` ＋ Sheets Client ＋
   `Sheets::` 命名空間 Actor」這一套成熟慣例，走 Sheets 路線可完全沿用，不需要在 Rails 端新增一整套
   Notion 專屬的憑證管理、HTTP client、分頁游標處理、429 重試、錯誤碼對應。
2. 原規劃卡住的前置條件（本 Rails 專案需要向 Notion 資料庫擁有者索取 Internal Integration token）
   實際上不管哪種架構都要有人向該 workspace 要到存取權——差別只在「誰去呼叫 Notion API」。既然 n8n
   端已經有現成存取權，讓 n8n 去呼叫可以直接跳過「幫 Rails 專案另外申請一組 Notion Integration」這
   一步。
3. 本頁是戰情室內部追蹤工具，非即時儀表板，n8n 排程同步造成的資料延遲（分鐘等級）可接受。

**技術棧說明**：延續 `warroom-data-api-prototype` 既有例外（Ruby on Rails 獨立伺服器），不受
`project-standards.md`「技術限制」「響應式設計」段落約束；遵守 `rails-standards.md` 分層慣例
（Controller → Actor → Client → Blueprint → View）與統一錯誤格式；憑證存放**直接沿用既有
`GoogleSheetsCredentials`**，不需另立新規則。

---

## 前置條件（階段 0／1 已確認，2026-08-25）

n8n workflow **已建立並實際同步中**（使用者已確認），目標 Google Sheet 已直接讀取確認：

- **spreadsheet ID**：`1YQp4f-5v985W4EV59jhSAdhTKMn2Mc-0PW-qYc6vKpU`（標題「專案進度」，擁有者
  `rita.chou@amastek.com.tw`，即已在使用者自己帳號下，不需額外處理跨帳號分享問題，但仍須確認已
  分享給既有 Google Service Account，見需求 1.2）。
- **欄位配置已確認，2026-08-25 使用者再次調整過一次**：`project, issue_id, issue_name, stage,
  planned_date, actual_date, status, reason, unique_key, sheet_year`（英文欄名，非 Notion 原始
  中文欄名，n8n 同步時已轉換）。原本是單一 `issue` 欄（有時是描述性名稱如「202412 優化」，有時是
  純 Redmine ID 如「4515」），使用者拆成兩欄：`issue_id`（沿用原 `issue` 欄的語意與 `unique_key`
  組成規則，仍是卡片分組鍵）、`issue_name`（新欄，議題的人類可讀名稱，**目前只在 `issue_id` 是
  純 Redmine ID 時才會填**，`issue_id` 本身已是描述性名稱的列則留空，View 顯示規則：有
  `issue_name` 時兩者並列「名稱（ID）」，否則只顯示 `issue_id`，見 `phase_tracking_issue_label`）。
  `unique_key`（`project|issue_id|stage` 組成的字串，⚠️ **非唯一**，見下方「已知資料特性」）。
- **資料依年度分區塊，屬於同一份資料（已與使用者確認，2026-08-25）**：Sheet 內容依 `sheet_year`
  （2024／2025／2026）分成三個各自帶表頭列的區塊，使用者確認「是同一份資料依照時間區分年度」——
  即 `PhaseRecordsSheetsClient` SHALL 讀出全部三個區塊、合併為單一 `PHASE_RECORDS` 陣列，不視為
  三種不同資料來源。同時使用者要求**加上年度篩選**功能（見需求 4.6，比照既有
  `warroom-project-history-*` 頁面已有的年度篩選慣例）。
  **已確認（2026-08-25，實作時用真實 Service Account 憑證直接查詢）**：三個年度區塊是三個獨立
  分頁，分頁名稱就是年度字串本身（`"2024"`／`"2025"`／`"2026"`），非同分頁內的三個表格。

### ⚠️ 已知資料特性（非單純資料品質問題——2026-08-25 使用者釐清語意）

1. **`unique_key` 撞號代表「重新排程」，不是資料錯誤**：例如 2026 年區塊 `HRM|4656|開案` 出現兩筆
   內容不同的記錄。**使用者已澄清語意**：這代表原本排定的時間點沒能如期完成，於是為同一
   `(project, issue_id, stage)` **重新建了一筆新資料**（而非直接覆蓋舊資料），舊的一筆等於「這次重排
   前失敗的嘗試」歷史紀錄。2025 年區塊 `PrjHJ|v1 開發|開案` 同樣是這個模式。
   - **決策（已與使用者確認）**：Rails 端 SHALL NOT 以 `unique_key`（或其組成的
     `project|issue|stage`）作為 hash／索引鍵去重——這麼做會讓「重排前」那筆歷史記錄被靜默覆蓋
     遺失。`PhaseRecordsSheetsClient` 的呼叫端 SHALL 將每一列都視為獨立記錄保留（陣列）。
   - **呈現規則（已與使用者確認，2026-08-25）**：同一 `(project, issue_id, stage)` 的多筆記錄
     **全部都是有效資料，都要呈現在專案進度上**——不得因為找到了「較新」的一筆就把較舊的記錄從
     UI 隱藏，因為每一筆延誤未完成的舊記錄本身就代表「應完成但未完成」的事實，是專案進度追蹤的
     重點之一，不是雜訊。具體呈現方式：
     - 該 stage 的**主要呈現**（清單卡片摘要、甘特圖色塊）使用**該 stage 多筆記錄中最新的一筆**
       （⚠️ 「最新」的判定規則預設採用 Sheet 中列出順序較後者 = 較新——因為 n8n 同步／PM 手動
       重排的操作方式應是「附加新列」而非「插入舊列之前」；此判定規則為合理預設，非使用者逐字
       確認，若日後發現 Sheet 實際排序方式不同須修正）。
     - 展開卡片後，該 stage 底下其餘（較舊、已被取代）的記錄 SHALL 以**次要樣式**顯示（例如較淡
       的顏色／較小字體，標示為「曾經延誤的舊排程」），不得完全省略不顯示。
2. **部分列 `sheet_year` 為空字串**：尤其 2025 年區塊後半段（約 5 月之前的資料）許多列
   `sheet_year` 是空的，即使 `planned_date`／`actual_date` 明顯落在 2025 年。Actor 層 SHALL NOT
   仰賴 `sheet_year` 做為年度篩選的唯一依據（若未來需要年度篩選功能，須改以 `planned_date` 年份
   為準，或先請 n8n 端修正）。
3. **`stage` 欄位實際只觀察到 4 種值**：`開案`／`開發`／`測試`／`發布`，掃過全部三個年度區塊都沒有
   `需求確認`。**決策（已與使用者確認）**：`STAGE_ORDER` 仍保留原本 5 個值（`需求確認`／`開案`／
   `開發`／`測試`／`發布`）不變——目前資料剛好沒有 `需求確認` 的紀錄，不代表這個階段不會發生，
   Actor／View 邏輯 SHALL 繼續容許「某階段完全沒有記錄」這個既有情境（沿用既有 5 色塊「至多」呈現
   的規則），不得因為目前抽樣沒看到就把 `需求確認` 從 `STAGE_ORDER` 移除。

### 卡片分組單位：`(project, issue_id)`，不是 `project`（已與使用者確認，2026-08-25）

static prototype 的 `PROJECT_PROFILES`／卡片設計原本假設**每個專案一張卡片、一組完整的 5 階段
生命週期**（見 static prototype design.md）。但真實 Sheet 顯示：`project`（例如 `HRM`、`JZNPMS`）
底下反覆出現大量**不同的 `issue`**（例如 HRM 底下有「202412 優化」「202411優化」「v2.0 調整」…
數十筆各自獨立的階段生命週期）。**決策：卡片分組單位改為 `(project, issue_id)`，每一組獨立的
`(project, issue_id)` 一張卡片**，不是每個 `project` 一張。這是與 static prototype 的根本差異，
本 spec 需求 3／4 的驗收標準與詞彙表 SHALL 一律以 `(project, issue_id)` 為卡片單位改寫，不得沿用
static prototype「一專案一卡片」的分組方式。

**跟著改變的細節（推論自此決策，非逐字向使用者確認，實作時如與此假設衝突須另外確認）**：
- 卡片標題／識別字串建議為 `"#{project} - #{issue_id}"`（`issue_name` 有值時改為
  `"#{project} - #{issue_name}（#{issue_id}）"`，見 `phase_tracking_issue_label`），避免不同
  `issue_id` 但同 `project` 的卡片在畫面上無法分辨。
- 需求 3 的「專案」層級資料（客戶／PM）**推定仍以 `project` 為鍵**（同一 `project` 底下所有
  `issue_id` 卡片共用同一組客戶／PM），而非 `(project, issue_id)` 各自一份——因為客戶／PM 通常是
  專案代碼層級的屬性，不隨每個 issue 變動。若日後發現同一 `project` 底下不同 `issue_id` 需要不同
  客戶／PM，須另外確認並修正此假設。
- **「狀態」不是專案層級的維運狀態（修正，2026-08-25 使用者澄清）**：一開始實作時誤把
  `ProjectProfilesSheetsClient`「專案」分頁的「狀態」欄（值如「維護」，專案層級的維運狀態，
  來自客戶／PM 那張表）當成卡片的「狀態」欄位使用；使用者指正「狀態應該指的是議題狀態不是
  專案狀態」。**正確定義：「狀態」= 議題目前所在階段的完成狀態**，取
  `STAGE_ORDER`（需求確認／開案／開發／測試／發布）由後往前第一個有記錄的階段之 `status` 欄位
  （值如「完成」／「延誤已完成」／「延誤未完成」／「暫緩」／「未完成」，來自階段紀錄 Sheet 本身，
  不是 Roster）；完全沒有任何階段記錄時為 `nil`。篩選下拉選單（依客戶／狀態／PM）與排序（依狀態）
  邏輯不變，只是「狀態」欄位資料來源與定義換了。ProjectProfilesSheetsClient 仍讀「專案」分頁的
  客戶／PM 兩欄，但不再讀「狀態」欄。
- **新增：議題名稱／ID 搜尋（2026-08-25 使用者要求）**：真實資料的 `issue_id` 欄有時是描述性名稱
  （如「202412 優化」），有時是純 Redmine ID（如「4515」，這種情況 `issue_name` 會補上人類可讀
  名稱如「現場報工」），使用者要求能同時搜這兩種形式。新增一個自由文字搜尋欄位（`q`），對
  `issue_id`／`issue_name`／`project` 三欄做不分大小寫的子字串比對，符合其一即算命中；與客戶／
  狀態／PM 篩選是 AND 關係。（此需求早於 `issue_name` 欄新增，當時只有 `issue_id` 可搜，欄位
  拆分後自動涵蓋 `issue_name`。）

### 實作狀態（2026-08-25）

全部需求（1〜6）已實作完成：Rails 路由／Controller、`ProjectPhaseTrackingHelper` 純邏輯、
`PhaseRecordsSheetsClient`／`ProjectProfilesSheetsClient`、`Sheets::FetchPhaseTracking` Actor、
View（清單／甘特圖／篩選／年度篩選／搜尋）。RSpec（Client×2、Actor）與 rubocop 皆通過，並用真實
Service Account 憑證對真實 Sheet 跑過 smoke test（`RAILS_ENV=development`，見 design.md）。

---

## 詞彙表

（沿用 `warroom-project-phase-tracking-static-prototype` 的定義，欄位對應改為來自 n8n 同步的
Google Sheet，而非硬編碼模擬資料或直接的 Notion API）

- **PhaseTracking_Page**：`/project_phase_tracking`，本 spec 新增的 Rails 頁面。
- **PhaseRecordsSheetsClient**：封裝「階段紀錄」Sheet 讀取的 Client（比照 `ProjectRosterSheetsClient`
  等既有 Sheets Client 慣例；spreadsheet ID `1YQp4f-5v985W4EV59jhSAdhTKMn2Mc-0PW-qYc6vKpU`，讀取
  `2024`／`2025`／`2026` 三個分頁並合併，已實作）。
- **issue_id**：Sheet 欄位之一，議題名稱（例如「202412 優化」）或純 Redmine ID（例如「4515」），
  與 `project` 共同組成一個獨立的階段追蹤生命週期單位＝卡片分組單位，static prototype 沒有這個
  概念。原本是單一 `issue` 欄，2026-08-25 使用者拆分後改名為 `issue_id`（語意不變）。
- **issue_name**：Sheet 欄位之一，2026-08-25 新增，議題的人類可讀名稱，**只在 `issue_id` 是純
  Redmine ID 時才會填**（例如 `issue_id` 為「4548」時 `issue_name` 為「現場報工」），`issue_id`
  本身已是描述性名稱時留空。不是卡片分組鍵，只是顯示用。
- **unique_key**：Sheet 欄位之一，`project|issue_id|stage` 組成的字串，⚠️ **並非真的唯一**（代表
  同一 stage 的重新排程，見前置條件「已知資料特性」），不得用作 Rails 端的去重／索引鍵。
- **ProjectProfilesSheetsClient**：封裝「專案」層級資料（客戶／PM）讀取的 Client，讀
  `300_員工專案` 試算表（與既有 `ProjectRosterSheetsClient` 同一份，不同分頁）的「專案」分頁，
  已實作（見需求 3）。
- **Sheets::FetchPhaseTracking**：本 spec 的主要業務邏輯 Actor（放在既有 `app/actors/sheets/`
  命名空間，比照 `Sheets::FetchProjectRoster`／`Sheets::FetchProjectHistory` 慣例），呼叫上述
  Client，回傳彙總後的 `PROJECT_PROFILES`／`PHASE_RECORDS` 形狀（欄位定義見 static prototype
  design.md 的 Prototype Data Contract，本 spec 沿用相同欄位命名）。

---

## 需求

### 需求 1：Google Sheets 連線基礎設施（已可用，無需新建）

**使用者故事：** 身為後端開發者，我希望「專案階段追蹤」的資料讀取沿用既有 Google Sheets 連線方式，
不引入新的憑證管理機制。

#### 驗收標準

1. THE **PhaseRecordsSheetsClient**／**ProjectProfilesSheetsClient** SHALL `include
   GoogleSheetsCredentials`，比照既有 `ProjectRosterSheetsClient`／`BurndownSheetsClient` 等既有
   Client，不另建新的憑證 module。
2. THE 目標 Google Sheet SHALL 分享給既有 Service Account（`README.md` 記載的 `client_email`），
   spreadsheet ID／分頁名稱以環境變數設定（比照 `ProjectRosterSheetsClient::SHEET_NAME` 可用
   `ENV.fetch` 覆寫的慣例），避免日後分頁改名需要改程式碼。

---

### 需求 2：讀取「階段紀錄」Sheet（已實作，2026-08-25）

**使用者故事：** 身為後端開發者，我希望 Actor 能讀取 n8n 同步出的「階段紀錄」Sheet，取得每個
`(project, issue_id)` 各階段的預計／實際完成日期。

#### 驗收標準

1. WHEN **Sheets::FetchPhaseTracking** 被呼叫，THE **PhaseRecordsSheetsClient** SHALL 對
   spreadsheet ID `1YQp4f-5v985W4EV59jhSAdhTKMn2Mc-0PW-qYc6vKpU` 的 `2024`／`2025`／`2026` 三個
   分頁（已用真實 Service Account 憑證確認過分頁名稱就是年度字串本身）各自呼叫
   `get_spreadsheet_values` 取得全部列並合併，各分頁自己的表頭列不納入合併結果。
2. THE **PhaseRecordsSheetsClient** 的呼叫端（Actor）SHALL 將每一列解析為
   `{ project, issue_id, issue_name, stage, planned_date, actual_date, status, reason }`
   （欄名已確認與 Sheet 表頭一致：`project, issue_id, issue_name, stage, planned_date,
   actual_date, status, reason, unique_key, sheet_year`；`unique_key`／`sheet_year` 不納入解析
   後形狀，理由見詞彙表與前置條件）。
3. THE 回傳字串 SHALL 依 `rails-standards.md`「其他慣例」重新標記為 UTF-8（比照既有 Sheets
   Client），並對缺少必要欄位（如「專案」欄空白）的列予以跳過，不使整個 request 失敗。
4. THE 呼叫端 SHALL 將每一列都保留為獨立記錄（陣列，不以 `unique_key` 或
   `project|issue_id|stage` 去重／覆蓋），理由與同一 `(project, issue_id, stage)` 多筆記錄的
   呈現規則見前置條件「已知資料特性」
   第 1 點（**該呈現規則尚未定案，此驗收標準只規定 Actor 層不得丟資料，不規定 View 層如何顯示**）。
5. IF 「stage」欄位的值不在 `STAGE_ORDER` 五個值（`需求確認`／`開案`／`開發`／`測試`／`發布`）
   之內，THEN THE 呼叫端 SHALL 跳過該列並記錄警告；`STAGE_ORDER` 本身維持 5 個值不變（見前置
   條件，`需求確認` 目前抽樣沒有資料不代表移除該階段）。

---

### 需求 3：讀取「專案」層級資料（已實作，2026-08-25）

**使用者故事：** 身為後端開發者，我希望 Actor 能取得每個專案的客戶／PM，以便橫向總覽頁可依此
篩選與顯示卡片標頭。

**實際情況（比原本三個假設情境都更單純）**：既有 `300_員工專案` 試算表（`ProjectRosterSheetsClient`
已在讀的同一份）裡藏著一個先前沒發現的「專案」分頁，欄位為 `Github/Notion, Redmine 專案,
303 專案, 客戶, PM, 狀態`——其中「Github/Notion」欄的值（如 `HRM`、`JZNPMS`）與階段紀錄 Sheet 的
`project` 欄完全一致，比既有 `ProjectRosterSheetsClient` 讀的「專案工程師對照表」分頁（鍵是專案
全名／專案縮寫，對不上）更適合直接對應。不需要 n8n 額外同步、不需要新申請 Sheet 分享權限——
同一組 Service Account 早就對整份試算表有讀取權。

#### 驗收標準

1. THE **ProjectProfilesSheetsClient** SHALL 讀取 `300_員工專案` 試算表（spreadsheet ID
   `101fF0GlW2iwjC6TNQnNgKjUrxJg-3Ia5nCYox6haTNM`）的「專案」分頁，解析為
   `{ project: <Github/Notion 欄>, customer, pm }`（不解析「狀態」欄——那是專案層級的維運狀態，
   如「維護」，不是本頁「狀態」欄位的定義，見前置條件「已知資料特性」）。
2. THE **Sheets::FetchPhaseTracking** Actor SHALL 以卡片的 `project` 查找對應的
   `{ customer, pm }`，查無對應資料時該卡片的 `customer`／`pm` 為 `nil`（不視為錯誤，顯示為 —）。

---

### 需求 4：橫向總覽頁 — 篩選、排序、清單／甘特圖（已定案，與資料來源無關）

**使用者故事：** 身為戰情室使用者，我希望在 `/project_phase_tracking` 能依客戶、狀態、PM 篩選並
排序專案清單，並切換清單／甘特圖檢視。

#### 驗收標準

以下驗收標準的規則本身（篩選交集、排序表格與穩定排序、完成狀態四種組合對照表、日期差異計算、甘特圖
錨點與提前完成視覺標記、SVG 最小寬度）**已在 static prototype 定案，且已完成 Ruby 移植
（`ProjectPhaseTrackingHelper`，見 design.md），不受 Sheet 結構未確認狀態影響**，本 spec 只需將
資料來源從 `PROJECT_PROFILES`／`PHASE_RECORDS` 模擬資料換成需求 2、3 的真實 Sheets 資料，邏輯本身
直接沿用（Ruby 版重寫，不與 JS 共用程式碼）：

1. THE **PhaseTracking_Page** SHALL 提供依「客戶」「狀態」「PM」篩選的下拉選單、排序下拉選單，
   以及一個議題名稱／ID 自由文字搜尋欄位（`q`，對 `issue_id`／`issue_name`／`project` 三欄不分
   大小寫子字串比對，
   符合其一即算命中，與其他篩選為 AND 關係，見前置條件「新增：議題名稱／ID 搜尋」），規則同
   static prototype requirements.md 需求 2（其中「狀態」下拉選單的值域改為議題階段完成狀態，見
   前置條件「狀態」定義修正，不是 static prototype／原規劃假設的專案維運狀態）。
2. THE **PhaseTracking_Page** SHALL 提供清單／甘特圖切換，規則同 static prototype requirements.md
   需求 3（含甘特圖錨點方向、提前完成視覺標記語意、SVG 最小寬度與水平捲動）。
3. THE **PhaseTracking_Page** SHALL 以卡片呈現每個 **`(project, issue_id)`**（見前置條件「卡片分組
   單位」，卡片標題建議格式 `"#{project} - #{issue}"`），展開後顯示階段追蹤表，規則同 static
   prototype requirements.md 需求 4（含完成狀態四狀態組合對照表、`null`／缺失資料容錯、`reason`
   顯示規則）；篩選（客戶／狀態／PM）與排序仍以卡片所屬 `project` 的專案層級資料為準（見需求 3）。
4. 與 static prototype 的差異：**本頁為唯讀**，不提供「實際完成日期」欄位的互動編輯功能（static
   prototype 的 `editedActualDates` 純前端暫存機制在此不適用；若未來需要回寫，須另立需求並考慮回寫
   目標是 Sheet 還是透過 n8n 反向同步回 Notion，見「不納入範圍」）。
5. **重排程記錄的呈現（新增，2026-08-25 使用者確認）**：同一 stage 有多筆記錄時（見前置條件「已知
   資料特性」第 1 點），THE 階段追蹤表／甘特圖 SHALL 只以最新一筆作為該 stage 的主要呈現；THE 卡片
   展開狀態 SHALL 額外列出該 stage 其餘（較舊、已被取代）的記錄，並以次要樣式（例如較淡顏色／較小
   字體，標示為「曾經延誤的舊排程」）呈現，不得省略不顯示——每一筆延誤未完成的舊記錄本身即代表
   「應完成但未完成」的事實，是使用者要追蹤的重點。這些次要記錄之間 SHALL 依新舊排序，**較新的
   排在較舊的上面，最舊的排在最下面**（2026-08-25 使用者確認：「越舊的應該放下面」）。
6. **年度篩選（新增，2026-08-25 使用者確認）**：資料橫跨 2024／2025／2026 三個年度（見前置條件），
   THE **PhaseTracking_Page** SHALL 提供年度篩選下拉選單，規則比照既有
   `project_history_controller#resolve_year`／`overview_years` 慣例：預設「今年」，使用者可明確
   選擇「全部年度」（以 `params.key?(:year)` 區分「使用者主動選了全部」與「表單尚未送出」，而非
   以空字串／`nil` 混用判斷）。⚠️ 篩選依據 SHALL 以卡片各 `(project, issue_id)` 底下 `planned_date`
   的年份為準，NOT 直接信賴 Sheet 的 `sheet_year` 欄位（該欄位部分列為空字串，見前置條件「已知
   資料特性」第 2 點，不可靠）。

---

### 需求 5：錯誤處理（沿用既有 Sheets Client 錯誤碼慣例）

**使用者故事：** 身為使用者，我希望 Sheets 讀取失敗時能看到清楚的錯誤訊息，而不是壞掉的頁面。

#### 驗收標準

1. IF **Sheets::FetchPhaseTracking** 呼叫 Client 時捕捉到 `Google::Apis::ClientError`，THEN THE
   Actor SHALL 比照既有 `Sheets::FetchProjectRoster` 慣例：狀態碼 404 或訊息含
   `"Unable to parse range"` 時以 `failure_code: :sheet_not_found` 回傳；403 時以
   `failure_code: :access_denied` 回傳；其餘（含非 `Google::Apis::ClientError` 的未預期例外）以
   `failure_code: :internal_error` 回傳。
2. IF **Sheets::FetchPhaseTracking** 失敗，THEN THE **PhaseTracking_Page** SHALL 顯示錯誤訊息，不
   顯示任何篩選表單或資料區塊，HTTP 狀態碼依 `failure_code` 對應（比照 `rails-standards.md` 對應
   表）。
3. IF **ProjectProfilesSheetsClient** 讀取失敗（客戶／PM 對照表），THEN 比照既有
   `warroom-project-history-real-source` 對 Roster 失敗的降級處理慣例，客戶／PM 欄位顯示 `—`，
   不視為整頁錯誤——階段紀錄才是本頁核心資料（已實作，`profiles_unavailable`）。

---

## 不納入範圍

- 既有 305/306/307／專案歷程 Rails 功能
- n8n workflow 本身的建立與維護（Notion → Google Sheets 同步邏輯，屬於另外的 n8n 開發任務，不在本
  spec 範圍）
- 資料寫回 Notion 或 Sheet（唯讀）
- 工時（預估／實際）欄位（static prototype 已明確排除，本 spec 不重新引入）
- JSON API endpoint（比照既有 307／`project_history` 慣例，先做 HTML 頁面）

> 以下兩項原列於不納入範圍，實作過程中經使用者要求已納入並完成，故從此列表移除（2026-08-25）：
> - **同步調整 `docs/project-phase-tracking.html`**：使用者要求「docs 也需要一併調整」並選擇
>   「完整同步」，static prototype（`docs/project-phase-tracking.html`／`docs/js/
>   project-phase-tracking*.js`／`docs/css/style.css`）已改版至與 Rails 頁面一致（已實作）。
> - **Rails 端快取**：使用者要求「加上跟 305/306 一樣的 5 分鐘快取」，`PhaseRecordsSheetsClient`／
>   `ProjectProfilesSheetsClient` 皆已改用 `Rails.cache.fetch(..., expires_in: 5.minutes)`（已實作）。
