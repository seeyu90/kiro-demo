module ExecutiveSummaryHelper
  HEALTH_LABEL = {
    critical: "🔴 需立即關注",
    at_risk: "🟡 觀察中",
    on_track: "🟢 正常"
  }.freeze

  # 沿用既有 307 燃盡頁的紅黃綠燈 CSS class（.status-over/.status-at_risk/.status-on_track），
  # 不新增另一組顏色系統。
  HEALTH_BADGE_CLASS = {
    critical: "status-over",
    at_risk: "status-at_risk",
    on_track: "status-on_track"
  }.freeze

  def executive_health_label(health)
    HEALTH_LABEL.fetch(health, health.to_s)
  end

  def executive_health_badge_class(health)
    HEALTH_BADGE_CLASS.fetch(health, "status-unknown")
  end

  BURNDOWN_FLAG_LABEL = {
    over: "超支", at_risk: "略慢", on_track: "正常", unknown: "資料不足"
  }.freeze

  def executive_burndown_flag_label(flag)
    return "—" if flag.nil?

    BURNDOWN_FLAG_LABEL.fetch(flag, flag.to_s)
  end

  # 卡片摘要列的一行結論，取代預設展開整份逐筆清單——CEO 掃過這一行就知道「為什麼」，
  # 要看是哪幾筆才需要點開詳情。逾期天數取最大值（最嚴重的那筆），不是平均或加總，
  # 避免「10 筆各延誤 1 天」跟「1 筆延誤 30 天」被同一個數字掩蓋掉輕重差異。
  def executive_project_reason_line(project)
    reasons = []
    if project[:overdue_task_count].positive?
      max_delay = project[:overdue_tasks].filter_map { |t| t[:delay_days].to_i if t[:delay_days].present? }.max
      reasons << "#{project[:overdue_task_count]} 項任務逾期" + (max_delay ? "（最長 #{max_delay} 天）" : "")
    end
    reasons << "燃盡#{executive_burndown_flag_label(project[:burndown_flag])}" if [ :at_risk, :over ].include?(project[:burndown_flag])
    reasons << "本週有 #{project[:due_this_week_count]} 項任務即將到期" if reasons.empty? && project[:due_this_week_count].positive?

    reasons.empty? ? "目前無需要注意的例外項目" : reasons.join("；")
  end
end
