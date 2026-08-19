# 設計文件

## 概述

本設計文件與既有 real-source spec 的設計文件性質不同：既有的（例如
`warroom-project-history-real-source`）在規劃階段就已經有可用的 Google Service Account，設計文件
可以直接針對真實試算表結構定案，只在少數細節上「邊做邊修正」。本 spec **目前完全沒有 Notion API
存取權**（見 requirements.md「前置條件」），因此本文件的定位是：

1. 把**不依賴真實 schema** 的架構骨架（憑證模組、通用 HTTP client、錯誤碼對應、純邏輯 Ruby 移植）
   先定案，現在就可以動工。
2. 把「拿到 token 之後，該按什麼順序去確認、實作、驗證」明確排出來（見下方「分階段實作與確認
   順序」），讓後續開發不是一次性補完整份文件，而是每完成一個階段就回來更新對應章節，逐步把 ⚠️
   標記換成確認過的真實內容。
3. 凡是本文件中標記 ⚠️ 的段落，皆為**依 static prototype 假設寫成的佔位設計**，正式實作該段落前
   SHALL 先完成對應階段的真實 API 探索，不得直接套用。

---

## 分階段實作與確認順序（本 spec 的核心工作方法）

| 階段 | 做什麼 | 需要什麼 | 完成後更新／解鎖 |
|---|---|---|---|
| 0 | 取得 Notion Integration token 與 database ID(s) | requirements.md 前置條件清單交給資料庫擁有者 workspace 執行 | 解鎖階段 1 |
| 1 | 呼叫 Notion **Retrieve a data source**（`GET /v1/data_sources/{id}`）取得「階段紀錄」資料庫真實 schema | 階段 0 的 token／database ID | 把下方「資料庫實際欄位」章節的 ⚠️ 換成真實 property 名稱／型別／選項清單；同時確認需求 3 的情境 (a)/(b)/(c) |
| 2 | 呼叫 Notion **Query a data source**（`POST /v1/data_sources/{id}/query`），抓 5〜10 筆真實資料列 | 階段 1 的 schema | 人工核對筆數／內容是否符合截圖印象；記下邊界案例（空值、多選、缺欄位、`類型` 是否真的只有 5 種）餵給 Client parser 的測試 |
| 3 | 實作 `NotionCredentials`＋通用 Notion HTTP client（見下方，不依賴 schema） | 無（可與階段 0〜2 平行進行） | Client 基礎設施就緒 |
| 4 | 依階段 1/2 結果實作 `PhaseRecordsNotionClient`（分頁＋property parser） | 階段 1、2、3 | 可讀出真實 `PHASE_RECORDS` 形狀資料 |
| 5 | 依需求 3 確認結果（見 requirements.md 情境 a/b/c）實作對應 Client，或改接既有 `Sheets::FetchProjectRoster` | 階段 1 | 可讀出真實 `PROJECT_PROFILES` 形狀資料 |
| 6 | 實作 `Notion::FetchPhaseTracking` Actor，彙總階段 4/5 輸出 | 階段 4、5 | Actor 對外輸出穩定的 `PROJECT_PROFILES`／`PHASE_RECORDS` 陣列 |
| 7 | Ruby 版 `compute_row_state`／`diff_days`／甘特圖幾何（純邏輯移植，見下方） | 無（可提前做，static prototype 規則已定案） | 可與階段 6 平行進行 |
| 8 | Controller＋View（篩選／排序／清單／甘特圖，沿用 static prototype 規則） | 階段 6、7 | 頁面可運作 |
| 9 | 錯誤處理與降級（需求 5） | 階段 4〜6 | 單一來源失敗不拖垮整頁 |
| 10 | 真實環境驗證，記錄「真實資料串接時發現的重大修正」（比照既有 real-source spec 慣例） | 階段 8、9 完成 | spec 狀態轉為「已完成」 |

**分階段的意義**：階段 3、7 完全不依賴真實 schema，建議先做（見下方設計），把等待階段 0 的時間拿來
把這兩塊寫好、寫測試；階段 1、2 是唯一真正「卡住」的地方，一旦解鎖，4〜6 可以很快接上已經備好的
3、7、8 骨架。

---

## 架構（可先行部分）

```
warroom-data-api-prototype/
├── app/clients/
│   ├── notion_credentials.rb              ← 新：階段 3
│   ├── notion_api_client.rb               ← 新：階段 3（通用 HTTP client 基底）
│   ├── phase_records_notion_client.rb     ← 新：階段 4（⚠️ 待階段 1/2）
│   └── project_profiles_notion_client.rb  ← 新：階段 5，僅情境(a)成立時需要（⚠️ 待需求 3 確認）
├── app/actors/notion/
│   └── fetch_phase_tracking.rb            ← 新：階段 6
├── app/helpers/
│   └── project_phase_tracking_helper.rb   ← 新：階段 7（甘特圖 SVG 幾何，比照既有
│                                              project_history_helper.rb 的角色）
├── app/blueprints/
│   ├── project_profile_blueprint.rb       ← 新：階段 6
│   └── phase_record_blueprint.rb          ← 新：階段 6
├── app/controllers/
│   └── project_phase_tracking_controller.rb ← 新：階段 8
├── app/views/project_phase_tracking/
│   └── index.html.erb（＋ partials）        ← 新：階段 8
└── config/routes.rb                        ← 新增 `get "/project_phase_tracking", to: "project_phase_tracking#index"`
```

不修改任何既有 305/306/307／`project_history` 檔案（同既有慣例）。

---

## `NotionCredentials`（階段 3，可先行定案）

比照既有 `GoogleSheetsCredentials`：

```ruby
# app/clients/notion_credentials.rb
module NotionCredentials
  private

  def notion_token
    token = rails_credentials_token || env_credentials_token
    raise "找不到 Notion Integration Token，請設定 Rails credentials 或環境變數 NOTION_INTEGRATION_TOKEN" if token.nil?
    token
  end

  def rails_credentials_token
    raw = Rails.application.credentials.dig(:notion, :integration_token)
    raw.present? ? raw.to_s : nil
  rescue => _e
    nil
  end

  def env_credentials_token
    token = ENV["NOTION_INTEGRATION_TOKEN"]
    token.presence
  end
end
```

## 通用 Notion HTTP Client（階段 3，可先行定案）

Notion API 是單純 REST／JSON，且 `faraday` 已透過既有 gem 相依鏈存在於 `Gemfile.lock`（見探索結果），
**不需要新增 Gemfile 項目**：

```ruby
# app/clients/notion_api_client.rb
class NotionApiClient
  include NotionCredentials

  BASE_URL = "https://api.notion.com/v1"
  # 固定版本字串，避免 Notion 端無感更新 API 版本造成欄位格式非預期變動；升級須是刻意決策。
  NOTION_VERSION = "2022-06-28"

  def initialize
    @conn = Faraday.new(url: BASE_URL) do |f|
      f.request :json
      f.response :json, content_type: /\bjson$/
      f.adapter Faraday.default_adapter
    end
  end

  def query_data_source(data_source_id, start_cursor: nil)
    @conn.post("/data_sources/#{data_source_id}/query", { start_cursor: start_cursor }.compact, headers)
  end

  def retrieve_data_source(data_source_id)
    @conn.get("/data_sources/#{data_source_id}", nil, headers)
  end

  private

  def headers
    {
      "Authorization" => "Bearer #{notion_token}",
      "Notion-Version" => NOTION_VERSION,
      "Content-Type" => "application/json"
    }
  end
end
```

`PhaseRecordsNotionClient`／`ProjectProfilesNotionClient`（階段 4／5）皆會 `include` 或委派給這個
基底 client，並各自處理 `has_more`／`next_cursor` 分頁與 property parser——parser 的實際內容待階段
1／2 確認 schema 後才能寫，此處不預先假設。

---

## 資料庫實際欄位（⚠️ 全部待階段 1／2 確認，以下為 static prototype 依單一截圖寫的佔位假設）

| Notion property（截圖顯示名稱） | 對應內部欄位 | 假設型別 | 確認狀態 |
|---|---|---|---|
| 日期 | `planned_date` | `date` ⚠️ | 未確認 |
| 實際完成 | `actual_date` | `date` ⚠️ | 未確認 |
| 專案 | `project` | `relation` ⚠️（也可能是 `rich_text`／`title`，見需求 3） | 未確認 |
| 議題 | （目前 static prototype 不使用此欄位） | `title`／`rich_text` ⚠️ | 未確認 |
| 類型 | `stage` | `select` ⚠️（也可能是 `status`） | 未確認，且僅觀察過 4／5 個合法值中的 4 個 |
| 狀態 | `status` | `select`／`status` ⚠️ | 未確認 |
| 原因 | `reason` | `rich_text` ⚠️ | 未確認 |

階段 1 完成後，本表 SHALL 整表替換為真實 `Retrieve a data source` API 回應內容，不得保留任何 ⚠️。

---

## 純邏輯 Ruby 移植（階段 7，可先行定案，不依賴 schema）

`docs/js/project-phase-tracking.js` 的 `parseDateOnly`／`diffDays`／`computeRowState`／甘特圖
`stageBar` 幾何計算，其規則已在 static prototype 三輪審閱定案，與資料來源無關，可直接移植為 Ruby
（放在 `ProjectPhaseTrackingHelper`，比照既有 `ProjectHistoryHelper` 的角色）：

- `parse_date_only(date_str)`：Ruby `Date.iso8601` 搭配 `rescue` 回傳 `nil`（等同 JS 版
  `parseDateOnly` 的容錯行為），不需要手刻 `Date.UTC` 等價邏輯——Ruby `Date` 物件本身無時區概念，
  直接比較日期部分即可，天生比 JS `Date` 安全，但**仍須以 `Date.iso8601` 嚴格解析**，不得用
  `Date.parse`（`Date.parse` 對不合法格式的容錯行為與 `Date.iso8601` 不同，可能誤判格式錯誤的
  字串為合法日期）。
- `diff_days(actual_date, planned_date)`：`(actual - planned).to_i`（Ruby `Date` 相減直接得到
  `Rational` 天數，取整數即可，不需要毫秒／86400000 換算）。
- `compute_row_state(planned_date, actual_date)`：與 JS 版邏輯一致的四狀態組合判斷（見 static
  prototype design.md）。
- 甘特圖幾何：比照既有 `project_history_helper.rb` 的 `xAt`／`monthTicks`／SVG padding 常數手法，
  改用 static prototype 已定案的錨點規則（`planned_date` 為左端點、提前完成畫「提前幅度」視覺
  標記、SVG 最小寬度 900px）。

---

## 錯誤處理

沿用需求 1.4／需求 5 的錯誤碼對應（`access_denied`＝401、`sheet_not_found`＝404 語意重新詮釋為
「database ID 錯誤或未分享給 Integration」、`internal_error`＝其餘）。額外規則：

- Notion API 回傳 `429 Too Many Requests` 時，THE `NotionApiClient` SHALL 讀取回應的
  `Retry-After` 標頭並重試一次（Notion API 有速率限制，單一 Integration 平均約每秒 3 次請求，本頁
  單次載入僅需個位數次請求，正常情況不會觸發，僅作為防禦）；重試後仍失敗則以 `internal_error`
  回傳，不得無限重試。
- 分頁游標（`next_cursor`）處理中途失敗時，THE Client SHALL 視為整體讀取失敗（`internal_error`），
  不回傳部分資料（避免顯示不完整、使用者誤判資料已讀取完畢）。

---

## 測試策略

- 階段 3、7（憑證模組、通用 client、純邏輯 Ruby 移植）**可在階段 0 解鎖前先寫好對應的 RSpec unit
  test**（`diff_days`／`compute_row_state` 用已知輸入輸出組合驗證，不需要真實 API）。
- 階段 1、2、4、5、6、8、9 需要真實 Notion API 存取，無法在拿到 token 前驗證，**不得**用臆測的
  schema 先寫死 parser 邏輯後才驗證——依「分階段實作與確認順序」表，先探索（階段 1／2）再實作
  （階段 4／5）。
- 階段 10：比照既有 `warroom-project-history-real-source` 慣例，於真實串接完成後，在本文件補上
  「真實資料串接時發現的重大修正」章節，記錄規劃假設與實際狀況的落差，供未來同類 spec 借鏡。
