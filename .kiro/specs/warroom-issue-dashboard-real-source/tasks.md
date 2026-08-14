# Implementation Plan: 306 臭蟲議題真實資料串接

## Overview

把 306 臭蟲議題資料從 `docs/issues.html` prototype 的模擬資料，串接為真實 Google Sheets
（`306_臭蟲議題紀錄`）資料，實作於 `warroom-data-api-prototype` Rails 專案，遵循
[rails-standards.md](../../steering/rails-standards.md) 分層。與既有 305 資料流平行存在，不修改
305 的任何檔案。

---

## Tasks

- [ ] 1. 確認真實分頁名稱
  - [ ] 1.1 透過 Google Sheets API 或人工開啟試算表，列出 `1RdU2p9b7fwNgO5e59jN-00a5KLOQ91xrFhj2NenyKTc`
        完整分頁名稱清單
    - 確認 `raw_2023`〜`raw_2026`、工程師負載表、專案清單表的實際分頁名稱；若與 design.md 推測不同，
      更新 design.md 的 `IssueSheetsClient` 常數
    - _需求：1.1, 1.2_

- [ ] 2. `IssueSheetsClient`
  - [ ] 2.1 新增 `app/clients/issue_sheets_client.rb`
    - 依 [design.md](design.md) 實作 `fetch_month_kpi_rows`／`fetch_daily_kpi_rows`／
      `fetch_issue_rows`／`fetch_engineer_load_rows`／`fetch_project_list_rows`
    - 沿用既有 `SheetsApiClient` 的憑證讀取、UTF-8 重標記邏輯
    - _需求：2.1, 2.2_

  - [ ] 2.2 單元測試：`spec/clients/issue_sheets_client_spec.rb`
    - stub `SheetsService`，驗證分頁名稱／range／合併邏輯（`raw_2023`〜`raw_2026` 僅保留第一個標題列）
    - _需求：3.1, 4.1, 5.1, 6.1_

- [ ] 3. `Sheets::FetchIssueDashboard` — 月度 KPI／每日趨勢解析
  - [ ] 3.1 新增 `app/actors/sheets/fetch_issue_dashboard.rb`，實作 `parse_month_kpi`
    - 不解析 `Top3` 欄位，不納入輸出（負責人不作為統計主軸，見需求 3.3）
    - _需求：3.2, 3.3_

  - [ ] 3.2 實作 `parse_daily_kpi`
    - 空字串 `total` 視為 0；結果依 `date` 升冪排序
    - _需求：4.2, 4.3, 4.4_

- [ ] 4. `Sheets::FetchIssueDashboard` — 議題明細解析與依專案分類統計
  - [ ] 4.1 實作 `parse_issues`
    - 欄位對應、日期正規化（沿用既有 `normalize_date`）、`work_days` 整數轉換容錯、必要欄位空白列跳過
    - _需求：5.2, 5.3, 5.4, 5.5_

  - [ ] 4.2 實作 `compute_project_breakdown(issues)`
    - 依 `project` 分組統計 `complaint`／`testing`／`other` 筆數與 `total`，純記憶體運算（不重複呼叫
      `IssueSheetsClient`），邏輯與 prototype 的 `computeProjectBreakdown` 一致
    - _需求：3a.1, 3a.2_

- [ ] 5. `Sheets::FetchIssueDashboard` — 工程師負載／專案清單解析
  - [ ] 5.1 實作 `parse_engineer_load`／`parse_project_list`
    - 跳過空白分隔欄／全空白列
    - _需求：6.2, 6.3, 6.4_

- [ ] 6. `Sheets::FetchIssueDashboard` — 錯誤處理
  - [ ] 6.1 實作統一錯誤對應（404/403/內部錯誤），任一資料類別失敗即整體失敗
    - 沿用 [rails-standards.md](../../steering/rails-standards.md) 的 `failure_code` 對應表
    - _需求：7.1, 7.2_

  - [ ] 6.2 單元測試：`spec/actors/sheets/fetch_issue_dashboard_spec.rb`
    - 涵蓋五類讀取資料解析、`project_breakdown` 分組統計、錯誤對應、邊界情況（空列、格式不符）
    - _需求：3〜7 全部驗收標準_

- [ ] 7. 檢查點 — Actor 層驗證
    - 於 Rails console 手動呼叫 `Sheets::FetchIssueDashboard.result`（可先搭配假憑證或
      mock client 驗證流程），確認六個 output 欄位（含 `project_breakdown`）結構符合 design.md 的
      Data Models

- [ ] 8. Blueprints
  - [ ] 8.1 新增 `MonthKpiBlueprint`／`DailyKpiBlueprint`／`IssueBlueprint`／
        `ProjectBreakdownBlueprint`／`EngineerLoadBlueprint`／`ProjectListBlueprint`
    - _需求：8.4_

- [ ] 9. API Endpoint
  - [ ] 9.1 新增路由 `GET /api/issue_dashboard`、`Api::IssueDashboardController`
    - 回傳 `{ month_kpi, daily_kpi, issues, project_breakdown, engineer_load, project_list }`，
      透過 Blueprint 序列化
    - _需求：8.1, 8.3, 8.4_

  - [ ] 9.2 Request spec：`spec/requests/api/issue_dashboard_spec.rb`
    - 驗證成功／各類錯誤情境回傳格式
    - _需求：8.3, 7.1_

- [ ] 10. Dashboard 頁面
  - [ ] 10.1 新增路由 `GET /issues`、`IssuesController#index`
    - 月份／專案／狀態篩選邏輯於 Controller 層完成
    - _需求：8.1, 9.1, 9.2, 10.1_

  - [ ] 10.2 新增 `app/views/issues/index.html.erb`（頁面骨架，5 個區塊）
    - 對齊 `docs/issues.html` prototype 版面
    - _需求：8.2_

  - [ ] 10.3 新增 `app/views/issues/_issue_list.html.erb`（Turbo Frame 局部）
    - 專案／狀態篩選變更時局部更新，不觸發整頁重載；無符合條件時顯示提示文字；「歸屬類型」欄位以
      `IssuesHelper#attribution_label`／`#attribution_class` 渲染徽章
    - _需求：5.6, 9.3, 9.4_

  - [ ] 10.4 KPI 卡片區塊 Turbo Frame 局部更新
    - 月份切換時局部更新 KPI 卡片；依專案分類統計（`project_breakdown`）不隨月份切換更新
    - _需求：3a.2, 10.2_

  - [ ] 10.5 每日趨勢圖：伺服器端 ERB 產生 SVG
    - 邏輯移植自 `docs/js/issues.js` 的 `renderTrendChart`（X/Y 軸等比例縮放邏輯相同）
    - _需求：8.2_

  - [ ] 10.6 依專案分類統計表：`<table>` 渲染 `@project_breakdown`
    - 取代 prototype 已移除的 Top3 排行
    - _需求：3a.1, 8.2_

- [ ] 11. 檢查點 — 頁面功能驗證
    - 瀏覽器手動驗證：月份切換、專案／狀態篩選、Turbo Frame 局部更新（不整頁重載）、空結果提示、
      響應式版面（沿用既有 CSS 斷點）

- [ ] 12. Request spec：`spec/requests/issues_spec.rb`
    - 驗證 `GET /issues` 帶各種 query params 組合的回應內容
    - _需求：9.1〜9.4, 10.1〜10.2_

- [ ] 13. 端對端驗證
    - 設定真實 Service Account 憑證，訪問 `/issues` 與 `/api/issue_dashboard`，確認回傳真實試算表
      資料且與 prototype 呈現方式一致（比照 `warroom-data-api-real-source` Task 10 驗證方式）
    - _需求：8.1〜8.4 全部_

---

## Notes

- 305 與 306 兩條資料流刻意平行、不共用 Client／Actor／Blueprint／Controller，降低耦合（見
  design.md「Components and Interfaces」段落的抽象化取捨說明）
- 每項任務參照對應需求編號以利追溯
- 依 karpathy-guidelines：每項工作開始前先確認可驗證標準，完成後才勾選
- Task 1（分頁名稱確認）為阻塞性前置任務，Task 2 之後任何涉及分頁名稱的實作都依賴其結果

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["2.1"] },
    { "id": 2, "tasks": ["2.2", "3.1", "3.2", "4.1", "5.1"] },
    { "id": 3, "tasks": ["4.2", "6.1"] },
    { "id": 4, "tasks": ["6.2"] },
    { "id": 5, "tasks": ["7"] },
    { "id": 6, "tasks": ["8.1"] },
    { "id": 7, "tasks": ["9.1"] },
    { "id": 8, "tasks": ["9.2", "10.1"] },
    { "id": 9, "tasks": ["10.2"] },
    { "id": 10, "tasks": ["10.3", "10.4", "10.5", "10.6"] },
    { "id": 11, "tasks": ["11"] },
    { "id": 12, "tasks": ["12"] },
    { "id": 13, "tasks": ["13"] }
  ]
}
```
