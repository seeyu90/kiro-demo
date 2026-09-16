# frozen_string_literal: true

module DashboardHelper
  # 延誤天數由 Sheets::FetchProjectProgress.delay_workdays 以工作日算好（Integer 或 nil），
  # 這裡只負責挑字樣：
  #   - nil（未到期、沒有預計完成日、已完成卻沒填實際完成日）→「—」，不下判斷
  #   - 已完成且 0 天 →「準時」
  #   - 未完成且 0 天 →「—」：已逾期但還沒跨過一個工作日（例如週六逾期、週日檢視），
  #     顯示「準時」會與旁邊的「逾期」標籤自相矛盾
  DELAY_PLACEHOLDER = "—"

  def delay_days_label(task)
    delay = task[:delay_days]
    return DELAY_PLACEHOLDER if delay.nil?
    return "+#{delay} 天" if delay.positive?

    task_completed?(task) ? "準時" : DELAY_PLACEHOLDER
  end

  # 只有真的算得出延誤／準時時才上色，「—」維持一般文字色。
  def delay_days_class(task)
    label = delay_days_label(task)
    return "delayed" if label.start_with?("+")

    label == "準時" ? "on-time" : ""
  end

  private

  def task_completed?(task)
    Sheets::FetchProjectProgress::COMPLETED_STATUSES.include?(task[:status])
  end
end
