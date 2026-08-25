# frozen_string_literal: true

module Sheets
  class FetchPhaseTracking < ApplicationActor
    input :year, default: nil
    output :cards
    output :available_years
    output :profiles_unavailable
    output :failure_code
    output :message

    # 保留原本 5 個值：真實資料目前只觀察到 4 個（缺「需求確認」），但這代表目前抽樣剛好沒有
    # 這個階段的紀錄，不代表這個階段不會發生（見 requirements.md 前置條件「已知資料特性」）。
    STAGE_ORDER = %w[需求確認 開案 開發 測試 發布].freeze

    def call
      records = parse_records(PhaseRecordsSheetsClient.fetch_rows)

      profiles_by_project = fetch_profiles_by_project
      self.profiles_unavailable = profiles_by_project.nil?
      profiles_by_project ||= {}

      # 年度下拉選單的選項固定依全部資料算出，不受目前篩選影響（同既有 project_history 慣例）。
      self.available_years = records.filter_map { |r| r[:planned_date].to_s[0, 4].presence }.uniq.sort.reverse

      all_cards = build_cards(records, profiles_by_project)
      self.cards = year.present? ? all_cards.select { |c| c[:record_years].include?(year) } : all_cards
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

    # 欄位：project, issue_id, issue_name, stage, planned_date, actual_date, status, reason,
    # unique_key, sheet_year（已用真實 Sheet 表頭確認，2026-08-25 使用者把原本的 issue 欄拆成
    # issue_id／issue_name 兩欄）。unique_key／sheet_year 不納入解析後形狀：unique_key 並非
    # 真的唯一（代表重排程，見前置條件），sheet_year 部分列為空字串不可靠，兩者都不是本 Actor
    # 需要的欄位。「專案」「議題 ID」欄空白的列整列跳過；「stage」不在 STAGE_ORDER 內的列也
    # 整列跳過並記錄警告。issue_name 目前只在 issue_id 是純 Redmine ID 時才會填，允許空白。
    def parse_records(rows)
      rows.filter_map do |row|
        project, issue_id, issue_name, stage, planned_date, actual_date, status, reason =
          row.values_at(0, 1, 2, 3, 4, 5, 6, 7)
        next if project.to_s.strip.empty? || issue_id.to_s.strip.empty?

        unless STAGE_ORDER.include?(stage)
          Rails.logger.warn("Sheets::FetchPhaseTracking: 跳過不明 stage 值 #{stage.inspect}（#{project}/#{issue_id}）")
          next
        end

        {
          project: project,
          issue_id: issue_id,
          issue_name: issue_name.presence,
          stage: stage,
          planned_date: planned_date.presence,
          actual_date: actual_date.presence,
          status: status.presence,
          reason: reason.presence
        }
      end
    end

    # Roster（客戶/PM 對照）失敗時降級顯示，不擋整頁：階段紀錄才是本頁面的核心資料（比照既有
    # Sheets::FetchProjectHistory 對 Roster 失敗的降級慣例）。找不到就回傳 nil，呼叫端顯示 —。
    # 「專案」分頁的「狀態」欄（維護／…）是專案層級的維運狀態，不是議題狀態，本頁的「狀態」
    # 篩選指的是議題目前所在階段的完成狀態（見 build_card 的 current_issue_status），故不讀
    # 這個 Roster 狀態欄。
    def fetch_profiles_by_project
      rows = ProjectProfilesSheetsClient.fetch_rows
      return {} if rows.nil? || rows.size <= 1

      rows[1..].filter_map do |row|
        code, _redmine, _project303, customer, pm, _maintenance_status = row.values_at(0, 1, 2, 3, 4, 5)
        next if code.to_s.strip.empty?

        [ code, { customer: customer.presence, pm: pm.presence } ]
      end.to_h
    rescue Google::Apis::ClientError
      nil
    end

    # 卡片分組單位是 (project, issue_id)，不是 project：一個 project 代碼底下有多個獨立的
    # issue 生命週期（見 requirements.md 前置條件「卡片分組單位」）。issue_id 是拆分前 issue
    # 欄的直接延續（unique_key 也是用 issue_id 組成，見 PhaseRecordsSheetsClient 附註），
    # issue_name 只是顯示用的人類可讀名稱，不是分組鍵。
    def build_cards(records, profiles_by_project)
      records.group_by { |r| [ r[:project], r[:issue_id] ] }.map do |(project, issue_id), issue_records|
        build_card(project, issue_id, issue_records, profiles_by_project[project] || {})
      end
    end

    # 同一 (project, issue_id, stage) 可能有多筆紀錄（重新排程，非資料錯誤）：全部保留、都要
    # 呈現。原始 Sheet 列出順序較後者視為較新（附加新列，非插入舊列之前），該筆為主要呈現，
    # 其餘為「重排歷史」（呈現規則見 requirements.md 需求 4.5，View 層負責樣式區分，這裡只
    # 負責分組不負責樣式）。
    def build_card(project, issue_id, issue_records, profile)
      stages = STAGE_ORDER.map do |stage_name|
        stage_records = issue_records.select { |r| r[:stage] == stage_name }
        # history 由新到舊排列（reverse）：較新的重排記錄排在較舊的上面，最舊的排在最下面。
        { stage: stage_name, primary: stage_records.last, history: stage_records[0...-1].reverse }
      end

      {
        project: project,
        issue_id: issue_id,
        # 同一 issue_id 底下各列理論上共用同一個 issue_name，仍防禦性地取第一筆非空值。
        issue_name: issue_records.filter_map { |r| r[:issue_name] }.first,
        customer: profile[:customer],
        pm: profile[:pm],
        status: current_issue_status(stages),
        planned_completion_date: planned_completion_date_for(stages),
        stages: stages,
        record_years: issue_records.filter_map { |r| r[:planned_date].to_s[0, 4].presence }.uniq
      }
    end

    # 「狀態」指議題目前所在階段的完成狀態（完成／延誤已完成／延誤未完成／暫緩／未完成），
    # 不是專案層級的維運狀態（見 fetch_profiles_by_project 附註）。取 STAGE_ORDER 由後往前
    # 第一個有主要記錄的階段（即議題目前推進到的最新階段）的 status 欄位；完全沒有任何階段
    # 記錄時回傳 nil。
    def current_issue_status(stages)
      stages.reverse.find { |s| s[:primary] }&.dig(:primary, :status)
    end

    # 沒有獨立的「專案層級預計完成日期」欄位（不像 static prototype 假設的那樣），改用終點
    # 階段（發布）的預計完成日期近似；「發布」缺紀錄時退回所有階段裡最晚的 planned_date，
    # 避免完全沒有排序依據（依預計完成日期排序，需求 4.1）。
    def planned_completion_date_for(stages)
      release_stage = stages.find { |s| s[:stage] == "發布" }
      release_stage&.dig(:primary, :planned_date) ||
        stages.filter_map { |s| s[:primary]&.dig(:planned_date) }.max
    end
  end
end
