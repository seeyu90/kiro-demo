# 設計文件

## 架構

```
ExecutiveSummaryController#index
  → Summary::BuildExecutiveSummary.result
      → Sheets::FetchProjectProgress.result(scope: "all", incomplete_only: false)   # 核心，失敗即整頁失敗
      → Sheets::FetchProjectRoster.result                                            # 降級：roster_unavailable
      → Sheets::FetchProjectBurndown.result(status: "all")                           # 降級：burndown_unavailable
      → Sheets::FetchIssueDashboard.result(status: "")                               # 降級：issues_unavailable
      → Sheets::FetchPhaseTracking.result                                            # 降級：phase_tracking_unavailable
  → ExecutiveProjectSummaryBlueprint.render_as_hash(result.projects)
  → app/views/executive_summary/index.html.erb
      ├── _kpi_strip（公司層 KPI，沿用 .summary-bar/.stat-item）
      ├── _project_card × N（Roster 主鍵的專案健康度卡片，沿用 .project-card）
      └── _phase_exceptions（階段追蹤例外，獨立區塊，見「已知限制」）
```

## Components and Interfaces

- **`Summary::BuildExecutiveSummary`**（`app/actors/summary/build_executive_summary.rb`）：唯一的
  新 Actor，只做「呼叫既有 5 個 Actor + 彙總」，不重新讀 Sheets Client、不重新實作任何判斷邏輯
  （逾期、燃盡燈號皆呼叫既有公開方法）。
- **`ExecutiveProjectSummaryBlueprint`**：專案卡片欄位的單一輸出定義。Portfolio KPI 為單一物件
  （非清單），不透過 Blueprint，由 Controller 直接指派給 View（同 `project_history_controller.rb`
  對 `@roster_unavailable` 等旗標的處理方式）。
- **`app/helpers/executive_summary_helper.rb`**：健康度／燃盡燈號的顯示文字與 CSS class 對照表
  （View 專用格式化，比照既有 `ProjectPhaseTrackingHelper#phase_tracking_status_class` 慣例）。

## 健康度規則（權威定義，取代規劃階段的初版猜測）

規劃階段（`.claude/plans/ceo-10-swift-lighthouse.md`）曾假設「延誤已完成」屬於黃燈訊號；實作前
讀 `ProjectPhaseTrackingHelper::STATUS_TAG_CLASS` 才發現「延誤已完成」在既有頁面已歸類為綠色
（已結束，只是曾經遲到），與「延誤未完成」（紅色，仍未結束）語意不同。本設計改採以下規則，
且不把階段追蹤併入紅黃燈判斷（見「已知限制」），只用 305＋307：

- **紅燈**：305 有 ≥1 個逾期任務，**或** 307 任一未完成議題 `burndown_status == :over`。
- **黃燈**：不符合紅燈，且 307 任一未完成議題 `:at_risk`，**或** 305 有任務本週到期
  （尚未逾期）。
- **綠燈**：以上皆不成立（含「燃盡資料不足以判斷」的 `:unknown` 情況——資料不足不等於風險，
  不應誤導 CEO 以為有問題）。

排序：紅 → 黃 → 綠。

## 已知限制：階段追蹤無法對照到 Roster

`Sheets::FetchPhaseTracking` 讀的 `ProjectProfilesSheetsClient`（「專案」分頁）用 Notion/Github
專案代碼（如 `HRM`、`JZNPMS`）當鍵；`Sheets::FetchProjectRoster`（「專案工程師對照表」分頁）用
「專案全名／縮寫」當鍵。兩者是同一份試算表的不同分頁，但**沒有任何既有欄位互相對照**（不像
307 有 `burndown_names_raw` 這種人工維護的對照欄）。

嘗試用「客戶＋PM 相同」猜測對應專案在客戶或 PM 重複時會猜錯——對 CEO 決策依據而言，猜錯的
合併比不合併更危險。故本設計刻意不合併，階段追蹤的例外（`build_phase_exceptions`）獨立成一節，
以自己的 project_code／customer／pm 呈現。

**後續建議**（不在本 spec 範圍）：仿照 Roster 的 `burndown_names_raw`，在「專案工程師對照表」
分頁新增一欄人工維護的「ProjectProfiles 對應代碼」，之後即可比照 307 的比對方式合併。

## Phase 2（週對週趨勢比較）— 設計已定案，實作排在 Phase 1 之後

CEO 週報最有價值的訊號之一是「跟上週比，變好還是變壞」。這需要每週保存一份快照才能比對。
目前整個 Rails App **完全沒有資料庫**（`config/application.rb` 的 `active_record/railtie` 被
註解掉、無 `config/database.yml`、Gemfile 無任何 DB gem），Phase 1 刻意不引入這個變更，先讓
健康度規則跑過一輪真實資料驗證再疊加。

### 資料表設計

```ruby
create_table :executive_weekly_snapshots do |t|
  t.date    :week_start,              null: false   # 該週週一（Date.current.beginning_of_week）
  t.integer :red_count,                null: false
  t.integer :yellow_count,             null: false
  t.integer :green_count,              null: false
  t.integer :overdue_task_total,       null: false
  t.integer :urgent_complaint_count,   null: false
  t.decimal :sla_rate,                 precision: 5, scale: 2
  t.json    :projects_snapshot,        null: false   # [{project_name, health, overdue_task_count, burndown_flag}, ...]
  t.timestamps
end
add_index :executive_weekly_snapshots, :week_start, unique: true
```

### 前置變更

1. Gemfile 新增 `sqlite3`；取消註解 `config/application.rb` 的 `active_record/railtie`；新增
   `config/database.yml`。
2. 新增 Model `app/models/executive_weekly_snapshot.rb`（薄 Model，只做 `week_start` 唯一性
   驗證；讀寫仍經由 Actor，補充 `rails-standards.md` 目前未涵蓋的 Model 層規範：「Model 僅作
   資料存取，不含業務邏輯」）。
3. 部署面：確認 Kamal/Docker 設定能讓 sqlite 檔案跨部署持久化（掛 volume）。

### 快照寫入時機

**方案 A（推薦）**：`ExecutiveSummaryController#index` 算完本週彙總後，
`ExecutiveWeeklySnapshot.find_or_initialize_by(week_start: ...).update!(...)`，零排程基礎設施，
取捨是 GET 請求有寫入副作用（冪等、範圍侷限在這支內部管理頁面，風險可接受）。
**方案 B**：獨立 rake task + 外部 cron，GET 請求維持無副作用，但需要新增排程機制。

### Delta 計算

新增 `Summary::ComputeWeeklyDelta`（或併入 `BuildExecutiveSummary`，視程式碼量決定）：取上一筆
`ExecutiveWeeklySnapshot`（`week_start <` 本週，無則不顯示趨勢區塊），計算 portfolio 與逐專案的
Δ（紅燈數增減、逾期任務增減、燈號轉變如「本週轉紅」）。
