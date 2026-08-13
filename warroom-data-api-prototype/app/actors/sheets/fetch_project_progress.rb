# frozen_string_literal: true

module Sheets
  class FetchProjectProgress < ApplicationActor
    input :simulate_error, optional: true, default: nil

    output :grouped_data
    output :failure_code
    output :message

    class ValidationError < StandardError; end

    def call
      if simulate_error
        return fail!(**error_mapping(simulate_error))
      end

      records = MockData::ProjectProgress::RECORDS
      normalized = records.map { |record| normalize_record(record) }
      validate_records!(normalized)

      self.grouped_data = group_by_project(normalized)
    rescue ValidationError => e
      fail!(failure_code: :invalid_data_format, message: e.message)
    end

    private

    def normalize_record(record)
      record.merge(
        planned_completion_date: normalize_date(record[:planned_completion_date]),
        actual_completion_date: normalize_date(record[:actual_completion_date])
      )
    end

    def normalize_date(date_str)
      return nil if date_str.nil? || date_str.empty?

      # Match date patterns: YYYY/M/D, YYYY/MM/DD, YYYY-M-D, YYYY-MM-DD
      match = date_str.match(%r{\A(\d{4})[-/](\d{1,2})[-/](\d{1,2})\z})
      return date_str unless match

      year, month, day = match.captures
      "#{year}-#{month.rjust(2, '0')}-#{day.rjust(2, '0')}"
    end

    def validate_records!(records)
      required = %i[project_name task_name status owner]
      records.each do |record|
        missing = required.select { |key| record[key].to_s.empty? }
        raise ValidationError, "缺少必要欄位：#{missing.join(', ')}" if missing.any?
      end
    end

    def group_by_project(records)
      records.group_by { |record| record[:project_name] }
    end

    def error_mapping(simulate_error)
      case simulate_error
      when :sheet_not_found
        { failure_code: :sheet_not_found, message: "找不到指定分頁（模擬情境）" }
      when :invalid_data_format
        { failure_code: :invalid_data_format, message: "資料格式不符預期（模擬情境）" }
      when :access_denied
        { failure_code: :access_denied, message: "資料來源存取權限不足（模擬情境）" }
      when :internal_error
        { failure_code: :internal_error, message: "未預期的內部錯誤（模擬情境）" }
      else
        { failure_code: :internal_error, message: "未預期的內部錯誤（模擬情境）" }
      end
    end
  end
end
