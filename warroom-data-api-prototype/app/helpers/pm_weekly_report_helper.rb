# 方法一律加 pm_weekly_ 前綴：Rails 預設 include_all_helpers 會把所有 app/helpers/*.rb 混入
# 同一個 view context，同名方法會互相覆蓋（詳見 ProjectPhaseTrackingHelper 開頭的說明）。
module PmWeeklyReportHelper
  def pm_weekly_range_label(range)
    return "—" if range.nil?

    "#{pm_weekly_date_label(range.first)} ~ #{pm_weekly_date_label(range.last)}"
  end

  # 日期一律顯示為 YYYY/MM/DD。無法解析的原始字串照原樣顯示，不顯示成「—」——305 的
  # 正規化本來就會保留無法解析的原始值（見 Sheets::FetchProjectProgress#normalize_date），
  # 把它藏起來會讓 PM 以為那一格是空的，看不出是試算表填錯格式。
  def pm_weekly_date_label(value)
    return "—" if value.blank?

    date = value.is_a?(Date) ? value : Sheets::FetchProjectProgress.parse_date(value)
    date ? date.strftime("%Y/%m/%d") : value.to_s
  end

  # 逾期天數即時計算（今天 − 預計完成日），不採用試算表的「延遲天數」欄位：該欄位對未完成
  # 任務不會隨日期前進而更新，週五看到的會是過期的數字（需求 2.9）。
  def pm_weekly_overdue_days(task)
    date = Sheets::FetchProjectProgress.parse_date(task[:planned_completion_date])
    return nil if date.nil?

    (Date.current - date).to_i
  end

  # SLA 推算出來的到期日要標示出來，不讓 PM 誤以為試算表有填（需求 3.5）。
  def pm_weekly_due_date_label(issue)
    label = pm_weekly_date_label(issue[:effective_due_date])
    issue[:due_date_estimated] ? "#{label}（推算）" : label
  end

  # 顯示相對時間而非絕對時間：本 app 未設定 config.time_zone（預設 UTC），絕對時間會跟
  # 使用者的本地時間差 8 小時。規則與 DashboardController#freshness_label 相同，但兩處各自
  # 實作、不共用——目前只有這兩個使用點，等第三個頁面也需要時再抽到 ApplicationHelper。
  FRESH_THRESHOLD = 10.seconds

  def pm_weekly_freshness_label(fetched_at)
    return nil if fetched_at.nil?

    elapsed = Time.current - fetched_at
    return "資料剛剛更新" if elapsed < FRESH_THRESHOLD

    minutes = (elapsed / 60).floor
    minutes.zero? ? "資料剛剛更新" : "資料更新於 #{minutes} 分鐘前"
  end

  # 區塊筆數（需求 1.3）。Actor 輸出的 305／306 清單都是 { 專案名稱 => [項目, ...] } 的分組
  # 結構，畫面要顯示的卻是跨專案的總筆數，故在此攤平相加；一個區塊常由兩三個分組結構組成
  # （例如「本週工作」＝本週待完成＋本週已完成＋306 議題），所以收可變參數。
  def pm_weekly_count(*grouped)
    grouped.sum { |group| group.values.sum(&:size) }
  end
end
