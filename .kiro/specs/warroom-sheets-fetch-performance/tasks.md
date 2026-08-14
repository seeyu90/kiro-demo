# Implementation Plan: Google Sheets 抓取效能與篩選體驗優化

## Overview

在既有 `warroom-data-api-prototype` 基礎上，降低即時打 Google Sheets API 造成的延遲，並補齊
快取生效後需要的體驗調整。任務 1、2 已於本分支實作完成；任務 3（載入狀態）為下一步優先項目，
任務 4、5 為選用項目，視情況再排入。

每項任務均可獨立開發、驗證並 Commit。

---

## Tasks

- [x] 1. `ProjectProgressSheetsClient` 加入快取
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

- [x] 4. 資料時效提示（選用）
  - [x] 4.1 `ProjectProgressSheetsClient` 暴露快取寫入時間
    - 新增 `FETCHED_AT_CACHE_KEY`，在 `Rails.cache.fetch` 區塊內（即快取實際被寫入的當下）
      額外 `Rails.cache.write` 一份 `Time.current`，與主快取共用 TTL、一起過期
    - 新增 `self.fetched_at`，回傳 `Rails.cache.read(FETCHED_AT_CACHE_KEY)`（尚無快取時為 nil）
    - _需求：4.3_

  - [x] 4.2 `DashboardController` 與 View 顯示時效文字
    - Actor 新增 `output :fetched_at`，`call` 內設為 `ProjectProgressSheetsClient.fetched_at`
    - `DashboardController#freshness_label`：elapsed < 10 秒顯示「資料剛剛更新」，否則顯示
      「資料更新於 X 分鐘前」
    - `index.html.erb` 於摘要列上方顯示 `@freshness_label`（`.freshness-label`）
    - _需求：4.1, 4.2_

  - [x] 4.3 對應測試更新
    - `spec/clients/project_progress_sheets_client_spec.rb`：`.fetched_at` 未快取時為 nil；換成真實
      `MemoryStore` 搭配 `travel_to` 驗證確實記錄抓取時間
    - `spec/requests/dashboard_spec.rb`：`fetched_at` 有值時顯示 `freshness-label`、無值
      （測試環境 `:null_store`）時不顯示
    - _需求：4（測試涵蓋）_

- [x] 5. 手動重新整理資料（選用，依賴任務 4 的 `fetched_at` 機制較完整，但可獨立實作）
  - [x] 5.1 `ProjectProgressSheetsClient` 支援略過快取
    - `fetch_rows` 新增 `force: false` 參數，透傳給 `Rails.cache.fetch(..., force: force)`
      （Rails 內建語意：force 只影響「是否讀取既有快取」，block 拋例外時不寫入，不會清掉舊值）
    - _需求：5.2_

  - [x] 5.2 View／Controller 新增「重新整理資料」按鈕
    - Actor 新增 `input :force, default: false`，`call` 呼叫
      `ProjectProgressSheetsClient.fetch_rows(force: force)`
    - `DashboardController#index`：`Sheets::FetchProjectProgress.result(force: params[:refresh] == "1")`
    - `index.html.erb`：既有篩選表單內新增第二個 `submit_tag "重新整理資料", name: "refresh", value: "1"`
      （沿用同一表單，瀏覽器原生行為只會送出被點擊的那個 submit 按鈕的 name/value，不用開新表單）
    - `application.html.erb` 的載入狀態腳本改為 `turbo:submit-start` 讀取 `event.detail.formSubmission.submitter`，
      只把「實際被點擊」的按鈕文字換成「套用中…」，同表單內其他按鈕僅停用
    - _需求：5.1, 5.3, 5.4_

  - [x] 5.3 對應測試更新
    - `spec/clients/project_progress_sheets_client_spec.rb`：驗證 `force: true` 會透傳給 `Rails.cache.fetch`
    - `spec/actors/sheets/fetch_project_progress_spec.rb`：驗證 `force` input 預設 `false`、
      會透傳給 `ProjectProgressSheetsClient.fetch_rows`；驗證 `fetched_at` output 反映
      `ProjectProgressSheetsClient.fetched_at`
    - `spec/requests/dashboard_spec.rb`：`refresh=1` 觸發 `force: true`、一般請求為
      `force: false`、頁面含「重新整理資料」按鈕
    - _需求：5（測試涵蓋）_

- [x] 6. 最終檢查點 — 全面驗證
  - `bundle exec rspec` 235/235 全數通過
  - 無法解密本機憑證（沙盒環境無 `master.key`），改用 `ActionDispatch::Integration::Session`
    + stub `ProjectProgressSheetsClient` 直接渲染成功路徑，確認：`freshness-label` 依 `fetched_at` 有無
    正確顯示／隱藏、「重新整理資料」按鈕存在且 `value="1"`
  - 已知限制：全程未透過瀏覽器實機點擊驗證（Chrome 工具本次連線失敗），視覺效果（按鈕停用、
    frame 變半透明、文字切換）依據既有已驗證過的 Turbo 事件機制與 CSS 選擇器推導，建議之後有
    瀏覽器可用、且有真實憑證時補做一次端對端手動驗證

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

- 全部任務（1–8）已在本分支（`claude/warroom-dashboards-fetch-ux`）實作完成
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
