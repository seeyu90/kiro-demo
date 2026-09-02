# 任務清單

## Phase 1（本次實作，已完成）

- [x] 1. 新增彙總 Actor `Summary::BuildExecutiveSummary`
  - 依序呼叫 305/Roster/307/306/階段追蹤五個既有 Actor，Roster/307/306/階段追蹤個別失敗時降級
  - 健康度規則（紅/黃/綠）+ 排序
  - 階段追蹤例外獨立輸出，不合併進專案卡片
  - _需求：1、2、3、4_

- [x] 2. 新增 `ExecutiveProjectSummaryBlueprint`
  - _需求：1_

- [x] 3. 新增 `ExecutiveSummaryController` + 路由 `/executive_summary`
  - _需求：1、3_

- [x] 4. 新增 View（`index`/`_kpi_strip`/`_project_card`/`_phase_exceptions`）+
      `ExecutiveSummaryHelper`
  - 沿用既有 `.summary-bar`/`.project-card`/`.status-*` CSS class，不新增顏色系統
  - _需求：1、4_

- [x] 5. 入口頁新增連結
  - _需求：1_

- [x] 6. RSpec：Actor spec（健康度分支、roster/burndown 對照、降級行為）+ Request spec
      （頁面渲染、核心資料失敗、次要資料源失敗）
  - _需求：2、3、4_

- [x] 7. 檢查點：`bundle exec rspec`、`bin/rubocop` 全部通過（既有 1 個與本次改動無關的
      日期相依既有測試 flaky failure，見下方備註）

**備註**：`bundle exec rspec` 執行時 `spec/actors/sheets/fetch_project_history_spec.rb:56`
（"builds gantt tasks from matched 307 burndown issues"）目前會因為測試沒有 `travel_to` 固定
日期、且系統日期已晚於測試假設的 `due_date`（2026-08-22）而失敗；此為既有測試本身的日期
相依問題，與本 spec 的任何改動無關，不在本 spec 範圍內修正。

## Phase 2（設計已定案，尚未排入實作——見 design.md）

- [ ] 8. 新增資料庫（sqlite3 + ActiveRecord + `executive_weekly_snapshots` migration）
- [ ] 9. 新增 `ExecutiveWeeklySnapshot` Model + 快照寫入邏輯（方案 A 或 B，見 design.md）
- [ ] 10. 新增 `Summary::ComputeWeeklyDelta`（或併入既有 Actor）+ View 呈現 Δ 箭頭/轉紅標籤
- [ ] 11. RSpec：連續兩週快照的 delta 計算、無歷史快照時不顯示趨勢區塊、同週重複造訪不重複列
- [ ] 12. 確認 Kamal/Docker 部署設定讓 sqlite 檔案跨部署持久化
