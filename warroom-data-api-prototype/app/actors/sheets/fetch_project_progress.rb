# frozen_string_literal: true

module Sheets
  class FetchProjectProgress < ApplicationActor
    input :force, default: false
    input :project, default: nil
    input :task_types, default: nil
    input :scope, default: "due_this_week"
    input :incomplete_only, default: true
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

    REQUIRED_KEYS = %i[project_name task_name status owner].freeze

    PRIORITY_TYPES = ["功能", "PR"].freeze
    SCOPES = %w[all due_this_week overdue].freeze
    # 真實試算表的「狀態」欄位是自由輸入的中文文字，非固定英文 enum；實際觀察到的值只有
    # 「完成」「已確認」「未完成」三種，其中「完成」與「已確認」皆代表任務已結束（「已確認」
    # 的紀錄一律已有實際完成日期），故兩者皆視為完成狀態；沒有「進行中」「待開始」的細分。
    COMPLETED_STATUSES = ["完成", "已確認"].freeze

    def call
      rows = ProjectProgressSheetsClient.fetch_rows(force: force)
      records = parse_rows(rows)
      normalized = records.map { |record| normalize_record(record) }
      valid_records = reject_invalid_records(normalized)
      self.grouped_data = group_by_project(valid_records)
      self.fetched_at = ProjectProgressSheetsClient.fetched_at

      all_tasks = grouped_data.values.flatten
      self.project_names = grouped_data.keys
      self.task_types_available = sorted_task_types(all_tasks)

      selected_types = task_types.nil? ? PRIORITY_TYPES : Array(task_types).reject(&:blank?)
      scoped_tasks = all_tasks.select { |t| matches_project_and_type?(t, project, selected_types) }
      self.summary = compute_summary(scoped_tasks)

      display_project_names = project.presence ? [ project ] : project_names
      filtered = filter_tasks(all_tasks, project, selected_types, scope, incomplete_only)
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

    # 任務是否逾期：ProjectTaskBlueprint 的 :overdue 欄位、依專案彙總摘要的逾期計數、
    # 依逾期優先排序皆需要同一份判斷邏輯，故公開讓 Blueprint 也能呼叫（Blueprint 渲染每次
    # request 都會重新執行，不受 ProjectProgressSheetsClient 的原始列快取影響，「今天」一律
    # 是呼叫當下的日期，不會被快取凍結在舊的時間點）。
    def self.overdue?(task)
      return false if COMPLETED_STATUSES.include?(task[:status])

      date = parse_date(task[:planned_completion_date])
      date && date < Date.current
    end

    def self.parse_date(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
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

        delay_raw = values[6]
        delay_value =
          if delay_raw.nil? || delay_raw.to_s.strip.empty?
            nil
          else
            begin
              Integer(delay_raw, 10)
            rescue ArgumentError, TypeError
              delay_raw
            end
          end

        COLUMN_KEYS.zip(values[0, 6] + [ delay_value, values[7] ]).to_h
      end
    end

    def normalize_record(record)
      record.merge(
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

    # 缺少必要欄位（project_name／task_name／status／owner 任一）的列會被跳過，
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

    def matches_project_and_type?(task, selected_project, selected_types)
      return false if selected_project.present? && task[:project_name] != selected_project
      return false if selected_types.any? && !selected_types.include?(task[:task_type])

      true
    end

    def filter_tasks(tasks, selected_project, selected_types, selected_scope, incomplete_only_flag)
      week_range = self.class.week_range(Date.current)

      tasks.select do |t|
        next false unless matches_project_and_type?(t, selected_project, selected_types)
        next false if incomplete_only_flag && COMPLETED_STATUSES.include?(t[:status])
        next false if selected_scope == "overdue" && !self.class.overdue?(t)
        next false if selected_scope == "due_this_week" && !due_by_this_week_end?(t, week_range)

        true
      end
    end

    # 本週到期＝不晚於本週週日，不限下界，涵蓋所有已逾期任務（不論逾期發生於本週內或更早）。
    def due_by_this_week_end?(task, week_range)
      return false if COMPLETED_STATUSES.include?(task[:status])

      date = self.class.parse_date(task[:planned_completion_date])
      date && date <= week_range.last
    end

    def compute_summary(tasks)
      completed = tasks.count { |t| COMPLETED_STATUSES.include?(t[:status]) }
      {
        total: tasks.size,
        completed: completed,
        incomplete: tasks.size - completed,
        overdue: tasks.count { |t| self.class.overdue?(t) }
      }
    end

    def sort_overdue_first(tasks)
      tasks.sort_by { |t| self.class.overdue?(t) ? 0 : 1 }
    end
  end
end
