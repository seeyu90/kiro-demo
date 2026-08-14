# frozen_string_literal: true

module Sheets
  class FetchProjectProgress < ApplicationActor
    input :force, default: false
    output :grouped_data
    output :failure_code
    output :message
    output :fetched_at

    COLUMN_KEYS = %i[
      project_name task_name status owner
      planned_completion_date actual_completion_date delay_days task_type
    ].freeze

    REQUIRED_KEYS = %i[project_name task_name status owner].freeze

    def call
      rows = ProjectProgressSheetsClient.fetch_rows(force: force)
      records = parse_rows(rows)
      normalized = records.map { |record| normalize_record(record) }
      valid_records = reject_invalid_records(normalized)
      self.grouped_data = group_by_project(valid_records)
      self.fetched_at = ProjectProgressSheetsClient.fetched_at
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

    private

    def parse_rows(rows)
      return [] if rows.nil? || rows.empty?

      rows[1..].filter_map do |row|
        next if row.nil? || (!row.empty? && row.all? { |cell| cell.to_s.strip.empty? })

        padded = row + [nil] * [0, 8 - row.length].max
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

        COLUMN_KEYS.zip(values[0, 6] + [delay_value, values[7]]).to_h
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
  end
end
