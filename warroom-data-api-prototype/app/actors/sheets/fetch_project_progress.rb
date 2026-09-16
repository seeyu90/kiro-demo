# frozen_string_literal: true

module Sheets
  class FetchProjectProgress < ApplicationActor
    input :force, default: false
    input :project, default: nil
    input :task_types, default: nil
    input :scope, default: "due_this_week"
    # 起訖日期區間篩選（作用於 planned_completion_date），與 scope 是獨立的兩個篩選軸，
    # 同時套用（AND）。305 資料源本身鎖在單一年度分頁（見 ProjectProgressSheetsClient
    # 的 SHEET_NAME 註解），無法跨年查詢，這裡的區間篩選只能篩「當年度已載入的資料」。
    input :planned_from, default: nil
    input :planned_to, default: nil
    output :grouped_data
    output :project_names
    output :task_types_available
    output :summary
    output :display_data
    output :failure_code
    output :message
    output :fetched_at

    COLUMN_KEYS = %i[
      project_name task_name status owner
      planned_completion_date actual_completion_date delay_days task_type
    ].freeze

    # 只有「專案名稱」與「任務名稱」是必要欄位——少了這兩個，那一列根本無從辨識是什麼任務。
    # 「狀態」與「負責人」空白都不算資料不完整：真實試算表上有一批這樣的列（狀態空白的
    # HRM 任務 5 筆、其中 2 筆已逾期；無負責人的 RAG 未完成任務 3 筆），把它們整列跳過等於
    # 讓戰情室看不到真的在延誤、甚至還沒有人認領的工作，與這個頁面存在的目的正好相反。
    # 改為保留並補上預設值（見 DEFAULT_STATUS／DEFAULT_OWNER）。
    REQUIRED_KEYS = %i[project_name task_name].freeze

    PRIORITY_TYPES = [ "功能", "PR" ].freeze
    # 來源資料的類型欄除了五種正式類型外還有「未分類」（還沒被歸類，不等於不重要），
    # 預設一併勾選，否則這些任務在預設檢視下等於不存在。
    UNCATEGORIZED_TYPE = "未分類"
    DEFAULT_TASK_TYPES = (PRIORITY_TYPES + [ UNCATEGORIZED_TYPE ]).freeze
    # 「範圍」是一組具名檢視，各自回答一個常見問題：全部／還沒做完的／本週該交或本週結掉的／
    # 逾期的。incomplete 是唯一一個純狀態條件的檢視——拿掉獨立的狀態篩選後，「只看未完成」
    # 沒有別的入口，而那是使用這頁最常見的意圖之一。
    SCOPES = %w[all incomplete due_this_week overdue].freeze
    # 真實試算表的「狀態」欄位是自由輸入的中文文字，非固定英文 enum；實際觀察到的值只有
    # 「完成」「已確認」「未完成」三種，其中「完成」與「已確認」皆代表任務已結束（「已確認」
    # 的紀錄一律已有實際完成日期），故兩者皆視為完成狀態；沒有「進行中」「待開始」的細分。
    COMPLETED_STATUSES = [ "完成", "已確認" ].freeze
    # 狀態欄空白時一律補成「未完成」：這三種值以外沒有別的語意，空白只代表填表的人還沒更新，
    # 補成未完成後，逾期判斷、摘要計數與畫面上的狀態標籤才有一致且正確的依據。
    DEFAULT_STATUS = "未完成"
    # 負責人空白代表這件事還沒有人認領，明講出來比留白有用（留白會讓人以為是資料漏填）。
    DEFAULT_OWNER = "未指派"

    def call
      rows = ProjectProgressSheetsClient.fetch_rows(force: force)
      records = parse_rows(rows)
      normalized = records.map { |record| normalize_record(record) }
      grace_days = ProjectProgressSheetsClient.fetch_grace_days
      valid_records = reject_invalid_records(normalized).map do |record|
        record.merge(delay_days: self.class.delay_workdays(record, grace_days: grace_days))
      end
      self.grouped_data = group_by_project(valid_records)
      self.fetched_at = ProjectProgressSheetsClient.fetched_at

      all_tasks = grouped_data.values.flatten
      self.project_names = grouped_data.keys
      self.task_types_available = sorted_task_types(all_tasks)

      selected_types = task_types.nil? ? DEFAULT_TASK_TYPES : Array(task_types).reject(&:blank?)
      scoped_tasks = all_tasks.select { |t| matches_base_filters?(t, project, selected_types) }
      self.summary = compute_summary(scoped_tasks)

      display_project_names = project.presence ? [ project ] : project_names
      filtered = filter_tasks(all_tasks, project, selected_types, scope, planned_from, planned_to)
      grouped_filtered = filtered.group_by { |t| t[:project_name] }
      self.display_data = display_project_names.index_with { |name| sort_overdue_first(grouped_filtered[name] || []) }
    rescue Google::Apis::ClientError => e
      if e.status_code == 404 || e.message.to_s.include?("Unable to parse range")
        fail!(failure_code: :sheet_not_found, message: "找不到指定分頁或試算表：#{e.message}")
      elsif e.status_code == 403
        fail!(failure_code: :access_denied, message: "資料來源存取權限不足：#{e.message}")
      else
        fail!(failure_code: :internal_error, message: "Google Sheets API 錯誤：#{e.message}")
      end
    rescue => e
      fail!(failure_code: :internal_error, message: "未預期的內部錯誤：#{e.message}")
    end

    # 任務是否「目前仍逾期」：未完成且已過期。executive_summary／pm_weekly_report 的專案
    # 健康度、任務分類皆依賴這個較窄的定義，公開讓其他 Actor 也能呼叫（Blueprint 渲染每次
    # request 都會重新執行，不受 ProjectProgressSheetsClient 的原始列快取影響，「今天」一律
    # 是呼叫當下的日期，不會被快取凍結在舊的時間點）。
    def self.overdue?(task)
      return false if COMPLETED_STATUSES.include?(task[:status])

      date = parse_date(task[:planned_completion_date])
      date && date < Date.current
    end

    # 305 頁專用、較寬的「逾期」定義：目前仍逾期，或已完成但當初遲交（delay_days > 0）。
    # 305 的「逾期」標籤、摘要卡逾期數、「範圍＝已逾期」篩選三處都改用這個定義，理由是三者
    # 原本各自用不同標準（標籤／摘要卡用上面較窄的 .overdue?，範圍篩選另外算），同一個畫面
    # 出現兩種「逾期」卻沒有區分，容易被誤讀成資料兜不起來。
    #
    # 刻意不動上面的 .overdue?：executive_summary 的專案健康度分級與 pm_weekly_report 的任務
    # 分類都共用那個方法，這裡的調整只該影響 305 這頁，不該外溢到那兩個跨來源彙整頁面。
    def self.overdue_or_completed_late?(task)
      return task[:delay_days].to_i.positive? if COMPLETED_STATUSES.include?(task[:status])

      overdue?(task)
    end

    def self.parse_date(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    # 延誤天數 = max(工作日 − 該類型的寬限天數, 0)。
    #
    # 工作日排除週六日；沒有國定假日表，故不扣國定假日。寬限天數由業務維護在試算表的
    # 「類型設定」分頁（例如 PR 給 2 天），用這個公式回推 456 筆已完成任務，命中率 98.9%
    # （純工作日只有 84.4%），可確認這就是業務認定的算法。
    #
    # 不直接採用試算表「延誤天數」欄的值：那一欄混用了公式與手填，且與畫面上的「逾期」判斷
    # 基準不同，會出現「顯示 +7 天、實際已過 13 個日曆日」這種對不起來的情況。
    #
    # 基準日：已完成的任務比到「實際完成日期」，未完成且已逾期的任務比到「今天」。
    # 未到期、沒有預計完成日期、或已完成卻沒有實際完成日期者一律回傳 nil（無從判斷，
    # 畫面顯示「—」，不謊稱準時）。
    def self.delay_workdays(task, grace_days: {})
      planned = parse_date(task[:planned_completion_date])
      return nil if planned.nil?

      reference =
        if COMPLETED_STATUSES.include?(task[:status])
          parse_date(task[:actual_completion_date])
        elsif Date.current > planned
          Date.current
        end
      return nil if reference.nil?

      grace = grace_days[task[:task_type]].to_i
      [ workdays_between(planned, reference) - grace, 0 ].max
    end

    # 預計完成日「之後」到基準日（含）之間的工作日數：當天完成＝0 天延誤。
    def self.workdays_between(from, to)
      return 0 if to <= from

      ((from + 1)..to).count { |date| (1..5).cover?(date.wday) }
    end

    def self.week_range(date)
      monday = date - (date.wday.zero? ? 6 : date.wday - 1)
      (monday..(monday + 6))
    end

    private

    def parse_rows(rows)
      return [] if rows.nil? || rows.empty?

      rows[1..].filter_map do |row|
        next if row.nil? || (!row.empty? && row.all? { |cell| cell.to_s.strip.empty? })

        padded = row + [ nil ] * [ 0, 8 - row.length ].max
        values = padded[0, 8]

        # 第 7 欄（試算表的「延誤天數」）讀進來只是為了讓欄位對齊，值本身不採用：那一欄在
        # 試算表上混用了公式與手填，用真實資料驗算過 456 筆已完成任務，只有 84% 對得上
        # 工作日差，其餘對不上任何單一公式；改由 .delay_workdays 以工作日即時計算。
        COLUMN_KEYS.zip(values[0, 6] + [ nil, values[7] ]).to_h
      end
    end

    def normalize_record(record)
      record.merge(
        status: record[:status].to_s.strip.presence || DEFAULT_STATUS,
        owner: record[:owner].to_s.strip.presence || DEFAULT_OWNER,
        planned_completion_date: normalize_date(record[:planned_completion_date]),
        actual_completion_date: normalize_date(record[:actual_completion_date])
      )
    end

    def normalize_date(date_str)
      return nil if date_str.nil? || date_str.to_s.empty?

      match = date_str.to_s.match(%r{\A(\d{4})[-/](\d{1,2})[-/](\d{1,2})\z})
      return date_str unless match

      year, month, day = match.captures
      "#{year}-#{month.rjust(2, '0')}-#{day.rjust(2, '0')}"
    end

    # 缺少必要欄位（project_name／task_name 任一）的列會被跳過，
    # 不納入結果，也不影響其餘正常列的顯示（真實資料難免有少量不完整列）。
    def reject_invalid_records(records)
      records.reject do |record|
        REQUIRED_KEYS.any? { |key| record[key].to_s.strip.empty? }
      end
    end

    def group_by_project(records)
      records.group_by { |record| record[:project_name] }
    end

    def sorted_task_types(tasks)
      types = tasks.map { |t| t[:task_type] }.compact.uniq
      types.sort_by { |t| PRIORITY_TYPES.index(t) || PRIORITY_TYPES.length }
    end

    def matches_base_filters?(task, selected_project, selected_types)
      return false if selected_project.present? && task[:project_name] != selected_project
      return false if selected_types.any? && !selected_types.include?(task[:task_type])

      true
    end

    def filter_tasks(tasks, selected_project, selected_types, selected_scope, from, to)
      week_range = self.class.week_range(Date.current)

      tasks.select do |t|
        next false unless matches_base_filters?(t, selected_project, selected_types)
        next false unless within_planned_range?(t, from, to)
        next false if selected_scope == "incomplete" && COMPLETED_STATUSES.include?(t[:status])
        next false if selected_scope == "overdue" && !self.class.overdue_or_completed_late?(t)
        next false if selected_scope == "due_this_week" && !due_this_week_scope?(t, week_range)

        true
      end
    end

    # from／to 皆為 nil（沒篩選）時一律視為符合；planned_completion_date 本身無法解析
    # （空白或格式錯誤）時，只要有設定任一邊界就視為不符合——不確定日期落在哪裡，不該被
    # 一個「起訖日期」篩選誤放行。
    def within_planned_range?(task, from, to)
      return true if from.blank? && to.blank?

      date = self.class.parse_date(task[:planned_completion_date])
      return false if date.nil?

      (from.blank? || date >= from) && (to.blank? || date <= to)
    end

    # 「範圍」是日期條件、「狀態」是完成與否，兩者必須各自獨立：這兩個範圍原本都在開頭直接
    # 排除已完成任務，導致使用者把狀態切成「全部」時畫面毫無變化（等於控制項是壞的），
    # 而且「delay 到本週才完成」這種最該被看見的任務永遠不會出現。
    #
    # 已完成任務需要另一條日期條件，不能沿用未完成那條：未完成用「預計完成日 ≤ 本週週日、
    # 不限下界」是對的（一月就該交、現在還沒交，今天依然欠著），但同一條件套在已完成任務上
    # 等於把歷來每一筆完成的任務都算進「本週」，整個視圖會被淹沒。
    #
    # 本週到期（已完成）＝預計完成日落在本週（本週到期且已做完，含提前完成）
    #                   或實際完成日落在本週（本週結掉的，含 delay 很久這週才補完的）。
    def due_this_week_scope?(task, week_range)
      planned = self.class.parse_date(task[:planned_completion_date])

      unless COMPLETED_STATUSES.include?(task[:status])
        return planned.present? && planned <= week_range.last
      end

      actual = self.class.parse_date(task[:actual_completion_date])
      week_range.cover?(planned) || (actual.present? && week_range.cover?(actual))
    end

    def compute_summary(tasks)
      completed = tasks.count { |t| COMPLETED_STATUSES.include?(t[:status]) }
      {
        total: tasks.size,
        completed: completed,
        incomplete: tasks.size - completed,
        overdue: tasks.count { |t| self.class.overdue_or_completed_late?(t) }
      }
    end

    def sort_overdue_first(tasks)
      tasks.sort_by { |t| self.class.overdue_or_completed_late?(t) ? 0 : 1 }
    end
  end
end
