# 實作計畫：306 臭蟲議題真實資料串接

## 概述

把 306 臭蟲議題資料從 `docs/issues.html` prototype 的模擬資料，串接為真實 Google Sheets
（`306_臭蟲議題紀錄`）資料，實作於 `warroom-data-api-prototype` Rails 專案，遵循
[rails-standards.md](../../steering/rails-standards.md) 分層。與既有 305 資料流平行存在，不修改
305 的任何檔案。範圍涵蓋月度 KPI、每日趨勢、議題明細（含依專案分類統計、歸屬類型標示、Redmine 連結）；
工程師負載表／專案清單表經評估後不納入範圍。

---

## 任務

- [x] 1. 確認真實分頁名稱
  - [x] 1.1 取得 `1RdU2p9b7fwNgO5e59jN-00a5KLOQ91xrFhj2NenyKTc` 完整分頁名稱清單
    - 透過解析試算表原生 XLSX 匯出檔的 `xl/workbook.xml`（`<sheet name="..." state="visible|hidden">`
      標籤）取得官方分頁清單與可見性狀態，比人工開啟試算表逐一核對更可靠、不遺漏
    - 結果：`month_kpi`／`daily_kpi`（顯示）、`raw_2023`〜`raw_2025`（隱藏）、`raw_2026`（顯示）、
      **新發現** `raw_2027`（隱藏，僅標題列無資料）、`工程師比例表`／`專案工程師對照表`（顯示，即
      原推測的「工程師負載表」「專案清單表」，已確認真實名稱但仍不納入範圍）、`2026_測試臭蟲`／
      `2026_客訴問題`（顯示，即先前描述的兩個用途不明分頁，已知真實名稱但用途仍待確認）
    - `raw_2023`〜`raw_2026` 原推測分頁名稱正確；已將 `raw_2027` 加入 `IssueSheetsClient.ISSUE_SHEETS`
    - 分頁隱藏狀態不影響 Google Sheets API 讀取，無需額外處理
    - 已更新 requirements.md「簡介」段落分頁結構表格與 design.md 的 `IssueSheetsClient` 常數
    - _需求：1.1, 1.2_

- [x] 2. `IssueSheetsClient`
  - [x] 2.1 新增 `app/clients/issue_sheets_client.rb`
    - 依 [design.md](design.md) 實作 `fetch_month_kpi_rows`／`fetch_daily_kpi_rows`／`fetch_issue_rows`
    - 沿用既有 `SheetsApiClient` 的憑證讀取、UTF-8 重標記邏輯（維持獨立實作，未抽共用 module，見
      design.md「元件與介面」段落的抽象化取捨說明）
    - _需求：2.1, 2.2_

  - [x] 2.2 單元測試：`spec/clients/issue_sheets_client_spec.rb`
    - stub `SheetsService`，驗證分頁名稱／range／合併邏輯（`raw_2023`〜`raw_2027` 僅保留第一個標題列，
      含 `raw_2027` 空分頁邊界情況）、UTF-8 重標記、憑證 fallback（Rails credentials → ENV → 例外）、
      Google API 錯誤（403/404）原樣拋出不吞掉
    - 15 examples, 0 failures（`bundle exec rspec spec/clients/issue_sheets_client_spec.rb`）；
      全專案回歸 `bundle exec rspec` 99 examples, 0 failures
    - _需求：3.1, 4.1, 5.1_

- [x] 3. `Sheets::FetchIssueDashboard` — 月度 KPI／每日趨勢解析
  - [x] 3.1 新增 `app/actors/sheets/fetch_issue_dashboard.rb`，實作 `parse_month_kpi`
    - 不解析 `Top3` 欄位，不納入輸出（負責人不作為統計主軸，見需求 3.3）
    - 數值欄位（complaint/testing/total_bug/completed/unresolved/block_rate/avg_days/sla_rate）
      有效則轉換為 Integer／Float，否則保留原始字串不拋出例外（沿用 305
      `Sheets::FetchProjectProgress` 的 `delay_days` 容錯慣例）
    - `call` 目前僅串接 `parse_month_kpi`／`parse_daily_kpi`；`issues`／`project_breakdown` 待
      Task 4、錯誤處理待 Task 5 補上
    - _需求：3.2, 3.3_

  - [x] 3.2 實作 `parse_daily_kpi`
    - 空字串 `total` 視為 0；結果依 `date` 升冪排序
    - _需求：4.2, 4.3, 4.4_

  - [x] 3.3 單元測試：`spec/actors/sheets/fetch_issue_dashboard_spec.rb`
    - `#parse_month_kpi`／`#parse_daily_kpi` 私有方法直接測試（`.send`，比照既有
      `fetch_project_progress_spec.rb` 慣例）：欄位對應、Top3 排除、空列跳過、必要欄位空白跳過、
      非數字值容錯、日期排序；`#call` 驗證 stub `IssueSheetsClient` 後兩個 output 正確填入
    - 13 examples, 0 failures；全專案回歸 112 examples, 0 failures

- [x] 4. `Sheets::FetchIssueDashboard` — 議題明細解析與依專案分類統計
  - [x] 4.1 實作 `parse_issues`
    - 欄位對應（issue_id/subject/type/tracker/status/assigned_to/start_date/due_date/work_days/
      project，跳過 `sheet_name`）、日期正規化（新增獨立實作的 `normalize_date`，邏輯與 305
      `Sheets::FetchProjectProgress#normalize_date` 相同，未抽共用 module，見 design.md 的抽象化
      取捨說明）、`work_days` 整數轉換容錯（沿用 `safe_integer`）、必要欄位（issue_id/subject/status）
      任一空白則跳過該列，其餘正常列不受影響
    - _需求：5.2, 5.3, 5.4, 5.5_

  - [x] 4.2 實作 `compute_project_breakdown(issues)`
    - 依 `project` 分組統計 `complaint`／`testing`／`other` 筆數與 `total`，純記憶體運算（不重複呼叫
      `IssueSheetsClient`），邏輯與 prototype 的 `computeProjectBreakdown` 一致；`project` 為空白時
      歸類為「未分類」
    - `call` 已串接 `self.issues = parse_issues(...)` 與 `self.project_breakdown =
      compute_project_breakdown(issues)`；錯誤處理仍待 Task 5
    - _需求：3a.1, 3a.2_

  - [x] 4.3 單元測試：擴充 `spec/actors/sheets/fetch_issue_dashboard_spec.rb`
    - `#parse_issues`：欄位對應（含 sheet_name 排除）、日期正規化、空值保留 nil、work_days 轉換
      與容錯、三種必要欄位各自空白時跳過（其餘正常列不受影響）、空列跳過
    - `#compute_project_breakdown`：分組計數與 total 加總、空白 project 歸類「未分類」、空清單
    - `#call`：驗證 stub 後 `issues`／`project_breakdown` 正確填入
    - 29 examples, 0 failures；全專案回歸 128 examples, 0 failures

- [x] 5. `Sheets::FetchIssueDashboard` — 錯誤處理
  - [x] 5.1 實作統一錯誤對應（404/403/內部錯誤），任一資料類別失敗即整體失敗
    - 沿用 [rails-standards.md](../../steering/rails-standards.md) 的 `failure_code` 對應表，
      邏輯與 305 `Sheets::FetchProjectProgress` 完全相同：`404` 或訊息含 `"Unable to parse range"`
      → `:sheet_not_found`；`403` → `:access_denied`；其餘 `Google::Apis::ClientError` →
      `:internal_error`；任何其他 `StandardError`（如憑證缺失）→ `:internal_error`
    - _需求：6.1, 6.2_

  - [x] 5.2 單元測試：`spec/actors/sheets/fetch_issue_dashboard_spec.rb`
    - 涵蓋 404／`"Unable to parse range"`／403／其他狀態碼／`StandardError`／`RateLimitError`
      六種錯誤情境對應的 `failure_code`；驗證任一讀取類別失敗即整體失敗（`result.success?` 為
      false），而非部分成功回傳
    - 全檔累計 36 examples, 0 failures；全專案回歸 135 examples, 0 failures

- [x] 6. 檢查點 — Actor 層驗證
    - 以 `bin/rails runner`（`RAILS_ENV=test`）stub `IssueSheetsClient` 三個 fetch 方法後實際呼叫
      `Sheets::FetchIssueDashboard.result`，確認 `success?` 為 true，四個 output 欄位
      （`month_kpi`／`daily_kpi`／`issues`／`project_breakdown`）結構皆符合 design.md 的「資料模型」

- [x] 7. Blueprints
  - [x] 7.1 新增 `MonthKpiBlueprint`／`DailyKpiBlueprint`／`IssueBlueprint`／`ProjectBreakdownBlueprint`
    - 比照既有 `ProjectTaskBlueprint` 慣例（`identifier` 欄位同時列於 `fields`）；`IssueBlueprint`
      刻意不包含「歸屬類型」／Redmine 連結（View-only 動態計算，見需求 5.6〜5.8）
    - 對應 spec：`spec/blueprints/{month_kpi,daily_kpi,issue,project_breakdown}_blueprint_spec.rb`，
      驗證 `render_as_hash` 恰好輸出預期欄位（含 `IssueBlueprint` 不外洩 `:attribution`／
      `:sheet_name` 的斷言）
    - 9 examples, 0 failures；全專案回歸 144 examples, 0 failures
    - _需求：7.4_

- [x] 8. API Endpoint
  - [x] 8.1 新增路由 `GET /api/issue_dashboard`、`Api::IssueDashboardController`
    - 回傳 `{ month_kpi, daily_kpi, issues, project_breakdown }`，透過 Blueprint 序列化；
      `error_status` 對應表比照既有 `Api::ProjectProgressController` 慣例獨立實作（未抽共用，
      沿用既有專案未曾為此抽象化的先例）
    - _需求：7.1, 7.3, 7.4_

  - [x] 8.2 Request spec：`spec/requests/api/issue_dashboard_spec.rb`
    - 驗證成功回傳（四個頂層 key、各 Blueprint 序列化正確、`issues` 不外洩 `type`／`tracker`
      以外欄位）、404／403／500 三種錯誤情境回傳統一錯誤格式
    - 9 examples, 0 failures；全專案回歸 153 examples, 0 failures（實際透過 Rails router／
      middleware stack 發出請求驗證，非僅單元測試）

- [x] 9. Dashboard 頁面
  - [x] 9.1 新增路由 `GET /issues`、`IssuesController#index`
    - 月份／專案／狀態篩選邏輯於 Controller 層完成；比照既有 `DashboardController` 的
      `build_success`／`build_failure` 模式（HTTP 一律 200，失敗時 `@error` 於頁面內顯示，不同於
      JSON API 走 HTTP 狀態碼分流）
    - _需求：7.1, 8.1, 8.2, 9.1_

  - [x] 9.2 新增 `app/helpers/issues_helper.rb`：`attribution_label(type)` / `attribution_class(type)`
        / `trend_chart_points` / `trend_chart_polyline`
    - `attribution_label`／`attribution_class` 邏輯與 prototype 的 `attributionLabel`／
      `attributionClass` 一致；`trend_chart_points`／`trend_chart_polyline` 為 9.6 的座標計算輔助
    - _需求：5.6_

  - [x] 9.3 新增 `app/views/issues/index.html.erb`（頁面骨架，3 個區塊）
    - 對齊 `docs/issues.html` prototype 版面（月度 KPI＋依專案分類統計／每日趨勢／議題明細）；單一
      `turbo_frame_tag "issue-content"` 包住全部動態內容，比照既有 `dashboard/index.html.erb` 的
      單一 frame 模式（非 design.md 原草案設想的多個獨立 frame——既有慣例已證明單一 frame 搭配
      「套用篩選」按鈕即可達成局部更新，不需為此新增複雜度）
    - _需求：7.2_

  - [x] 9.4 新增 `app/views/issues/_issue_list.html.erb`
    - 專案／狀態篩選變更時隨表單送出局部更新（單一 frame 內），不觸發整頁重載；無符合條件時顯示
      提示文字；欄位依序為議題編號／專案／主旨／歸屬類型／狀態／負責人／開始日期／到期日期／
      工作天數（不含 type／tracker）；「歸屬類型」欄位以 `IssuesHelper#attribution_label`／
      `#attribution_class` 渲染徽章；「議題編號」渲染為連結至
      `https://redmine.amastek.com.tw/issues/{issue_id}`（新分頁開啟）；`Controller#index` 未帶
      `status` 參數時預設篩選為「新建立」（`params.key?(:status) ? params[:status] : "新建立"`），
      非全部狀態，與 prototype 一致
    - _需求：5.6, 5.7, 5.8, 8.2, 8.3, 8.4_

  - [x] 9.5 KPI 卡片區塊
    - 月份切換時（表單送出）更新 KPI 卡片；依專案分類統計（`project_breakdown`）恆為全部議題的
      分組統計，不受 `month` 篩選影響，天然滿足「不隨月份切換更新」
    - _需求：3a.2, 9.2_

  - [x] 9.6 每日趨勢圖：新增 `app/views/issues/_trend_chart.html.erb`，伺服器端 ERB 產生 SVG
    - 邏輯移植自 `docs/js/issues.js` 的 `renderTrendChart`（X/Y 軸等比例縮放邏輯相同，由
      `IssuesHelper#trend_chart_points` 計算座標）；空清單、單筆資料、全零總計三種邊界情況皆已
      測試（避免除以零）
    - _需求：7.2_

  - [x] 9.7 依專案分類統計表：新增 `app/views/issues/_project_breakdown.html.erb`，`<table>` 渲染
        `@project_breakdown`
    - 取代 prototype 已移除的 Top3 排行
    - _需求：3a.1, 7.2_

  - [x] 9.8 樣式：`.issue-id-link`／`.attribution-badge`（`-shared`／`-individual`／`-other`）／
        `.trend-chart-wrap`／`.trend-svg`／`.trend-line`／`.trend-point`／`.issue-section`
    - 沿用既有 `application.css` 主題變數（`--color-accent`／`--overdue-bg`／`--badge-*` 等），
      深色／淺色主題皆正確呈現，無需另寫斷點（表格響應式已由既有 `.project-tasks` 規則涵蓋）
    - _需求：5.8_

  - [x] 9.9 測試：`spec/helpers/issues_helper_spec.rb`（12 examples）、
        `spec/requests/issues_spec.rb`（16 examples，對應原 Task 12）
    - Request spec 涵蓋：預設篩選（月份最新、狀態「新建立」）、月份／專案／狀態切換、清空狀態篩選、
      無符合結果時的提示文字、`project_breakdown` 不受月份篩選影響、Redmine 連結正確性、404 錯誤時
      頁面內顯示錯誤訊息而非拋出例外
    - 全專案回歸 181 examples, 0 failures

  - [x] 9.10 每日趨勢圖新增橫軸日期標籤／縱軸數值刻度（Prototype 確認畫面後追加需求，見需求 3.4、3.5）
    - `docs/js/issues.js`：`renderTrendChart` 改用 `TREND_PADDING_LEFT/RIGHT/TOP/BOTTOM` 分向留白，
      新增 `pickLabelIndices`（等距挑選含首尾的橫軸標籤索引，資料點超過 `TREND_MAX_X_LABELS`＝6 時
      自動精簡）、`shortDate`（`YYYY-MM-DD`→`MM/DD`）；繪製 3 條縱軸格線＋數字標籤
    - `docs/css/style.css`：新增 `.trend-gridline`／`.trend-axis-label`
    - Rails `IssuesHelper`：新增 `trend_chart_y_ticks`／`trend_chart_x_labels`，邏輯與 JS 版本
      完全一致；`_trend_chart.html.erb` 對應渲染格線與標籤；`application.css` 同步新增相同樣式
    - 兩端座標計算邏輯保持一致，避免 prototype 與正式頁面呈現不同步
    - 檢查點：`docs/js/issues.js` 以 Playwright 驗證 6/6 通過（3 條縱軸格線、橫軸標籤含首尾且超過
      6 個資料點時自動精簡）；Rails `issues_helper_spec.rb` 擴充至 19 examples；全專案回歸
      196 examples, 0 failures；並以 `ActionDispatch::Integration::Session` 直接檢視渲染出的
      `<svg>`，確認格線／標籤／折線座標互相對應無誤
    - _需求：3.4, 3.5_

  - [x] 9.11 月度 KPI 區塊新增說明文字，釐清「月結」與「即時資料」的關係（見需求 9.3、9.4）
    - 起因：使用者反映「當月仍有議題要顯示，但統計資料是月底結算」，容易誤解為「當月無資料」
    - `app/views/issues/index.html.erb`：於「月度 KPI」`<h2>` 下新增
      `<p class="section-note">月結數字，當月進行中尚未結算；下方依專案分類統計與議題明細皆為即時
      資料，不受此處月份選擇影響</p>`；`application.css` 新增 `.section-note`
    - 說明文字僅置於月度 KPI 區塊一處，不重複放在議題明細的專案／狀態篩選控制項附近——初版曾一併在
      議題明細篩選列旁加註，使用者指出容易讓人誤以為專案／狀態篩選未生效（實際上這兩個篩選確實會
      影響下方議題明細清單，僅「月份」不影響），故收斂為單一位置，與 prototype 的修正同步
    - 測試：`issues_spec.rb` 新增 2 examples（`.section-note` 恰好出現一次、文字含「月結」與
      「即時」關鍵字），全專案回歸 198 examples, 0 failures
    - 文字內容後於 Task 9.12（分頁籤）再次調整，見下
    - _需求：9.3, 9.4_

  - [x] 9.12 改為分頁籤呈現：統計摘要（月度 KPI＋每日趨勢） / 議題資料（依專案分類＋議題明細）
        （見需求 7a，對齊 prototype 需求 5）
    - 起因：使用者反映頁首單一篩選列同時放月份／專案／狀態三個選單，容易誤以為月份篩選會影響
      下方所有區塊；改為分頁籤後，篩選控制項各自歸屬到其實際影響的分頁籤內
    - `IssuesController`：新增 `TABS`／`DEFAULT_TAB` 常數與 `@active_tab`（讀取 `params[:tab]`，
      無效值 fallback 為 `"stats"`）
    - `app/views/issues/index.html.erb`：改用純 CSS radio+label 分頁籤結構；月份篩選表單移入
      「統計摘要」分頁籤（隱藏欄位 `tab=stats`）；專案／狀態篩選表單移入「議題資料」分頁籤（隱藏
      欄位 `tab=detail`）；「依專案分類」區塊隨之移至「議題資料」分頁籤；`section-note` 文字改為
      「「議題資料」分頁的依專案分類統計與議題明細皆為即時資料」，反映內容已移至不同分頁籤
    - `application.css`：新增 `.tab-radio`／`.tab-buttons`／`.tab-button`／`.tab-panel`（沿用
      prototype 相同的 CSS 選擇器邏輯）
    - 測試：`issues_spec.rb` 新增 5 examples（預設顯示統計摘要分頁籤、四區塊正確分組、月份表單
      送出後停留在統計摘要分頁籤、專案/狀態表單送出後停留在議題資料分頁籤、無效 tab 參數 fallback）
    - 全專案回歸 208 examples, 0 failures
    - _需求：7a.1, 7a.2, 7a.3, 7a.4_

- [x] 10. Rails 入口頁（對齊 docs/index.html 模式）
  - [x] 10.1 新增 `app/controllers/home_controller.rb`（`GET /`，純靜態，不讀取任何資料來源）
    - `index` 為空動作，不呼叫 `SheetsApiClient`／`IssueSheetsClient`
    - _需求：10.1, 10.3_

  - [x] 10.2 修改 `config/routes.rb`：`root "home#index"` 取代原本 `root "dashboard#index"`；
        `get "/dashboard", to: "dashboard#index"` 維持不變，305 頁面仍可直接訪問
    - _需求：10.1_

  - [x] 10.3 新增 `app/views/home/index.html.erb`：兩張卡片連結（「305 專案進度」→`/dashboard`、
        「306 臭蟲議題」→`/issues`），比照 `docs/index.html` 的 `.entry-grid`／`.entry-card` 結構；
        新增 `.entry-grid`／`.entry-card`／`.back-link` 樣式至 `application.css`
    - 額外於 `/dashboard`、`/issues` 頁首加上「← 返回入口頁」連結（回到 `/`），對齊 `docs/` 靜態站
      每個子頁面皆有返回入口頁連結的既有體驗（超出原始任務描述，但屬同一需求 10 的自然延伸）
    - _需求：10.2, 10.4_

  - [x] 10.4 檢查點 — 入口頁驗證
      - 新增 `spec/requests/home_spec.rb`（8 examples）：`GET /` 回傳 200、不呼叫任何 SheetsClient
        （需求 10.3）、正確連結至 `/dashboard`／`/issues`、theme-toggle 按鈕存在；`GET /dashboard`
        與 `GET /issues` 皆能正常直接訪問並各自渲染「返回入口頁」連結
      - 全專案回歸 196 examples, 0 failures（含本次新增）

- [x] 11. 檢查點 — 頁面功能驗證（改以 Playwright E2E 取代原規劃的瀏覽器手動驗證，見
      design.md「測試策略」段落的設計變更紀錄）
    - 起因：本機開發環境已在 `config/credentials/development.yml.enc` 設定真實 Service Account
      憑證，`rails server` 可直接以真實試算表資料運作；改用 Playwright 驅動實際運行中的伺服器
      （斷言針對真實資料的結構性質，不寫死具體筆數／專案名稱），比純手動點擊更可重複執行、更不
      容易遺漏
    - 驗證項目：首次載入時狀態篩選預設為「新建立」、專案篩選預設為全部專案；Turbo Frame 局部更新
      （監聽 `framenavigated` 確認主畫面未整頁重載）；月份切換正確套用；清空狀態篩選後議題筆數
      增加；依專案篩選正確縮小結果；某專案＋狀態組合命中空結果時顯示「目前無符合條件的議題」；
      議題編號連結正確導向 Redmine（`target="_blank"`、`rel="noopener noreferrer"`）；響應式版面
      （480px 寬度下議題表格橫向捲動，Rails 版與 prototype 的堆疊卡片版面為刻意不同的響應式設計
      選擇）
    - 17/17（`e2e_rails_task11.js`）通過，無 console error
    - _需求：7a.4, 8.1〜8.4, 9.1〜9.2_

- [x] 12. Request spec：`spec/requests/issues_spec.rb`
    - 已於 Task 9.9 一併完成（實作與測試同步進行，避免無測試覆蓋的中間狀態）；16 examples, 0 failures
    - _需求：8.1〜8.4, 9.1〜9.2_

- [x] 13. 端對端驗證（Playwright E2E，見 Task 11 的設計變更紀錄）
    - 訪問真實運行中的 `/issues` 與 `/api/issue_dashboard`：確認 API 回傳真實試算表資料（`issues`
      412 筆，非模擬資料的個位數筆數）；確認 `tracker=測試` 的議題已被排除（`issues` 輸出的
      `tracker` 值僅有「臭蟲」）；確認頁面預設選中的月份與 `month_kpi` 最新 `year_month` 一致；
      確認 KPI 卡片的攔截率數值與 API 回傳值一致；確認清空篩選後 HTML 頁面議題筆數與 API `issues`
      筆數一致（HTML 與 JSON 兩種呈現方式資料一致）
    - 6/6（`e2e_rails_task13.js`）通過
    - _需求：7.1〜7.4 全部_

- [x] 14. 每日趨勢與依專案分類改為依所選月份篩選；依專案分類移回統計摘要分頁籤；橫軸標籤改為全部
      顯示並旋轉（將 `docs/js/issues.js` prototype 側的同名變更移植到 Rails，見需求 3a.4、4.5、4.6、
      7a.1 的設計變更紀錄）
  - [x] 14.1 `IssuesController#build_success` 改為對月份篩選過的議題子集重新計算 `@project_breakdown`
        （新增 `compute_project_breakdown` private method），`@daily_kpi` 改為對 `all_daily_kpi`
        依 `date` 欄位篩選所選月份
    - Actor（`Sheets::FetchIssueDashboard`）與 `GET /api/issue_dashboard` JSON 端點行為不變，僅
      HTML 頁面（`GET /issues`）的月份篩選邏輯變更
    - `_project_breakdown.html.erb`／`_trend_chart.html.erb` 空狀態文字改為「所選月份無議題資料」／
      「所選月份無每日趨勢資料」
    - _需求：3a.4, 4.5_

  - [x] 14.2 「依專案分類」`<section>` 由 `tab-panel-detail` 移至 `tab-panel-stats`（原 Task 9 置於
        議題資料分頁籤，此次反轉該決策）；`.section-note` 文字同步更新為「月度 KPI 為月結數字，
        當月進行中尚未結算；每日趨勢與依專案分類統計則依此處所選月份即時呈現；「議題資料」分頁的
        議題明細不受月份篩選影響（顯示全部議題）」
    - _需求：7a.1, 9.3_

  - [x] 14.3 `IssuesHelper`：移除 `TREND_MAX_X_LABELS` 常數與 `trend_chart_label_indices`，
        `trend_chart_x_labels` 改為回傳全部資料點（不再抽樣）；`TREND_HEIGHT` 220→250、
        `TREND_PADDING_BOTTOM` 28→55；`_trend_chart.html.erb` 的橫軸 `<text>` 加上
        `transform="rotate(-45 x y)"` + `text-anchor="end"`
    - `spec/helpers/issues_helper_spec.rb` 同步更新：移除「超過上限時抽樣」的測試案例，改為驗證
      「資料點數量不設上限、皆一一對應輸出標籤」
    - _需求：4.6_

  - [x] 14.4 檢查點 — RSpec 驗證
    - `spec/requests/issues_spec.rb` 新增／改寫斷言：預設月份（2026-08）依專案分類僅顯示當月
      `start_date` 符合的議題；切換月份後依專案分類與趨勢圖點數同步改變；無符合議題的月份顯示
      空狀態；新增 `project_breakdown_section` test helper 避免誤判專案下拉選單／議題明細的
      同名文字
    - 30/30（`issues_spec.rb`）通過；全專案回歸 210/210 通過

- [x] 15. 排除 tracker=測試 議題；依專案分類統計表新增排序功能（見需求 3a.5、5a）
  - [x] 15.1 `Sheets::FetchIssueDashboard#parse_issues` 新增 `next if tracker.to_s.strip == "測試"`
    - 起因：使用者反映「如果 tracker 是測試的不列入品質裡面，那個是測試議題」；確認排除範圍為
      整個頁面（議題明細清單＋依專案分類統計），故於 Actor 解析階段排除，`issues`／
      `project_breakdown` 輸出與 `GET /api/issue_dashboard`／`GET /issues` 皆不會看到
    - `spec/actors/sheets/fetch_issue_dashboard_spec.rb` 新增測試：tracker=測試 的列被跳過，其餘
      正常列不受影響
    - _需求：5a_

  - [x] 15.2 `IssuesController` 新增 `BREAKDOWN_SORT_KEYS`／`BREAKDOWN_SORT_DIRS` 常數 +
        `breakdown_sort`／`breakdown_dir` query params 解析 + `sort_project_breakdown` private
        method；`IssuesHelper#breakdown_sort_link(key, label)` 產生可點擊的排序標題連結
    - 起因：使用者詢問「依專案分類 能有排序嗎？例如可以依照客訴數量 測試數量 總數量」
    - 連結保留目前所選 `month`、固定 `tab: "stats"`；同欄位再次點擊反轉方向，切換不同欄位預設
      `desc`；非法 `breakdown_sort` 值忽略，維持原始順序；`_project_breakdown.html.erb` 四個數值
      欄位標題改用 `breakdown_sort_link`
    - 新增 `.sort-button` CSS（`application.css`），與 `docs/css/style.css` 的樣式意圖一致
      （無底線、hover/`:focus-visible` 呈現 accent 色）
    - _需求：3a.5_

  - [x] 15.3 檢查點 — RSpec 驗證
    - `spec/requests/issues_spec.rb` 新增 fixture：一筆 tracker=測試 的議題列（驗證排除）、一筆
      不同專案的 8 月議題列（提供多列資料以驗證排序有意義）；新增 `describe` 區塊驗證：預設降冪、
      同欄位切換反轉為升冪、▲／▼ 指示正確、非法 `breakdown_sort` 值忽略、排序連結保留 `month`
      參數
    - 37/37（`issues_spec.rb`）通過；全專案回歸 218/218 通過

---

## Notes

- 305 與 306 兩條資料流刻意平行、不共用 Client／Actor／Blueprint／Controller，降低耦合（見
  design.md「元件與介面」段落的抽象化取捨說明）
- 每項任務參照對應需求編號以利追溯
- 依 karpathy-guidelines：每項工作開始前先確認可驗證標準，完成後才勾選
- Task 1（分頁名稱確認）為阻塞性前置任務，Task 2 之後任何涉及分頁名稱的實作都依賴其結果
- 工程師負載表／專案清單表經評估後不納入本 spec 範圍，故無對應 Client／Actor 輸出／Blueprint／
  View 區塊（對照 draft 版本已移除相關任務）

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["2.1"] },
    { "id": 2, "tasks": ["2.2", "3.1", "3.2", "3.3", "4.1"] },
    { "id": 3, "tasks": ["4.2", "5.1"] },
    { "id": 4, "tasks": ["4.3", "5.2"] },
    { "id": 5, "tasks": ["6"] },
    { "id": 6, "tasks": ["7.1"] },
    { "id": 7, "tasks": ["8.1"] },
    { "id": 8, "tasks": ["8.2", "9.1"] },
    { "id": 9, "tasks": ["9.2", "9.3"] },
    { "id": 10, "tasks": ["9.4", "9.5", "9.6", "9.7"] },
    { "id": 11, "tasks": ["9.8", "9.9", "9.10", "9.11", "9.12"] },
    { "id": 12, "tasks": ["10.1"] },
    { "id": 13, "tasks": ["10.2"] },
    { "id": 14, "tasks": ["10.3"] },
    { "id": 15, "tasks": ["10.4"] },
    { "id": 16, "tasks": ["11"] },
    { "id": 17, "tasks": ["12"] },
    { "id": 18, "tasks": ["13"] }
  ]
}
```
