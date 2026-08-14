# Implementation Plan: 306 臭蟲議題真實資料串接

## Overview

把 306 臭蟲議題資料從 `docs/issues.html` prototype 的模擬資料，串接為真實 Google Sheets
（`306_臭蟲議題紀錄`）資料，實作於 `warroom-data-api-prototype` Rails 專案，遵循
[rails-standards.md](../../steering/rails-standards.md) 分層。與既有 305 資料流平行存在，不修改
305 的任何檔案。範圍涵蓋月度 KPI、每日趨勢、議題明細（含依專案分類統計、歸屬類型標示、Redmine 連結）；
工程師負載表／專案清單表經評估後不納入範圍。

---

## Tasks

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
      design.md「Components and Interfaces」段落的抽象化取捨說明）
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

- [ ] 4. `Sheets::FetchIssueDashboard` — 議題明細解析與依專案分類統計
  - [ ] 4.1 實作 `parse_issues`
    - 欄位對應（issue_id/subject/type/tracker/status/assigned_to/start_date/due_date/work_days/
      project）、日期正規化（沿用既有 `normalize_date`）、`work_days` 整數轉換容錯、必要欄位空白列跳過
    - _需求：5.2, 5.3, 5.4, 5.5_

  - [ ] 4.2 實作 `compute_project_breakdown(issues)`
    - 依 `project` 分組統計 `complaint`／`testing`／`other` 筆數與 `total`，純記憶體運算（不重複呼叫
      `IssueSheetsClient`），邏輯與 prototype 的 `computeProjectBreakdown` 一致
    - _需求：3a.1, 3a.2_

- [ ] 5. `Sheets::FetchIssueDashboard` — 錯誤處理
  - [ ] 5.1 實作統一錯誤對應（404/403/內部錯誤），任一資料類別失敗即整體失敗
    - 沿用 [rails-standards.md](../../steering/rails-standards.md) 的 `failure_code` 對應表
    - _需求：6.1, 6.2_

  - [ ] 5.2 單元測試：`spec/actors/sheets/fetch_issue_dashboard_spec.rb`
    - 涵蓋三類讀取資料解析、`project_breakdown` 分組統計、錯誤對應、邊界情況（空列、格式不符）
    - _需求：3〜6 全部驗收標準_

- [ ] 6. 檢查點 — Actor 層驗證
    - 於 Rails console 手動呼叫 `Sheets::FetchIssueDashboard.result`（可先搭配假憑證或
      mock client 驗證流程），確認四個 output 欄位（`month_kpi`／`daily_kpi`／`issues`／
      `project_breakdown`）結構符合 design.md 的 Data Models

- [ ] 7. Blueprints
  - [ ] 7.1 新增 `MonthKpiBlueprint`／`DailyKpiBlueprint`／`IssueBlueprint`／`ProjectBreakdownBlueprint`
    - _需求：7.4_

- [ ] 8. API Endpoint
  - [ ] 8.1 新增路由 `GET /api/issue_dashboard`、`Api::IssueDashboardController`
    - 回傳 `{ month_kpi, daily_kpi, issues, project_breakdown }`，透過 Blueprint 序列化
    - _需求：7.1, 7.3, 7.4_

  - [ ] 8.2 Request spec：`spec/requests/api/issue_dashboard_spec.rb`
    - 驗證成功／各類錯誤情境回傳格式
    - _需求：7.3, 6.1_

- [ ] 9. Dashboard 頁面
  - [ ] 9.1 新增路由 `GET /issues`、`IssuesController#index`
    - 月份／專案／狀態篩選邏輯於 Controller 層完成
    - _需求：7.1, 8.1, 8.2, 9.1_

  - [ ] 9.2 新增 `app/helpers/issues_helper.rb`：`attribution_label(type)` / `attribution_class(type)`
    - 邏輯與 prototype 的 `attributionLabel`／`attributionClass` 一致
    - _需求：5.6_

  - [ ] 9.3 新增 `app/views/issues/index.html.erb`（頁面骨架，3 個區塊）
    - 對齊 `docs/issues.html` prototype 版面（月度 KPI＋依專案分類統計／每日趨勢／議題明細）
    - _需求：7.2_

  - [ ] 9.4 新增 `app/views/issues/_issue_list.html.erb`（Turbo Frame 局部）
    - 專案／狀態篩選變更時局部更新，不觸發整頁重載；無符合條件時顯示提示文字；欄位依序為議題編號／
      專案／主旨／歸屬類型／狀態／負責人／開始日期／到期日期／工作天數（不含 type／tracker）；
      「歸屬類型」欄位以 `IssuesHelper#attribution_label`／`#attribution_class` 渲染徽章；「議題編號」
      渲染為連結至 `https://redmine.amastek.com.tw/issues/{issue_id}`（新分頁開啟）；`Controller#index`
      未帶 `status` 參數時預設篩選為「新建立」（`params.key?(:status) ? params[:status] : "新建立"`），
      非全部狀態，與 prototype 一致
    - _需求：5.6, 5.7, 5.8, 8.2, 8.3, 8.4_

  - [ ] 9.5 KPI 卡片區塊 Turbo Frame 局部更新
    - 月份切換時局部更新 KPI 卡片；依專案分類統計（`project_breakdown`）不隨月份切換更新
    - _需求：3a.2, 9.2_

  - [ ] 9.6 每日趨勢圖：伺服器端 ERB 產生 SVG
    - 邏輯移植自 `docs/js/issues.js` 的 `renderTrendChart`（X/Y 軸等比例縮放邏輯相同）
    - _需求：7.2_

  - [ ] 9.7 依專案分類統計表：`<table>` 渲染 `@project_breakdown`
    - 取代 prototype 已移除的 Top3 排行
    - _需求：3a.1, 7.2_

  - [ ] 9.8 樣式：`.issue-id-link`（沿用 prototype 的 CSS class，無底線、hover/focus 才顯示底線）
    - _需求：5.8_

- [ ] 10. 檢查點 — 頁面功能驗證
    - 瀏覽器手動驗證：首次載入時狀態篩選預設為「新建立」（非全部狀態）、專案篩選預設為全部專案、
      月份切換、專案／狀態篩選、Turbo Frame 局部更新（不整頁重載）、空結果提示、議題編號連結正確
      導向 Redmine 且新分頁開啟、響應式版面（沿用既有 CSS 斷點）

- [ ] 11. Request spec：`spec/requests/issues_spec.rb`
    - 驗證 `GET /issues` 帶各種 query params 組合的回應內容
    - _需求：8.1〜8.4, 9.1〜9.2_

- [ ] 12. 端對端驗證
    - 設定真實 Service Account 憑證，訪問 `/issues` 與 `/api/issue_dashboard`，確認回傳真實試算表
      資料且與 prototype 呈現方式一致（比照 `warroom-data-api-real-source` Task 10 驗證方式）
    - _需求：7.1〜7.4 全部_

---

## Notes

- 305 與 306 兩條資料流刻意平行、不共用 Client／Actor／Blueprint／Controller，降低耦合（見
  design.md「Components and Interfaces」段落的抽象化取捨說明）
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
    { "id": 4, "tasks": ["5.2"] },
    { "id": 5, "tasks": ["6"] },
    { "id": 6, "tasks": ["7.1"] },
    { "id": 7, "tasks": ["8.1"] },
    { "id": 8, "tasks": ["8.2", "9.1"] },
    { "id": 9, "tasks": ["9.2", "9.3"] },
    { "id": 10, "tasks": ["9.4", "9.5", "9.6", "9.7"] },
    { "id": 11, "tasks": ["9.8"] },
    { "id": 12, "tasks": ["10"] },
    { "id": 13, "tasks": ["11"] },
    { "id": 14, "tasks": ["12"] }
  ]
}
```
