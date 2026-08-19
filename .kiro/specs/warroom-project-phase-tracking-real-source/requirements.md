# 需求文件

## 簡介

`warroom-project-phase-tracking-static-prototype` 已在 `docs/` 完成「專案階段追蹤」的靜態原型
（`docs/project-phase-tracking.html`），使用依單一 Notion 截圖仿造的模擬資料。本 spec 是該原型的
後續迭代：在既有 `warroom-data-api-prototype` Rails 專案中，比照 305/306/307／
`warroom-project-history-real-source` 既有資料流的模式，新增一組獨立的「專案階段追蹤」資料流與頁面
（`/project_phase_tracking`），改讀真實 **Notion API** 資料，取代靜態原型的模擬資料。這是本專案第一
個串接 Notion（而非 Google Sheets）的 real-source spec，架構沿用既有分層慣例，但憑證與 API 呼叫層
需要新建（Notion 而非 Google Service Account）。

**技術棧說明**：延續 `warroom-data-api-prototype` 既有例外（Ruby on Rails 獨立伺服器），不受
`project-standards.md`「技術限制」「響應式設計」段落約束；遵守 `rails-standards.md` 分層慣例
（Controller → Actor → Client → Blueprint → View）與統一錯誤格式；Notion 憑證存放比照
`rails-standards.md`「Google Sheets 憑證存放」段落的精神另訂一組 Notion 版規則（見 design.md），
本 spec 完成後可考慮回饋進共用 steering 文件。

---

## ⚠️ 前置條件（本 spec 目前無法開始實作，需以下事項確認後才能動工）

與既有 `warroom-project-history-real-source`（Google Sheets，規劃階段已有可用的 Service Account
可以邊做邊修正）不同，本 spec **目前完全沒有真實資料存取管道**：

1. **截圖來源的 Notion 資料庫不在使用者本人的 Notion 帳號／workspace 內**（已向使用者確認：
   「不是我的帳號」）。以本 session 連接的 Notion 整合（workspace「SeeYu」，
   `rita.chou@amastek.com.tw`）實際搜尋過該帳號下的工作區，找不到截圖中「日期／實際完成／專案／
   議題／類型／狀態／原因」這組欄位結構的資料庫——推測資料庫位於 AMASTek 內部另一個 Notion
   workspace 或 teamspace，此 session 的整合完全無權限存取。
2. 因此，以下事項在**真正開始寫 Client／Actor 程式碼之前**必須先確認，否則會重演
   `warroom-project-history-real-source` 「真實資料串接時發現的重大修正」的狀況（甚至更嚴重，因為
   目前連第一次探索性存取都做不到）：
   - 該 Notion 資料庫（截圖所見的「階段紀錄」表，範例列「內控調整2510」）的**實際擁有 workspace**
     是哪一個；由誰負責在該 workspace 建立 **Notion Internal Integration**，並將此資料庫（以及
     待確認事項 2 提到、可能存在的「專案」資料庫）分享給該 Integration。
   - 取得該 Integration 的 **API token**（Notion 稱為 Internal Integration Secret），並依
     `rails-standards.md` 既有慣例（憑證僅能存於 Rails encrypted credentials 或環境變數，不得寫入
     原始碼／版控）安全地提供給部署此 Rails 專案的人。
   - 該資料庫的 **database ID**（Notion 頁面 URL 中的 32 碼十六進位字串）。
   - 若確認真的存在獨立的「專案」資料庫（提供客戶／PM／狀態／專案層級預計完成日期，見待確認事項
     2），其 database ID 與確切欄位名稱／型別。

### 需要向該 Notion workspace 管理者／資料庫擁有者索取的具體項目

以下是需要請「該資料庫所在 workspace 的人」實際動手做、並回傳結果的清單，供轉發：

1. **建立 Internal Integration**：前往該 workspace 的
   `https://www.notion.so/profile/integrations`（或 workspace 設定 →「Connections」→
   「Develop or manage integrations」），新增一個 **Internal Integration**（不是 Public OAuth
   App）。權限（Capabilities）僅需勾選 **「Read content」**（本 spec 唯讀，見「不納入範圍」，不需要
   「Insert content」「Update content」「Read comments」「Read user information」）。
2. **複製 Integration Secret**：建立後會產生一組以 `ntn_`（或舊版 `secret_`）開頭的字串，這就是
   需求 1.1 的 `NOTION_INTEGRATION_TOKEN`。**這組字串等同密碼，只能透過安全管道（不是聊天訊息／
   email 明文）傳遞給部署此 Rails 專案的人，且不得貼進任何會進版控的檔案。**
3. **⚠️ 最容易漏掉的一步：把資料庫「分享」給這個 Integration。** 建立 Integration 本身**不會**自動
   給它任何資料存取權——必須另外到目標資料庫（截圖中的「階段紀錄」資料庫，若情況 3(a) 成立則還有
   「專案」資料庫）頁面，點右上角「...」選單 →「Connections」（或「連結」）→ 把剛建立的 Integration
   加進去，或是在該資料庫的**上層父頁面**做一次分享（分享會沿頁面階層往下套用到所有子資料庫）。沒
   做這一步，API 呼叫會回傳 404，看起來像是 database ID 錯誤，但其實是分享沒做。
4. **提供 database ID**：分享完成後，把該資料庫在瀏覽器網址列的完整連結傳回來即可（連結中
   `notion.so/<workspace>/<32碼十六進位字串>?v=...` 的那串十六進位字串就是 database ID，不需要
   手動擷取）。
5. **確認 Notion plan 是否支援 API**：Notion 的 Free plan 部分帳號可能有 API 呼叫量或功能限制，若
   該 workspace 是付費 plan 通常沒有這個問題，僅在真的遇到權限錯誤時才需要往這個方向排查。
3. **在上述資訊到位前**，本文件下方的需求僅是**依 static prototype 的假設與 Notion API 官方文件
   通用行為**寫成的草案，用來先把 Rails 分層架構、Client／Actor／Blueprint 骨架、憑證存放慣例、
   錯誤碼對應規劃出來（這些部分不依賴實際資料，可以先動工，見「可先行實作的部分」）；凡是**依賴
   實際 Notion schema**的細節（欄位對應、`類型`／`狀態` 完整合法值、5 階段預計日期的真實來源）皆
   明確標記為「⚠️ 待真實 schema 確認」，實作時 SHALL 以實際 API 回應為準，不得逕行採用本文件的
   假設值。

### 可先行實作的部分（不依賴真實 Notion schema，可現在動工）

- Rails 路由、Controller 骨架（`/project_phase_tracking`）
- `NotionCredentials` 共用 module（比照 `GoogleSheetsCredentials`，見 design.md）
- Notion API 通用 HTTP client 基礎設施（認證標頭、分頁游標處理、逾時／重試策略、共用錯誤碼對應）
- Blueprint／View 的欄位形狀（沿用 static prototype 已定義的 `PROJECT_PROFILES`／`PHASE_RECORDS`／
  `STAGE_ORDER` 概念，見詞彙表）
- 差異天數計算、完成狀態判斷（`computeRowState` 邏輯的 Ruby 版本）、甘特圖 SVG 幾何計算——這些是
  static prototype 已定案、與資料來源無關的純邏輯，可直接照 `docs/js/project-phase-tracking.js`
  的規則用 Ruby 重寫一份（各自獨立實作，不共用程式碼，同既有 Ruby/JS 分離慣例）

### 需要真實 schema 才能定案的部分（⚠️ 標記於下方對應需求）

- 兩個 Notion database 各自的 Client（欄位如何從 Notion API 的 property JSON 解析出來，因 Notion
  API 依 property 型別回傳不同 JSON 結構，例如 `date`／`select`／`status`／`relation`／`rich_text`
  形狀皆不同）
- `類型` 欄位的完整合法值（是否真的是 `STAGE_ORDER` 五個值）
- 是否真的存在獨立的「專案」資料庫、其與階段紀錄資料庫的 relation 欄位名稱
- 5 個階段的「預計完成日期」在真實資料中從何而來（見 static prototype 待確認事項 1）

---

## 詞彙表

（沿用 `warroom-project-phase-tracking-static-prototype` 的定義，欄位對應改為來自 Notion API 而非
硬編碼模擬資料）

- **PhaseTracking_Page**：`/project_phase_tracking`，本 spec 新增的 Rails 頁面。
- **NotionCredentials**：共用 module，封裝 Notion Internal Integration token 的讀取（Rails
  credentials 優先、環境變數 fallback），比照 `GoogleSheetsCredentials`。
- **PhaseRecordsNotionClient**：封裝「階段紀錄」資料庫讀取的 Client（⚠️ database ID／欄位對應待
  確認）。
- **ProjectProfilesNotionClient**：封裝「專案」資料庫讀取的 Client，**若該資料庫真的存在**（⚠️
  待確認事項 2）。
- **Notion::FetchPhaseTracking**：本 spec 的主要業務邏輯 Actor，呼叫上述 Client，回傳彙總後的
  `PROJECT_PROFILES`／`PHASE_RECORDS` 形狀（欄位定義見 static prototype design.md 的 Prototype
  Data Contract，本 spec 沿用相同欄位命名）。

---

## 需求

### 需求 1：Notion 憑證與連線基礎設施（可先行實作）

**使用者故事：** 身為後端開發者，我希望有一套統一、安全的 Notion API 連線方式，以便後續所有 Notion
Client 共用。

#### 驗收標準

1. THE **NotionCredentials** module SHALL 依序嘗試 Rails encrypted credentials
   （`Rails.application.credentials.dig(:notion, :integration_token)`）與環境變數
   `NOTION_INTEGRATION_TOKEN`，找不到任一來源時視為憑證缺失。
2. THE 憑證 SHALL 不得寫入任何原始碼檔案或提交至版控，比照 `rails-standards.md` 既有 Google Sheets
   憑證存放規則。
3. THE Notion API 呼叫 SHALL 使用官方 REST API（`https://api.notion.com/v1/...`），標頭包含
   `Authorization: Bearer <token>`、`Notion-Version: <固定版本字串>`（版本號於 design.md 訂定，避免
   Notion 於呼叫端無感更新 API 版本造成非預期欄位格式變動）。
4. IF Notion API 回傳 401，THEN THE 呼叫端 Actor SHALL 以 `failure_code: :access_denied` 回傳失敗；
   IF 回傳 404，THEN SHALL 以 `failure_code: :sheet_not_found`（沿用既有錯誤碼命名，語意為「找不到
   指定資料來源」，Notion 情境下代表 database ID 錯誤或 Integration 未被分享該資料庫）回傳失敗；
   其餘非預期錯誤 SHALL 以 `failure_code: :internal_error` 回傳。

---

### 需求 2：讀取「階段紀錄」資料庫（⚠️ 待真實 schema 確認）

**使用者故事：** 身為後端開發者，我希望 Actor 能讀取真實 Notion 階段紀錄資料庫，取得每個專案各階段
的預計／實際完成日期。

#### 驗收標準

1. WHEN **Notion::FetchPhaseTracking** 被呼叫，THE **PhaseRecordsNotionClient** SHALL 對
   ⚠️ **待確認**的 database ID 呼叫 Notion Query Database API，取得全部列。
2. THE **PhaseRecordsNotionClient** SHALL 將每一列的 Notion property 解析為
   `{ project, stage, planned_date, actual_date, status, reason }`（見詞彙表），對應規則
   ⚠️ **待確認**：static prototype 依單一截圖假設的對應為「日期→planned_date、實際完成→
   actual_date、專案→project、類型→stage、狀態→status、原因→reason」，但截圖無法確認這些欄位在
   Notion API 回傳的 property 型別（例如「專案」究竟是 `relation`、`rich_text` 還是 `title`；
   「類型」是 `select` 還是 `status`），型別不同會導致解析程式碼完全不同，須以實際 API 回應（例如
   呼叫一次 Notion 的 `retrieve a data source` API 取得 schema）為準,不得假設。
3. IF 「類型」欄位的值不在 `STAGE_ORDER` 五個值之內，THEN THE **PhaseRecordsNotionClient** SHALL
   跳過該列並記錄警告（不確定的合法值清單見「前置條件」，真實確認後可能需要調整 `STAGE_ORDER`
   本身，而非在這裡過濾）。
4. 分頁（pagination）：THE **PhaseRecordsNotionClient** SHALL 處理 Notion Query API 的
   `has_more`／`next_cursor` 分頁機制，直到取得全部列（Notion 單次查詢預設上限 100 列）。

---

### 需求 3：讀取「專案」資料庫（⚠️ 待確認是否存在，待真實 schema 確認）

**使用者故事：** 身為後端開發者，我希望 Actor 能取得每個專案的客戶／PM／狀態／專案層級預計完成
日期，以便橫向總覽頁可依此篩選與顯示卡片標頭。

#### 驗收標準

1. ⚠️ **待確認**：static prototype 假設存在一個獨立的「專案」Notion database，透過「專案」relation
   對應到需求 2 的階段紀錄。真實情況可能是：(a) 確實有這樣一個獨立 database；(b) 客戶／PM／狀態
   實際上是階段紀錄 database 本身的欄位（每列重複記錄）；(c) 客戶／PM／狀態來自完全不同的系統
   （例如既有 Google Sheets `300_員工專案`，那本 spec 應改為同時讀取 Sheets 與 Notion 兩種來源，
   比照既有 `warroom-project-history-real-source` 讀取 Roster 的模式）。三種情況的 Client／Actor
   設計差異很大，須先確認才能定案此需求的驗收標準。
2. IF 確認為情況 (a)，THEN THE **ProjectProfilesNotionClient** SHALL 對該 database 呼叫 Notion
   Query Database API，解析為 `{ project_name, customer, pm, status, planned_completion_date }`。
3. IF 確認為情況 (c)（客戶／PM 來自既有 `300_員工專案` Google Sheets），THEN THE
   **Notion::FetchPhaseTracking** Actor SHALL 比照 `Sheets::FetchProjectHistory` 呼叫既有
   `Sheets::FetchProjectRoster`，不重新設計 join 邏輯。

---

### 需求 4：橫向總覽頁 — 篩選、排序、清單／甘特圖（沿用 static prototype 已定案規則）

**使用者故事：** 身為戰情室使用者，我希望在 `/project_phase_tracking` 能依客戶、狀態、PM 篩選並
排序專案清單，並切換清單／甘特圖檢視。

#### 驗收標準

以下驗收標準的規則本身（篩選交集、排序表格與穩定排序、完成狀態四種組合對照表、日期差異計算、甘特圖
錨點與提前完成視覺標記、SVG 最小寬度）**已在 static prototype 定案，不受 Notion schema 未確認狀態
影響**，本 spec 只需將資料來源從 `PROJECT_PROFILES`／`PHASE_RECORDS` 模擬資料換成需求 2、3 的真實
Notion 資料，邏輯本身直接沿用（Ruby 版重寫，不與 JS 共用程式碼）：

1. THE **PhaseTracking_Page** SHALL 提供依「客戶」「狀態」「PM」篩選的下拉選單與排序下拉選單，規則
   同 static prototype requirements.md 需求 2。
2. THE **PhaseTracking_Page** SHALL 提供清單／甘特圖切換，規則同 static prototype requirements.md
   需求 3（含甘特圖錨點方向、提前完成視覺標記語意、SVG 最小寬度與水平捲動）。
3. THE **PhaseTracking_Page** SHALL 以卡片呈現每個專案，展開後顯示固定 5 列階段追蹤表，規則同
   static prototype requirements.md 需求 4（含完成狀態四狀態組合對照表、`null`／缺失資料容錯、
   `reason` 顯示規則）。
4. 與 static prototype 的差異：**本頁為唯讀**，不提供「實際完成日期」欄位的互動編輯功能（static
   prototype 的 `editedActualDates` 純前端暫存機制在此不適用；若未來需要透過此頁面回寫 Notion，
   須另立需求，見「不納入範圍」）。

---

### 需求 5：錯誤處理

**使用者故事：** 身為使用者，我希望 Notion API 呼叫失敗時能看到清楚的錯誤訊息，而不是壞掉的頁面。

#### 驗收標準

1. IF **Notion::FetchPhaseTracking** 失敗，THEN THE **PhaseTracking_Page** SHALL 顯示錯誤訊息，不
   顯示任何篩選表單或資料區塊，HTTP 狀態碼依 `failure_code` 對應（比照需求 1.4 與
   `rails-standards.md` 對應表）。
2. IF 需求 3 確認為「專案」資料庫獨立存在、但該資料庫讀取失敗，THEN 比照既有
   `warroom-project-history-real-source` 對 Roster 失敗的降級處理慣例（見需求 6.2），客戶／PM／
   狀態欄位顯示 `—`，不視為整頁錯誤——**此規則待需求 3 確認後才能真正定案**，此處先記錄設計意圖。

---

## 不納入範圍

- 修改既有 `docs/project-phase-tracking.html`（static prototype 頁面）或既有 305/306/307／專案歷程
  Rails 功能
- 資料寫回 Notion（唯讀，即使 Notion API 支援寫入）
- 工時（預估／實際）欄位（static prototype 已明確排除，本 spec 不重新引入）
- JSON API endpoint（比照既有 307／`project_history` 慣例，先做 HTML 頁面）
- 資料庫或任何本地持久化（Rails 端不快取 Notion 回應，每次請求即時查詢，除非後續發現效能問題另立
  spec，比照既有 `warroom-sheets-fetch-performance` 的先例）
