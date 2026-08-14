# Implementation Plan: Google Sheets 抓取效能與篩選體驗優化

## Overview

在既有 `warroom-data-api-prototype` 基礎上，降低即時打 Google Sheets API 造成的延遲，並補齊
快取生效後需要的體驗調整。任務 1、2 已於本分支實作完成；任務 3（載入狀態）為下一步優先項目，
任務 4、5 為選用項目，視情況再排入。

每項任務均可獨立開發、驗證並 Commit。

---

## Tasks

- [x] 1. `SheetsApiClient` 加入快取
  - [x] 1.1 `fetch_rows` 包一層 `Rails.cache.fetch`
    - 新增 `CACHE_KEY`（含 `SPREADSHEET_ID`）、`CACHE_EXPIRY`（5 分鐘）常數
    - 原本的 API 呼叫邏輯搬到私有方法 `fetch_rows_from_api`，由 `Rails.cache.fetch` 的區塊呼叫
    - 例外於區塊內拋出時不寫入快取，維持原本的例外傳遞行為
    - _需求：1.1, 1.2, 1.3, 1.4, 1.5_

- [x] 2. Dashboard 篩選改為 Turbo Frame 局部更新
  - [x] 2.1 篩選表單改為只更新 `project-content` frame
    - `index.html.erb` 的 `form_with` 移除 `local: true`，加上
      `data: { turbo_frame: "project-content" }`
    - Controller／routes／Actor 不需變動（底層仍是一般 GET request）
    - _需求：2.1, 2.2, 2.3_

- [x] 3. 篩選送出時的載入狀態回饋（優先）
  - [x] 3.1 CSS：`project-content` frame 的 busy 狀態樣式
    - 使用 Turbo 內建的 `turbo-frame[busy]` 屬性選擇器，送出期間降低透明度並停用互動
      （`app/assets/stylesheets/application.css`）
    - _需求：3.1_

  - [x] 3.2 送出按鈕停用與文字變化
    - 於 `application.html.erb` 監聽篩選表單（`.project-selector`）的 `turbo:submit-start` /
      `turbo:submit-end`，送出時 disable「套用篩選」按鈕並改為「套用中…」，完成後恢復原文字
    - 未引入額外前端框架，使用既有 layout 中原生 JS 事件監聽（與既有主題切換腳本同一慣例）
    - _需求：3.2, 3.3, 3.4_

  - [x] 3.3 檢查點 — 驗證
    - `bundle exec rspec` 84/84 全數通過
    - 以 `curl` 對執行中的 dev server 確認：頁面 HTML 含 `turbo:submit-start` 監聽與
      `套用中…` 文案；編譯後的 CSS 含 `apply-filters-btn:disabled` 與
      `turbo-frame#project-content[busy]` 樣式
    - 已知限制：本次未透過瀏覽器實機點擊驗證（Chrome 工具連線失敗），行為依據 Turbo 官方
      `turbo:submit-start` / `turbo:submit-end` 事件與 `[busy]` 屬性機制推導，建議下次有瀏覽器
      可用時補做一次手動點擊確認

- [ ] 4. 資料時效提示（選用）
  - [ ] 4.1 `SheetsApiClient` 暴露快取寫入時間
    - `Rails.cache.fetch` 改為額外記錄一個 `#{CACHE_KEY}/fetched_at` 時間戳記（或改存
      `{ rows:, fetched_at: }` 結構），供 Controller 取用
    - _需求：4.3_

  - [ ] 4.2 `DashboardController` 與 View 顯示時效文字
    - `Sheets::FetchProjectProgress` 或 `DashboardController` 取得 `fetched_at`，換算成
      「X 分鐘前」／「剛剛更新」文字，傳入 View
    - `index.html.erb` 於摘要列附近顯示該文字
    - _需求：4.1, 4.2_

  - [ ] 4.3 對應測試更新
    - `spec/clients/sheets_api_client_spec.rb`：驗證快取命中／未命中時 `fetched_at` 行為
    - `spec/requests/dashboard_spec.rb`：驗證頁面包含時效文字
    - _需求：4（測試涵蓋）_

- [ ] 5. 手動重新整理資料（選用，依賴任務 4 的 `fetched_at` 機制較完整，但可獨立實作）
  - [ ] 5.1 `SheetsApiClient` 支援略過快取
    - `fetch_rows` 新增可選參數（例如 `force: false`），為 `true` 時略過
      `Rails.cache.fetch` 直接呼叫 `fetch_rows_from_api` 並覆寫快取
    - _需求：5.2_

  - [ ] 5.2 View／Controller 新增「重新整理資料」按鈕
    - Dashboard 頁面新增按鈕，送出時帶一個參數（例如 `refresh=1`）觸發 `force: true`
    - 沿用需求 3 的載入狀態呈現；失敗時沿用既有錯誤訊息呈現，不清除既有快取內容
    - _需求：5.1, 5.3, 5.4_

  - [ ] 5.3 對應測試更新
    - `spec/clients/sheets_api_client_spec.rb`：`force: true` 略過快取的案例
    - `spec/requests/dashboard_spec.rb`：`refresh=1` 觸發即時讀取的案例
    - _需求：5（測試涵蓋）_

- [ ] 6. 最終檢查點 — 全面驗證
  - `bundle exec rspec` 全數通過
  - 瀏覽器手動驗證：篩選送出網址不變、載入狀態正確顯示、（若做了 4/5）時效提示與手動刷新皆正確

- [x] 7. `IssueSheetsClient` 加入快取
  - [x] 7.1 三個 `fetch_*_rows` 方法各自包一層 `Rails.cache.fetch`
    - `fetch_month_kpi_rows`、`fetch_daily_kpi_rows`、`fetch_issue_rows` 各自獨立快取鍵
      （避免互相覆蓋），TTL 沿用 5 分鐘
    - 例外於區塊內拋出時不寫入快取，維持原本的例外傳遞行為
    - _需求：6.1, 6.2, 6.3_

  - [x] 7.2 對應測試確認
    - `spec/clients/issue_sheets_client_spec.rb` 既有測試（測試環境 `:null_store`，快取實質
      停用）維持全數通過，未為快取本身另外新增案例（比照任務 1 的驗證方式）
    - _需求：6（測試涵蓋）_

- [x] 8. Issues 頁面篩選改為 Turbo Frame 局部更新 + 載入狀態
  - [x] 8.1 兩個篩選表單改為只更新 `issue-content` frame
    - `app/views/issues/index.html.erb` 兩處 `form_with` 皆移除 `local: true`，加上
      `data: { turbo_frame: "issue-content" }`
    - 既有 hidden fields（跨分頁籤保留篩選狀態）不變動
    - _需求：7.1, 7.3_

  - [x] 8.2 載入狀態回饋涵蓋兩個表單
    - `application.html.erb` 的送出監聽邏輯改為 `querySelectorAll(".project-selector")`
      逐一綁定，而非只綁定第一個符合的表單（原本只會抓到 Dashboard 頁面那一個）
    - _需求：7.2_

  - [x] 8.3 檢查點 — 驗證
    - `bundle exec rspec` 224/224 全數通過
    - `curl` 對執行中的 dev server 驗證：無憑證環境下 `/issues` 因 `@error` 分支不渲染表單
      （既有結構，非本次改動造成），故改用 `bin/rails runner` + `ActionDispatch::Integration::Session`
      搭配 stub `IssueSheetsClient` 直接渲染成功路徑，確認兩個 `<form class="project-selector">`
      皆帶 `data-turbo-frame="issue-content"`
    - 未透過瀏覽器實機點擊驗證載入狀態視覺效果（Chrome 工具本次連線失敗），行為依據與任務 3
      相同的 Turbo 事件機制推導

---

## Notes

- 任務 1、2、3、7、8 已在本分支（`claude/warroom-dashboards-fetch-ux`）實作完成；任務 4、5
  （選用）尚未執行
- 任務 4、5 標記為選用，可視時間與優先順序決定是否納入本輪
- 任務 7、8 是把任務 1、2、3 的做法比照套用到 306 議題 Dashboard（`/issues`），詳見
  requirements.md 需求 6、7
- 依 karpathy-guidelines：每項工作開始前先確認可驗證標準，完成後才勾選

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1", "2"] },
    { "id": 1, "tasks": ["3.1", "3.2", "7.1"] },
    { "id": 2, "tasks": ["3.3", "7.2", "8.1"] },
    { "id": 3, "tasks": ["4.1", "8.2"] },
    { "id": 4, "tasks": ["4.2", "8.3"] },
    { "id": 5, "tasks": ["4.3", "5.1"] },
    { "id": 6, "tasks": ["5.2"] },
    { "id": 7, "tasks": ["5.3"] },
    { "id": 8, "tasks": ["6"] }
  ]
}
```
