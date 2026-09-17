# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 儲存庫結構

本 repo 有**兩套獨立的程式碼，不可混用**：

| 目錄 | 內容 | 技術限制 |
| --- | --- | --- |
| `docs/` | 靜態展示站（GitHub Pages，發布來源為 `main` 分支的 `/docs` 資料夾，deploy-from-branch、無 CI／build 步驟） | 純 HTML／CSS／JS、模擬資料、無框架、無建置工具、不呼叫外部 API |
| `warroom-data-api-prototype/` | Rails 8 應用，串接真實 Google Sheets，是**目前的發展方向** | 不受上述限制（已於 spec 中宣告例外） |

動工前先確認要改的檔案落在哪一邊，再套用對應的規則。

`.kiro/` 是 spec-driven 工作區：`steering/`（always-on 規範）、`specs/<name>/{requirements,design,tasks}.md`、`skills/`、`hooks/`。**動手前先讀 `.kiro/steering/project-standards.md`、`.kiro/steering/rails-standards.md` 與對應 spec 的 `requirements.md`**——spec 的「技術棧說明」段落可以宣告例外（例如 Rails 應用就是靜態站規則的例外）。這兩份 steering 才是權威規範，本檔僅為摘要。

根目錄的 `project-rules.md` 是 `docs/` 規則的舊版節錄；`.kiro/steering/project-standards.md` 才是正本（且額外載明例外條款與分支命名）。兩者衝突時以 steering 為準。

介面語言一律繁體中文（兩邊皆適用）。

## `docs/` —— 靜態站

- 純 HTML／CSS／JavaScript，不用 React／Vue／Angular，不用 Node.js／Vite／任何建置工具，不呼叫外部 API
- 資料一律 hardcode（寫在 HTML 或 JS 物件／陣列裡）
- 需支援桌機／平板／手機，用 CSS media query 實作
- 所有檔案放在 `docs/` 底下；GitHub Pages 直接服務 `main` 分支的 `/docs`，不需要 `.nojekyll`、`gh-pages` 分支或任何 workflow（見 `.kiro/skills/github-pages-deploy.md`）

本機預覽：

```bash
python3 -m http.server 8123 --directory docs
```

結構：每個儀表板一個 HTML 頁面配一支 JS（`docs/index.html`、`issues.html`、`burndown.html`、`project-history-overview.html`、`project-phase-tracking.html`、`project-progress.html`，各自對應 `docs/js/<name>.js`）。模擬資料量大的頁面把資料獨立成 `docs/js/<name>-data.js`，讓 view 模組只管渲染。共用的 header 行為（主題切換）放在 `docs/js/entry.js`；樣式只有一份 `docs/css/style.css`。

主題：**預設淺色**，深色由 `html[data-theme="dark"]` 覆蓋 CSS 變數。Rails 應用在自己的 `app/assets/stylesheets/application.css` 裡有一份同樣結構的複本，**兩份樣式表是各自獨立的**，改主題通常兩邊都要改。

## `warroom-data-api-prototype/` —— Rails 應用

Ruby 3.3.12、Rails ~8.1。主要 gem：`service_actor`、`blueprinter`、`pagy`、`google-apis-sheets_v4`／`googleauth`、`importmap-rails`／`turbo-rails`／`stimulus-rails` + `propshaft`（無 Node／打包步驟）。**沒有資料庫**——沒有 `config/database.yml`，`spec/rails_helper.rb` 設定 `config.use_active_record = false`。所有狀態都來自 Google Sheets 加上 `Rails.cache`。

### 常用指令

```bash
cd warroom-data-api-prototype
bin/setup                 # bundle install + 清 log/tmp（無 db 步驟）
bin/rails server -p 3000  # 啟動應用
bundle exec rspec                                                       # 全部測試
bundle exec rspec spec/actors/sheets/fetch_project_progress_spec.rb     # 單一檔案
bundle exec rspec spec/actors/sheets/fetch_project_progress_spec.rb:42  # 單一案例
bin/rubocop                # 風格檢查（Omakase Rails style）
bin/brakeman --no-pager    # 靜態安全掃描
bin/bundler-audit          # gem 弱點掃描
bin/importmap audit        # JS 依賴弱點掃描
```

CI（`.github/workflows/ci.yml`）每次 push／PR 會跑 brakeman、bundler-audit、importmap audit 與 rubocop，**沒有 rspec job**，所以推送前要自己跑測試。`bin/ci` 可在本機跑完整的同一套流程。

### 強制分層（`.kiro/steering/rails-standards.md`）

嚴格單向、不得跳層或反向：

- **Controller**（`app/controllers/`）——只呼叫單一 Actor，把結果渲染為 JSON 或交給 View。不做資料存取、不呼叫外部服務、不做轉換。共用的篩選解析抽在 `app/controllers/concerns/`（`YearFilterable`、`DateRangeFilterable`）。
- **Actor**（`app/actors/`，依領域分目錄：`app/actors/sheets/` 讀試算表、`app/actors/summary/` 做跨來源彙整）——`service_actor` 慣例：繼承 `ApplicationActor`、單一 `call` 入口、用 `input`／`output` 宣告介面。所有商業邏輯（讀取、正規化、驗證、分組）都在這層。Actor 可組合其他 Actor。
- **Client**（`app/clients/`）——一個 class 只包一個外部服務呼叫，只取原始資料，不做業務層轉換或驗證。`GoogleSheetsCredentials` 是共用的憑證載入器。
- **Blueprint**（`app/blueprints/`，Blueprinter）——輸出欄位的唯一定義來源，Controller 與 View 共用同一份，欄位清單不得在別處重複列舉。
- **View + Helper**（`app/views/<page>/`、`app/helpers/<page>_helper.rb`）——ERB 伺服器渲染；圖表（燃盡線、甘特條、KPI bar）是 helper 產生的 inline SVG。Helper 只放呈現用的計算（座標／比例／CSS class 對應），是 Actor 以外唯一有實質邏輯的地方，有自己的 `spec/helpers/`。Turbo／Stimulus 用得很少，多數互動是 query param 連結交給 Controller 處理。

錯誤一律 `{ "error": { "code": "<代碼>", "message": "<描述>" } }`。Actor 以 `fail!(failure_code: :xxx, message: "...")` 失敗；Controller 對應 HTTP 狀態：`sheet_not_found`→404、`access_denied`→403、`invalid_data_format`→422、`internal_error`→500（可依 spec 擴充）。

降級是刻意設計：非核心資料源失敗時設 `*_unavailable` output、頁面照樣渲染，只有核心資料源失敗才中止 request。

### Sheets 快取

每個 Sheets client 都把 API 呼叫包在 `Rails.cache.fetch(CACHE_KEY, expires_in: 5.minutes)` 裡——**快取只在 Client 層**，Actor 與 Controller 都不碰。

- 例外不會被快取，失敗的請求下次會重試，也不會蓋掉既有的好資料。
- `ProjectProgressSheetsClient` 另有 `fetch_rows(force: true)` 與 `.../fetched_at` key。頁面層級的「重新整理資料」按鈕已移除，改為入口頁唯一入口 `POST /refresh`（`Rails.cache.clear`，一次清掉所有 Sheets 快取）。其他 client 刻意沒有 force／fetched_at（見各檔註解），不要臆測著補。
- `config.cache_store` 在 development 是 `:memory_store`、test 是 `:null_store`，所以測試裡快取形同停用，除非該 spec 明確 stub `Rails.cache`。

### Google Sheets 串接慣例

- 憑證順序：Rails encrypted credentials（`Rails.application.credentials.dig(:google_sheets, :service_account_json)`，本機開發建議）→ 環境變數 `GOOGLE_SHEETS_CREDENTIALS_JSON`（CI／部署）→ 都沒有則 Actor 以 `internal_error` 失敗。不得硬寫於原始碼。
- 認證 scope 一律唯讀（`spreadsheets.readonly`）。
- API 回傳的字串會被標記為 `ASCII-8BIT`（即使內容是合法 UTF-8），要在 client 邊界 `force_encoding(Encoding::UTF_8)`，否則與中文常值併接時會噴 `Encoding::CompatibilityError`。
- API 會省略列尾端的空白儲存格——欄位對應前一定要先補滿到固定欄數，否則欄位會錯位。
- 缺少必要欄位的個別紀錄只跳過該筆，絕不讓整個 request 失敗。但「必要」要定義得夠窄：305 只有專案名稱與任務名稱是必要的，狀態空白視為「未完成」、負責人空白視為「未指派」——把這些列藏起來等於讓戰情室看不到真正在延誤、甚至沒人認領的工作。
- 日期正規化失敗時保留原始字串，不拋例外、不視為 `invalid_data_format`。
- 會逐年更換的試算表／分頁一律用環境變數切換，不依系統日期判斷（跨年當天不保證新的已建好）。權威清單是 `app/clients/` 裡的 `ENV.fetch`：目前有 `PROJECT_PROGRESS_SPREADSHEET_ID`、`PROJECT_PROGRESS_SHEET_NAME`、`PROJECT_PROGRESS_GRACE_SHEET_NAME`、`BURNDOWN_SHEET_NAME`、`PROJECT_ROSTER_SHEET_NAME`、`PROJECT_PROFILES_SHEET_NAME`；新增時記得同步更新 README 的表格。
- **注意衍生分頁**：305 的來源是年度分頁（n8n 從各專案 Slack 頻道同步），不是依類型切出來的 `功能`／`PR`／… 分頁——那些是衍生視圖，會落後於來源且會漏掉「未分類」。接新資料源前先確認哪一個分頁才是真正的來源。
- 新開的 worktree 需要手動複製 `config/credentials/development.key`（gitignored、每個 checkout 各自持有），從主 checkout 複製即可，不要重新產生。

### 測試慣例

`spec/` 對應各層（`actors/`、`clients/`、`blueprints/`、`controllers/`、`helpers/`、`requests/`）。不用 WebMock／VCR：Actor spec 直接 stub client 的類別方法（`allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return(rows)`，rows 用含標題列的字面陣列），Client spec 則 stub Google API service 物件。`ActiveSupport::Testing::TimeHelpers` 已全域引入——凡是會跟「今天」比較的（逾期、本週、年度預設值到處都是）都要用 `travel_to` 固定時間。

### 目前路由

`/`（入口頁）、`/dashboard`（305 專案任務進度）、`/issues`（306 臭蟲議題）、`/burndown`（307 人時燃盡）、`/project_history`（專案歷程）、`/project_phase_tracking`（專案階段追蹤）、`/executive_summary`（跨來源週報）、`/pm_weekly_report`（PM 週報）；JSON API 在 `/api/project_progress`、`/api/issue_dashboard`；`POST /refresh` 清除全站快取。

View 使用 Hotwire。篩選列與麵包屑包在 turbo frame 裡，因此「離開本頁」的連結必須標 `data-turbo-frame="_top"`，否則 Turbo 會顯示「Content missing」。同理，靠 `DOMContentLoaded` 綁定的事件在 Turbo 換頁後不會重新執行（該事件整個工作階段只觸發一次），需要一併監聽 `turbo:load`。

## Spec 工作流程（兩邊適用）

- `.kiro/skills/karpathy-guidelines.md` 是現行的房規：選最簡單可行方案、不做臆測性抽象（要有三個具體使用情境才抽）、動工前先陳述可驗證的完成標準、對照標準驗證後才算完成、能改既有檔就不要新增檔、死碼直接刪掉不要註解掉。
- 寫程式前先讀該 spec 的 `requirements.md` 與 `design.md` 以及適用的 steering；`tasks.md` 追蹤 checkbox 層級的進度，常附有任務相依波次圖。
- Spec 成對出現：`*-static-prototype` 做出 `docs/` 頁面，對應的 `*-real-source` 把它搬到 Rails ＋真實 Sheets。改 Rails 頁面時，相關的是 `-real-source` 那一份。
- 規格與實作不一致時要一起改：以真實資料驗算後推翻規格假設的情況實際發生過（見 `warroom-data-api-real-source/requirements.md` 需求 2.1、4.3a、4.3b 的附註），改程式時要同步更新 requirements／design／tasks。
- 分支命名：`<類型>/<簡短描述>`（全小寫、連字號分隔），類型 ∈ `feature|fix|chore`，不需 ticket 編號。
- `.kiro/hooks/frontend-quality-review.json` 與 `.kiro/hooks/rails-backend-quality-review.json` 定義了唯讀的 PostFileSave 檢查清單（前者針對 `docs/*.{html,css,js}` 的語意 HTML／響應式 CSS／禁用技術；後者針對 `*.rb`／`*.erb` 的 service_actor／Blueprinter／RSpec 覆蓋／N+1／rubocop），就算 hook 沒觸發，手動照著自我檢查也有價值。
- 本 codebase 的註解主要解釋「為什麼這樣做」（多為中文，常引用需求編號）。新增那種後人容易誤「簡化」掉的邏輯時，請比照補上理由。
