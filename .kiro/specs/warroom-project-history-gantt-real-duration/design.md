# 設計文件

## 概觀

在既有 `Sheets::FetchProjectHistory`（`warroom-project-history-real-source`）基礎上調整：橫向總覽
改為一律用 307 燃盡議題畫甘特圖任務（DurationTask），查無對應議題的專案該列不畫任何色塊。不新增
資料來源、不改資料庫、不動 305/306 既有 Actor，只動 307 呼叫時機與甘特圖／清單渲染邏輯。

**設計變更紀錄（相對於 `warroom-project-history-real-source` 的既有行為）**：
原設計刻意讓橫向總覽完全不呼叫 306/307（見該 spec 需求 6、`fetch_project_history_spec.rb` 的
`"does not call 306/307 at all when no project is given"` 測試），理由是不讓非核心資料來源的可用
性問題拖累總覽頁。本 spec 改變這個決定的一半：橫向總覽現在會呼叫 307（甘特圖需要真正的時程區間，
不是非核心資料），但**呼叫失敗時的處理方式沿用同一個精神**——降級顯示（`gantt_duration_unavailable:
true`，全部專案的甘特圖那一列改為不畫任何色塊），不讓 307 的問題擋住整頁。306（議題）仍然完全不在
橫向總覽呼叫範圍內，因為甘特圖不需要議題資料。既有測試 `"does not call 306/307 at all when no
project is given"` 需要拆成兩條：306 維持「不呼叫」，307 改為「會呼叫，但失敗不影響整體成功」。

**設計變更紀錄二（實作後簡化，拿掉 CheckpointTask）**：
第一版實作曾在「307 無對應議題」時退回 305 檢查點顯示（雙 kind 並存：DurationTask／CheckpointTask，
`ProjectHistoryHelper#gantt_chart_task_rect` 依 `task[:kind]` 分派到兩個不同的私有方法）。用真實
Google Sheets 資料驗證時發現：目前 9 個有進度資料的專案，307 對應全數成功，CheckpointTask 分支
完全沒被觸發到——是為了假設中的「307 覆蓋率不保證 100%」保留的保險分支，違反最簡方案原則；使用者
看到雙 kind 的程式碼與圖例也直接反問「為什麼一個甘特圖會有兩個邏輯，這樣合理嗎？」。故拿掉
CheckpointTask：`duration_tasks_from_burndown` 回傳的任務 hash 不再帶 `kind` 欄位，
`gantt_chart_task_rect` 不再分派、直接就是原本的 `duration_task_rect` 邏輯，307 無對應議題的專案
`tasks` 為空陣列（甘特圖那一列不畫色塊，不是整列消失）。相關 CSS（`.gantt-task-checkpoint*`）、
圖例項目、`ProjectHistoryRowBlueprint` 的 `:gantt_kind` 欄位一併移除。若未來真的出現 307 覆蓋不到
的專案，行為就是「那一列沒有色塊」，不需要額外的容錯程式碼；要恢復雙 kind 顯示需要另開需求討論，
不是本次簡化的預設方向。

**實作後修正的真實 bug**：換源後 `gantt_chart_domain`（計算時間軸 min/max）一度仍只掃描
`planned_completion_date`／`actual_completion_date` 兩個 305 檢查點欄位，沒有涵蓋 DurationTask 的
`start_date`／`due_date`。全部任務都是 DurationTask 的專案因此完全沒有日期可用，min/max 被迫退化
成只剩「今天」一天，導致所有色塊的 x 座標算出離譜的值、擠在畫布邊緣——這正是使用者回報「所有色塊
都貼在最左邊、月份格線消失」那張截圖的成因。修法：`gantt_chart_domain` 改成只掃描
`start_date`／`due_date`（拿掉 CheckpointTask 後，任務只會有這兩個欄位），並補上對應的迴歸測試。

---

## 資料流

```
ProjectHistoryController#index
  → Sheets::FetchProjectHistory.result(project:, year:)
      ├─ Sheets::FetchProjectRoster.result           （客戶/PM/burndown_names_raw，失敗降級）
      ├─ Sheets::FetchProjectProgress.result(scope:"all") （305，失敗整體失敗，橫向總覽必要）
      ├─ Sheets::FetchProjectBurndown.result(status:"all") （307，全量，橫向總覽用；失敗降級，
      │                                                     縱向歷程用時失敗仍整體失敗）
      ├─ build_overview_rows(roster, progress_grouped, burndown_issues)
      │     └─ 每個專案：matched_burndown_issues → duration_tasks_from_burndown
      │        （查無對應時得到空陣列，該列不畫色塊）
      └─（project present 時）Sheets::FetchIssueDashboard.result（306，失敗整體失敗）
            └─ build_detail(...)（不變，仍用同一份 307 issues，重用 matched_burndown_issues）
```

`Sheets::FetchProjectBurndown.result(status: "all")` 只呼叫一次，橫向總覽與縱向歷程共用同一份
`burndown_issues`，避免重複打 Google Sheets API。

---

## 關鍵設計決策

### 1. 甘特圖任務只有一種形狀，`tasks` 為空陣列代表「這個專案沒有 307 對應資料」

`row[:tasks]` 一律是 `duration_tasks_from_burndown` 的輸出（見上方「設計變更紀錄二」，已拿掉雙
kind 分流）。查無對應議題時 `tasks` 為 `[]`，`ProjectHistoryHelper#gantt_chart_task_rect` 對空陣列
自然不會畫出任何 `<rect>`，不需要額外的分支處理空狀態。清單頁（`_overview_list.html.erb`）不關心
`tasks` 陣列內容，只讀取 row 層級彙總後的 `progress_percent` / `hours_estimated` /
`hours_consumed`（`tasks` 為空時三者皆為 `nil`，顯示 `—`）。

### 2. 307↔Roster 對應規則抽成 `matched_burndown_issues`，橫向總覽與縱向歷程共用

既有 `build_detail` 內已有這段比對邏輯（`burndown_names_raw` 子字串比對，查無則精確比對）。本 spec
抽成 `matched_burndown_issues(roster_row, project_name, burndown_issues)` 私有方法，兩處呼叫，避免
橫向總覽與縱向歷程對「這個專案對應哪些 307 議題」給出不一致的答案。

### 3. DurationTask 完成度＝「已消耗人時 ÷ 預估人時」，取自既有燃盡序列，不新增計算邏輯

`Sheets::FetchProjectBurndown` 的 `merge_rows` 已經算出 `actual_series`（剩餘人時逐週序列）。已消耗
人時 = `estimated_hours − actual_series.last[:hours]`。沒有 `actual_series` 資料點的議題（例如剛
開案、燃盡表還沒填）視為「工時資料不足」，不填色、不計入 KPI 欄的加總分子分母（見需求 2.2、3.1）。

### 4. DurationTask 的區間右界沒有「實際完成日」可用，退而求其次用 `due_date`

307 燃盡議題只有 `status`（未開始／執行中／已完成）與 `due_date`（計畫完成日），沒有「實際幾號結
案」的欄位。已完成的 DurationTask 時程條右界因此固定用 `due_date`，不是真正的實際結案日——這是
307 資料本身的限制，不是本 spec 的計算錯誤。若之後 307 試算表新增「實際完成日」欄位，可以直接把
`gantt_chart_task_rect` 改成優先取該欄位，不需重新設計。

未完成的 DurationTask，右界＝`due_date` 與今日兩者較晚者：還沒到期＝維持顯示到 `due_date`（不提前
延伸出一段沒發生過的時間）；已逾期＝延伸到今日，讓使用者看出「已經拖了多久」。

### 5. 逾期判斷：`duration_task_overdue?`

`!done && due_date < 今天`：未完成 ＋ 期限已過＝逾期，helper 端的 `gantt_chart_task_rect` 與 actor
端的 `row_has_overdue?`／`duration_task_overdue?`（用於風險排序）共用同一個判斷精神，各自實作在
自己的檔案裡（helper 端算 `rect[:overdue]` 用於畫框；actor 端算 `has_overdue` 用於排序），不強行
抽成跨層共用方法。

### 6. 風險排序：專案列依「是否含逾期任務」二分排序，同組內維持原順序

`Controller#build_overview` 篩選後排序，比照既有 `Sheets::FetchProjectProgress#sort_overdue_first`
的寫法（`sort_by { has_overdue ? 0 : 1 }`），不新增排序穩定性保證機制——與既有程式碼的既有取捨
一致（同一批 spec 已有的慣例，非本 spec 新增的風險）。

---

## 已知簡化

1. **DurationTask 右界用 `due_date` 不是實際完成日**（見決策 4），307 資料本身沒有這個欄位。
2. **KPI「工時」欄只加總有 `actual_series` 資料的議題**，若某專案的 307 議題全部沒有工時資料，會
   顯示 `—` 而不是 `0h / Nh`——這是刻意的（避免「看起來完全沒做」的誤導，實際上可能只是燃盡表還
   沒開始填）。
3. **307 無對應議題時，該專案的甘特圖那一列不畫任何色塊**（不退回 305 的單一完成日期畫出語意不對
   的假時程，見「設計變更紀錄二」）。目前真實資料下沒有專案落入這個情況，但程式邏輯上是合法且會
   正確處理的空狀態，不是遺漏。
4. `docs/` 靜態原型不在本 spec 範圍內（見 requirements.md「不納入範圍」），甘特圖語意兩邊會暫時
   不一致；若之後要處理，需另開 spec。
