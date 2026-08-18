# 實作計畫：專案歷程甘特圖真實區間 + UX 改善

## 概述

在既有 `Sheets::FetchProjectHistory` 基礎上，橫向總覽甘特圖改用 307 燃盡議題畫真實時程區間
（DurationTask）；並加上依工時消耗比例填色、進度／工時 KPI 欄、圖例、逾期標示、風險排序。範圍
對應 requirements.md 需求 1～5（A／B／C）。

**狀態**：已完成實作並用真實資料驗證後追加修正兩項：

1. **拿掉 CheckpointTask（雙 kind 簡化為單一 kind）**：第一版曾在「307 無對應議題」時退回 305
   檢查點顯示，用真實資料驗證後發現目前 9 個專案 307 對應全數成功，這個分支是沒被觸發到的假設性
   保險，使用者也直接反問「為什麼一個甘特圖會有兩個邏輯」，故拿掉——307 無對應議題時該專案的甘特
   圖那一列改為不畫任何色塊。詳見 design.md「設計變更紀錄二」。
2. **修正 `gantt_chart_domain` 遺漏 DurationTask 日期欄位的 bug**：換源後一度只掃描 305 的
   `planned_completion_date`／`actual_completion_date`，沒涵蓋 DurationTask 的
   `start_date`／`due_date`，導致時間軸整批退化成「今天」一天、所有色塊擠在畫布邊緣（使用者截圖
   回報的症狀）。已修正並補上迴歸測試（`spec/helpers/project_history_helper_spec.rb`
   `#gantt_chart_domain`）。

`bundle exec rspec` 全專案 372/372 通過，`bundle exec rubocop` 本次變更檔案無違規。已用開發伺服器
對真實 Google Sheets 資料重新驗證：目前 305 有進度資料的 9 個
專案，307 對應全數成功（0 個空白列），甘特圖正確畫出 DurationTask 時程條、依工時比例
填色（34 段已完成、6 段進行中）、6 個逾期標示、圖例正常顯示；清單頁「進度」「工時」兩欄正常顯示
（含消耗工時超過預估工時、進度 clamp 在 100% 的真實案例）。

---

## 任務

- [x] 1. `Sheets::FetchProjectHistory` — 307 全量呼叫與降級
  - [x] 1.1 `#call`：橫向總覽階段呼叫一次 `Sheets::FetchProjectBurndown.result(status: "all")`，
        成功則供橫向總覽與縱向歷程共用；失敗且未選定 `project` 時降級（`gantt_duration_
        unavailable: true`，`burndown_issues = []`）；失敗且已選定 `project` 時整體失敗
    - _需求：1.3, 1.3a, 5.1_
  - [x] 1.2 新增 `output :gantt_duration_unavailable`
    - _需求：1.3_
  - [x] 1.3 更新 `#call` 測試：拆分「不呼叫 306/307」為「306 仍不呼叫」＋「307 會呼叫，失敗時
        橫向總覽仍成功且 `gantt_duration_unavailable` 為 true」；新增「已選定 project 時 307
        失敗仍整體失敗」

- [x] 2. `matched_burndown_issues` 共用比對邏輯
  - [x] 2.1 從 `build_detail` 抽出 307↔Roster 對應邏輯為私有方法
        `matched_burndown_issues(roster_row, project_name, burndown_issues)`，`build_detail`
        改呼叫此方法（行為不變）
    - _需求：1a_
  - [x] 2.2 迴歸測試：抽出後 `build_detail` 既有測試（子字串比對／退回精確比對）全數通過

- [x] 3. `build_overview_rows` — DurationTask／CheckpointTask 分流
  - [x] 3.1 每個專案先呼叫 `matched_burndown_issues`；有結果則 `duration_tasks_from_burndown`
        （`kind: "duration"`），否則 305 任務打上 `kind: "checkpoint"`
    - _需求：1, 1a_
  - [x] 3.2 `duration_tasks_from_burndown`：`start_date`／`due_date`／`done`（`status == "done"`）
        ／`estimated_hours`／`consumed_hours`（由 `actual_series` 最後一筆反推，缺資料時為 nil）
    - _需求：1.2, 2.1, 2.2_
  - [x] 3.3 單元測試：307 有對應資料時輸出 DurationTask；無對應時退回 CheckpointTask；
        `consumed_hours` 反推邏輯；`actual_series` 空陣列時 `consumed_hours` 為 nil

- [x] 4. 進度／工時 KPI 欄位彙總
  - [x] 4.1 `progress_percent_for(kind, tasks)`：DurationTask 用工時比例（排除無工時資料的議題）、
        CheckpointTask 用任務完成數比例、空清單回傳 nil
    - _需求：3.1, 3.3_
  - [x] 4.2 `hours_estimated` / `hours_consumed` 欄位彙總（CheckpointTask 專案回傳 nil）
    - _需求：3.2, 3.3_
  - [x] 4.3 `ProjectHistoryRowBlueprint` 新增 `:gantt_kind, :progress_percent, :hours_estimated,
        :hours_consumed, :has_overdue` 欄位
  - [x] 4.4 單元測試涵蓋上述兩個彙總方法的三種情境（DurationTask 有工時資料／DurationTask 工時
        資料不足／CheckpointTask）

- [x] 5. 逾期判斷與風險排序
  - [x] 5.1 `duration_task_overdue?(task)`（`!done && due_date < 今天`），CheckpointTask 沿用
        `Sheets::FetchProjectProgress.overdue?`
    - _需求：4.3_
  - [x] 5.2 `row_has_overdue?(tasks)` 依 `kind` 分流判斷，寫入 row 的 `has_overdue`
    - _需求：4.3_
  - [x] 5.3 `ProjectHistoryController#build_overview`：篩選後依 `has_overdue` 排序（含逾期任務的
        專案優先），同組內維持原順序
    - _需求：4.4_
  - [x] 5.4 request spec：驗證含逾期任務的專案排在篩選結果最前面

- [x] 6. `ProjectHistoryHelper` — 甘特圖區塊渲染分流
  - [x] 6.1 `gantt_chart_task_rect` 依 `task[:kind]` 分派至 `duration_task_rect` /
        `checkpoint_task_rect`；`checkpoint_task_rect` 即既有邏輯改名，行為不變
    - _需求：1.2, 1.4_
  - [x] 6.2 `duration_task_rect`：依決策 4 的區間右界規則計算 `x`／`width`；另計算
        `fill_width`（`width * duration_fill_ratio`）與 `overdue` 布林
    - _需求：1.2, 2.1, 2.2, 4.3_
  - [x] 6.3 `duration_fill_ratio(task)`：`consumed_hours` 為 nil 或 `estimated_hours` 為 0 時
        回傳 0（不填色，見需求 2.2）
  - [x] 6.4 helper 單元測試：DurationTask 未逾期／已逾期／已完成的 x/width 計算；
        `duration_fill_ratio` 的三種邊界情況；`checkpoint_task_rect` 既有測試不受影響

- [x] 7. `_overview_gantt.html.erb` — 雙層 rect 渲染 + 逾期樣式
  - [x] 7.1 依 `rect[:kind]` 套用 `gantt-task-checkpoint`（含 done/open 子 class）或
        `gantt-task-track` 底色 class；`rect[:overdue]` 為真時額外套用 `gantt-task-overdue` class
    - _需求：1.4, 4.3_
  - [x] 7.2 `rect[:kind] == "duration"` 且 `fill_width > 0` 時，疊加第二個 `<rect>`（
        `gantt-task-fill-done` / `gantt-task-fill-open`）
    - _需求：2.1_
  - [x] 7.3 `title` 文字依 kind 顯示對應內容（DurationTask 含工時資訊或「工時資料不足」）
    - _需求：2.2_

- [x] 8. 圖例與今日線樣式
  - [x] 8.1 新增 `_gantt_legend.html.erb`，僅在 `@view == "gantt"` 時渲染於 `_overview.html.erb`
        （含 `gantt_duration_unavailable` 降級提示）
    - _需求：4.1_
  - [x] 8.2 CSS：新增 `.gantt-task-track` `.gantt-task-fill-done` `.gantt-task-fill-open`
        `.gantt-task-checkpoint`（含 `-done`/`-open`）`.gantt-task-overdue` `.gantt-legend`
        `.legend-*`；加強 `.gantt-today-line` 對比度（改用 `--overdue-text`、加粗）
    - _需求：1.4, 2.1, 4.2, 4.3_

- [x] 9. 清單檢視 KPI 欄位
  - [x] 9.1 `_overview_list.html.erb` 新增「進度」「工時」欄，`—` 處理空值情境；逾期專案列加
        `row-overdue` class（左側紅色細邊框，非動畫）
    - _需求：3.1, 3.2, 3.3_
  - [x] 9.2 request spec 驗證新欄位輸出（含有/無 307 對應資料兩種情境）

- [x] 10. 全量驗證
  - [x] 10.1 `bundle exec rspec`（373/373 通過）
  - [x] 10.2 `bundle exec rubocop` 針對本次變更檔案（無違規）
  - [x] 10.3 依 requirements.md 驗收標準逐條核對；並用開發伺服器對真實 Google Sheets 資料手動
        檢視甘特圖／清單畫面（見上方「狀態」段落的驗證結果）
