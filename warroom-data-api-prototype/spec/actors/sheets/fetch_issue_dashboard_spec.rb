# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sheets::FetchIssueDashboard do
  let(:actor) { described_class.new(ServiceActor::Result.to_result({})) }

  describe "#parse_month_kpi" do
    let(:header) { %w[year_month 客訴 測試 總Bug 攔截率 完成數 未結案 平均天數 SLA達標率 Top3] }

    it "maps columns to the expected keys, ignoring the Top3 column" do
      rows = [
        header,
        [ "2026-08", "15", "9", "24", "37.5", "6", "3", "3.1", "25", "王贊勛:8 | 黃靖益:5" ]
      ]

      result = actor.send(:parse_month_kpi, rows)

      expect(result).to eq([
        {
          year_month: "2026-08",
          complaint: 15,
          testing: 9,
          total_bug: 24,
          block_rate: 37.5,
          completed: 6,
          unresolved: 3,
          avg_days: 3.1,
          sla_rate: 25.0
        }
      ])
    end

    it "does not include a :top3 key in the output" do
      rows = [ header, [ "2026-08", "15", "9", "24", "37.5", "6", "3", "3.1", "25", "王贊勛:8" ] ]

      result = actor.send(:parse_month_kpi, rows)

      expect(result.first.keys).not_to include(:top3)
    end

    it "skips blank rows" do
      rows = [
        header,
        [ "2026-08", "15", "9", "24", "37.5", "6", "3", "3.1", "25", "王贊勛:8" ],
        [],
        [ nil, nil, nil, nil, nil, nil, nil, nil, nil, nil ],
        [ "", "", "", "", "", "", "", "", "", "" ]
      ]

      result = actor.send(:parse_month_kpi, rows)

      expect(result.size).to eq(1)
    end

    it "skips a row whose year_month is blank" do
      rows = [ header, [ "", "15", "9", "24", "37.5", "6", "3", "3.1", "25", "" ] ]

      expect(actor.send(:parse_month_kpi, rows)).to eq([])
    end

    it "keeps a non-numeric value as-is instead of raising" do
      rows = [ header, [ "2026-08", "TBD", "9", "24", "37.5", "6", "3", "3.1", "25", "" ] ]

      result = actor.send(:parse_month_kpi, rows)

      expect(result.first[:complaint]).to eq("TBD")
    end

    it "returns an empty array for nil or header-only input" do
      expect(actor.send(:parse_month_kpi, nil)).to eq([])
      expect(actor.send(:parse_month_kpi, [ header ])).to eq([])
    end
  end

  describe "#parse_daily_kpi" do
    let(:header) { %w[日期 客訴 測試 其他 總計] }

    it "maps columns to the expected keys" do
      rows = [ header, [ "2026-08-13", "0", "1", "0", "1" ] ]

      result = actor.send(:parse_daily_kpi, rows)

      expect(result).to eq([
        { date: "2026-08-13", complaint: 0, testing: 1, other: 0, total: 1 }
      ])
    end

    it "treats an empty total as 0 instead of nil" do
      rows = [ header, [ "2026-08-13", "0", "0", "0", "" ] ]

      result = actor.send(:parse_daily_kpi, rows)

      expect(result.first[:total]).to eq(0)
    end

    it "sorts records by date ascending regardless of source order" do
      rows = [
        header,
        [ "2026-08-13", "0", "0", "0", "0" ],
        [ "2026-08-01", "1", "0", "0", "1" ],
        [ "2026-08-06", "0", "2", "0", "2" ]
      ]

      result = actor.send(:parse_daily_kpi, rows)

      expect(result.map { |r| r[:date] }).to eq([ "2026-08-01", "2026-08-06", "2026-08-13" ])
    end

    it "skips blank rows" do
      rows = [ header, [ "2026-08-13", "0", "0", "0", "0" ], [], [ nil, nil, nil, nil, nil ] ]

      result = actor.send(:parse_daily_kpi, rows)

      expect(result.size).to eq(1)
    end

    it "skips a row whose date is blank" do
      rows = [ header, [ "", "0", "0", "0", "0" ] ]

      expect(actor.send(:parse_daily_kpi, rows)).to eq([])
    end

    it "returns an empty array for nil or header-only input" do
      expect(actor.send(:parse_daily_kpi, nil)).to eq([])
      expect(actor.send(:parse_daily_kpi, [ header ])).to eq([])
    end
  end

  describe "#parse_issues" do
    let(:header) do
      %w[issue_id subject type tracker status assigned_to start_date due_date work_days sheet_name project total_hours]
    end

    it "maps columns to the expected keys, dropping sheet_name" do
      rows = [
        header,
        [ "4547", "未匯入行事曆", "Complaint", "臭蟲", "已結束", "黃靖益",
         "2026/1/2", "2026/1/6", "3", "raw_2026", "Virtuous HRM", "0.75" ]
      ]

      result = actor.send(:parse_issues, rows)

      expect(result).to eq([
        {
          issue_id: "4547", subject: "未匯入行事曆", type: "Complaint", tracker: "臭蟲",
          status: "已結束", assigned_to: "黃靖益", start_date: "2026-01-02", due_date: "2026-01-06",
          work_days: 3, project: "Virtuous HRM", total_hours: 0.75
        }
      ])
      expect(result.first.keys).not_to include(:sheet_name)
    end

    it "converts a valid total_hours string to Float" do
      rows = [ header, [ "1", "s", "Complaint", "臭蟲", "已結束", "x", "", "", "", "raw_2026", "P", "8.25" ] ]

      expect(actor.send(:parse_issues, rows).first[:total_hours]).to eq(8.25)
    end

    it "leaves total_hours nil when the source cell is empty or the column is missing" do
      rows = [ header, [ "1", "s", "Complaint", "臭蟲", "已結束", "x", "", "", "", "raw_2026", "P", "" ] ]

      expect(actor.send(:parse_issues, rows).first[:total_hours]).to be_nil
    end

    it "strips thousands-separator commas from total_hours before parsing (FORMATTED_VALUE may format large numbers as e.g. \"1,200\")" do
      rows = [ header, [ "1", "s", "Complaint", "臭蟲", "已結束", "x", "", "", "", "raw_2026", "P", "1,200.5" ] ]

      expect(actor.send(:parse_issues, rows).first[:total_hours]).to eq(1200.5)
    end

    it "normalizes start_date and due_date to ISO 8601" do
      rows = [ header, [ "1", "s", "Complaint", "臭蟲", "已結束", "x", "2026/8/1", "2026-08-02", "", "raw_2026", "P" ] ]

      result = actor.send(:parse_issues, rows)

      expect(result.first[:start_date]).to eq("2026-08-01")
      expect(result.first[:due_date]).to eq("2026-08-02")
    end

    it "leaves start_date/due_date nil when the source cell is empty" do
      rows = [ header, [ "1", "s", "Complaint", "臭蟲", "已結束", "x", "", nil, "", "raw_2026", "P" ] ]

      result = actor.send(:parse_issues, rows)

      expect(result.first[:start_date]).to be_nil
      expect(result.first[:due_date]).to be_nil
    end

    it "converts a valid work_days string to Integer" do
      rows = [ header, [ "1", "s", "Complaint", "臭蟲", "已結束", "x", "", "", "108", "raw_2026", "P" ] ]

      expect(actor.send(:parse_issues, rows).first[:work_days]).to eq(108)
    end

    it "keeps a non-numeric work_days value as-is instead of raising" do
      rows = [ header, [ "1", "s", "Complaint", "臭蟲", "已結束", "x", "", "", "TBD", "raw_2026", "P" ] ]

      expect(actor.send(:parse_issues, rows).first[:work_days]).to eq("TBD")
    end

    it "leaves work_days nil when the source cell is empty" do
      rows = [ header, [ "1", "s", "Complaint", "臭蟲", "已結束", "x", "", "", "", "raw_2026", "P" ] ]

      expect(actor.send(:parse_issues, rows).first[:work_days]).to be_nil
    end

    it "skips a row when issue_id is blank" do
      rows = [ header, [ "", "s", "Complaint", "臭蟲", "已結束", "x", "", "", "", "raw_2026", "P" ] ]

      expect(actor.send(:parse_issues, rows)).to eq([])
    end

    it "skips a row when subject is blank" do
      rows = [ header, [ "1", "", "Complaint", "臭蟲", "已結束", "x", "", "", "", "raw_2026", "P" ] ]

      expect(actor.send(:parse_issues, rows)).to eq([])
    end

    it "skips a row when status is blank, keeping other valid rows" do
      rows = [
        header,
        [ "1", "s", "Complaint", "臭蟲", "", "x", "", "", "", "raw_2026", "P" ],
        [ "2", "s2", "TestingBug", "臭蟲", "新建立", "y", "", "", "", "raw_2026", "P" ]
      ]

      result = actor.send(:parse_issues, rows)

      expect(result.map { |r| r[:issue_id] }).to eq([ "2" ])
    end

    it "skips blank rows" do
      rows = [
        header,
        [ "1", "s", "Complaint", "臭蟲", "已結束", "x", "", "", "", "raw_2026", "P" ],
        [],
        Array.new(11)
      ]

      expect(actor.send(:parse_issues, rows).size).to eq(1)
    end

    it "returns an empty array for nil or header-only input" do
      expect(actor.send(:parse_issues, nil)).to eq([])
      expect(actor.send(:parse_issues, [ header ])).to eq([])
    end

    it "skips a row whose tracker is 測試 (test-only issue, not a real quality defect), keeping other valid rows" do
      rows = [
        header,
        [ "1", "s", "TestingBug", "測試", "新建立", "x", "", "", "", "raw_2026", "P" ],
        [ "2", "s2", "TestingBug", "臭蟲", "新建立", "y", "", "", "", "raw_2026", "P" ]
      ]

      result = actor.send(:parse_issues, rows)

      expect(result.map { |r| r[:issue_id] }).to eq([ "2" ])
    end
  end

  describe "#compute_project_breakdown" do
    it "groups by project and counts complaint/testing/other, with total as their sum" do
      issues = [
        { project: "A", type: "Complaint" },
        { project: "A", type: "Complaint" },
        { project: "A", type: "TestingBug" },
        { project: "B", type: "Other" },
        { project: "B", type: "SomethingElse" }
      ]

      result = actor.send(:compute_project_breakdown, issues)

      expect(result).to contain_exactly(
        { project: "A", complaint: 2, testing: 1, other: 0, total: 3 },
        { project: "B", complaint: 0, testing: 0, other: 2, total: 2 }
      )
    end

    it "groups issues with a blank project under 未分類" do
      issues = [ { project: "", type: "Complaint" }, { project: nil, type: "TestingBug" } ]

      result = actor.send(:compute_project_breakdown, issues)

      expect(result).to eq([ { project: "未分類", complaint: 1, testing: 1, other: 0, total: 2 } ])
    end

    it "returns an empty array for an empty issues list" do
      expect(actor.send(:compute_project_breakdown, [])).to eq([])
    end
  end

  describe "#call" do
    subject(:result) { described_class.result }

    let(:month_kpi_rows) do
      [
        %w[year_month 客訴 測試 總Bug 攔截率 完成數 未結案 平均天數 SLA達標率 Top3],
        [ "2026-08", "15", "9", "24", "37.5", "6", "3", "3.1", "25", "王贊勛:8" ]
      ]
    end

    let(:daily_kpi_rows) do
      [
        %w[日期 客訴 測試 其他 總計],
        [ "2026-08-13", "0", "1", "0", "1" ]
      ]
    end

    let(:issue_rows) do
      [
        %w[issue_id subject type tracker status assigned_to start_date due_date work_days sheet_name project total_hours],
        [ "4547", "未匯入行事曆", "Complaint", "臭蟲", "已結束", "黃靖益",
         "2026/1/2", "2026/1/6", "3", "raw_2026", "Virtuous HRM" ],
        [ "5165", "白名單申請時間錯誤", "TestingBug", "臭蟲", "新建立", "蔡秉逸",
         "2026/8/12", "", "", "raw_2026", "Virtuous HRM" ]
      ]
    end

    before do
      allow(IssueSheetsClient).to receive(:fetch_month_kpi_rows).and_return(month_kpi_rows)
      allow(IssueSheetsClient).to receive(:fetch_daily_kpi_rows).and_return(daily_kpi_rows)
      allow(IssueSheetsClient).to receive(:fetch_issue_rows).and_return(issue_rows)
    end

    it "populates month_kpi and daily_kpi outputs from the client's rows" do
      expect(result.month_kpi).to eq([
        {
          year_month: "2026-08", complaint: 15, testing: 9, total_bug: 24, block_rate: 37.5,
          completed: 6, unresolved: 3, avg_days: 3.1, sla_rate: 25.0
        }
      ])
      expect(result.daily_kpi).to eq([
        { date: "2026-08-13", complaint: 0, testing: 1, other: 0, total: 1 }
      ])
    end

    it "populates issues from the client's rows" do
      expect(result.issues.map { |i| i[:issue_id] }).to eq([ "4547", "5165" ])
    end

    it "populates project_breakdown derived from issues" do
      expect(result.project_breakdown).to eq([
        { project: "Virtuous HRM", complaint: 1, testing: 1, other: 0, total: 2 }
      ])
    end

    # 原本沒有排序，是掃描 raw_2023～raw_2027 分頁時每個專案第一次出現的巧合順序，跟字母／
    # 注音都無關。改依字母排序（大小寫不分），使用者才看得出規則、找得到想找的專案。
    context "projects ordering" do
      let(:issue_rows) do
        [
          %w[issue_id subject type tracker status assigned_to start_date due_date work_days sheet_name project],
          [ "9001", "s1", "Complaint", "臭蟲", "新建立", "A", "2026/1/1", "", "", "raw_2026", "zeta" ],
          [ "9002", "s2", "Complaint", "臭蟲", "新建立", "A", "2026/1/2", "", "", "raw_2026", "Alpha" ],
          [ "9003", "s3", "Complaint", "臭蟲", "新建立", "A", "2026/1/3", "", "", "raw_2026", "beta" ]
        ]
      end

      it "sorts projects alphabetically, case-insensitive, not by first-appearance order" do
        expect(result.projects).to eq(%w[Alpha beta zeta])
      end
    end

    # available_months 改依 issues 的 start_date 算（不再受限於 month_kpi 的涵蓋範圍），
    # 但 start_date 若正規化失敗會保留原始字串（見 normalize_date），slice(0,7) 可能切出
    # 「形狀像月份、實際上不是合法日期」的字串（例如月份打錯的 "2026-13-05"）。
    # IssuesHelper#available_month_bounds 會拿 available_months 的第一筆／最後一筆做
    # Date.parse，混進不合法字串會讓整個 /issues 頁面 500，故這裡要先過濾掉。
    context "available_months filters out unparseable year-month strings" do
      let(:issue_rows) do
        [
          %w[issue_id subject type tracker status assigned_to start_date due_date work_days sheet_name project],
          [ "9001", "合法日期", "Complaint", "臭蟲", "新建立", "A", "2026/8/1", "", "", "raw_2026", "P" ],
          [ "9002", "月份打錯", "Complaint", "臭蟲", "新建立", "A", "2026/13/5", "", "", "raw_2026", "P" ]
        ]
      end

      it "excludes the malformed month (2026-13) but keeps the valid one (2026-08)" do
        expect(result.available_months).to include("2026-08")
        expect(result.available_months).not_to include("2026-13")
      end
    end

    # 所有欄位現在全部即時從 issues 算（見 Sheets::FetchIssueDashboard#compute_month_kpi），
    # 不再讀 month_kpi 表，故這裡的 month_kpi_rows 刻意留著跟下面算出來的數字不同，藉此確認
    # selected_month_record 真的是即時算出來的，不是抄 sheet。公式細節（完成數只認「已解決」、
    # 未結案＝客訴總數－完成數、平均天數與SLA達標率只以「客訴」為分母）照抄／改編自實際產生
    # month_kpi 表的 n8n 腳本（使用者提供原始碼）。狀態刻意不用「未完成」這種字面上包含
    # 「完成」二字的值——ISSUE_DONE_STATUS_PATTERN 是子字串比對，「未完成」會被誤判為已完成
    # 狀態，而這不是真實試算表會出現的值（實測過的真實狀態只有已結束／已解決／已測試／
    # 新建立／已暫停／已拒絕／待測試），用它當測試資料反而測不出真正的行為。
    describe "from/to date range filtering" do
      let(:month_kpi_rows) do
        [
          %w[year_month 客訴 測試 總Bug 攔截率 完成數 未結案 平均天數 SLA達標率 Top3],
          [ "2026-07", "999", "999", "999", "99", "999", "999", "9.99", "99", "" ],
          [ "2026-08", "999", "999", "999", "99", "999", "999", "9.99", "99", "" ]
        ]
      end

      # 7 月：C1（Complaint／已解決／work_days=1）、C2（Complaint／已結束／work_days=3）、
      # T1（TestingBug／新建立）。
      # 8 月：C3（Complaint／新建立，尚未結案且無到期日／work_days=2）、C4（Complaint／
      # 已解決／work_days=1）、T2（TestingBug／實作中）、T3（TestingBug／已結束）。
      let(:issue_rows) do
        [
          %w[issue_id subject type tracker status assigned_to start_date due_date work_days sheet_name project total_hours],
          [ "1001", "C1", "Complaint", "臭蟲", "已解決", "A", "2026/7/5", "", "1", "raw_2026", "P", "2" ],
          [ "1002", "C2", "Complaint", "臭蟲", "已結束", "A", "2026/7/10", "", "3", "raw_2026", "P", "1.5" ],
          [ "1003", "T1", "TestingBug", "臭蟲", "新建立", "A", "2026/7/15", "", "", "raw_2026", "P", "0.5" ],
          [ "1004", "C3", "Complaint", "臭蟲", "新建立", "A", "2026/8/5", "", "2", "raw_2026", "P", "1" ],
          [ "1005", "C4", "Complaint", "臭蟲", "已解決", "A", "2026/8/10", "", "1", "raw_2026", "P", "0.75" ],
          [ "1006", "T2", "TestingBug", "臭蟲", "實作中", "A", "2026/8/12", "", "", "raw_2026", "P", "0" ],
          [ "1007", "T3", "TestingBug", "臭蟲", "已結束", "A", "2026/8/20", "", "", "raw_2026", "P", "3" ]
        ]
      end

      around { |example| travel_to(Date.new(2026, 8, 19)) { example.run } }

      it "defaults from/to to the current month's bounds, computing every field live from issues (not month_kpi_rows)" do
        expect(result.selected_from).to eq(Date.new(2026, 8, 1))
        expect(result.selected_to).to eq(Date.new(2026, 8, 31))
        # 8 月：C3／C4 客訴、T2／T3 測試；完成數只有 C4（已解決）；未結案＝2－1＝1（C3）；
        # 平均天數＝(2+1)/2；SLA達標率＝work_days<=1 的 C4 一筆 ÷ 2 客訴；遲期客訴：C3
        # 尚未結案（新建立）且無到期日，客訴 SLA 為 2 天，8/5+2=8/7 早於「今天」8/19 → 逾期，
        # C4 已解決不算；總花費工時（不分類型）＝1(C3)+0.75(C4)+0(T2)+3(T3)。
        expect(result.selected_month_record).to eq(
          complaint: 2, testing: 2, other: 0, block_rate: 50.0,
          completed: 1, unresolved: 1, avg_days: 1.5, sla_rate: 50.0,
          overdue_complaints: 1, total_hours_sum: 4.75
        )
      end

      it "computes a different set of numbers for a different single month" do
        result = described_class.result(from: Date.new(2026, 7, 1), to: Date.new(2026, 7, 31))

        # 7 月：C1／C2 客訴、T1 測試；完成數只有 C1（已解決，C2 是已結束不算）；未結案＝
        # 2－1＝1；平均天數＝(1+3)/2；SLA達標率＝work_days<=1 的 C1 一筆 ÷ 2 客訴；本月遲期
        # 客訴：C1／C2 皆已完成（廣義 done? 判斷含「已解決」「已結束」），沒有尚未結案的客訴
        # 可能逾期，故為 0；總花費工時＝2(C1)+1.5(C2)+0.5(T1)。
        expect(result.selected_month_record).to eq(
          complaint: 2, testing: 1, other: 0, block_rate: 33.33,
          completed: 1, unresolved: 1, avg_days: 2.0, sla_rate: 50.0,
          overdue_complaints: 0, total_hours_sum: 4.0
        )
      end

      it "recomputes over the full combined range when it spans multiple months (no month_kpi_rows aggregation)" do
        result = described_class.result(from: Date.new(2026, 7, 1), to: Date.new(2026, 8, 31))

        # 7+8 月合計：4 客訴（C1～C4）、3 測試（T1～T3）；完成數 C1＋C4＝2；未結案＝4－2＝2；
        # 平均天數＝(1+3+2+1)/4；SLA達標率＝ work_days<=1 的 C1／C4 兩筆 ÷ 4 客訴；本月遲期
        # 客訴＝1（仍只有 C3）；總花費工時＝4.0（7月）+4.75（8月）。
        expect(result.selected_month_record).to eq(
          complaint: 4, testing: 3, other: 0, block_rate: 42.86,
          completed: 2, unresolved: 2, avg_days: 1.75, sla_rate: 50.0,
          overdue_complaints: 1, total_hours_sum: 8.75
        )
      end

      it "returns nil for the ratio fields (not 0) when the range has no complaints at all" do
        result = described_class.result(from: Date.new(2025, 1, 1), to: Date.new(2025, 1, 31))

        expect(result.selected_month_record).to eq(
          complaint: 0, testing: 0, other: 0, block_rate: nil,
          completed: 0, unresolved: 0, avg_days: nil, sla_rate: nil,
          overdue_complaints: 0, total_hours_sum: 0
        )
      end

      it "only applies the given bound when the other is absent (open-ended range)" do
        result = described_class.result(from: Date.new(2026, 8, 1), to: nil)

        expect(result.selected_month_record).to include(complaint: 2, testing: 2)
      end
    end

    # 每日趨勢圖用陣列索引決定 X 軸間距，不是依日期本身的間隔（見 IssuesHelper#trend_chart_points）。
    # daily_kpi 分頁本身沒有假日的列（一年約 185 列對應約 260 個平日），若直接拿「有資料的日子」
    # 當資料點，週末造成的空隙跟平日的 1 天間距在圖上會畫成一樣寬，時間軸因此失真。
    describe "daily_kpi_for_range fills gaps so the trend chart's X axis matches real calendar days" do
      let(:daily_kpi_rows) do
        [
          %w[日期 客訴 測試 其他 總計],
          # 8/3（一）有資料，8/4～8/7（週末＋兩個平日）完全沒有列，8/10（一）才又有資料，
          # 模擬業務不在假日回報、平日偶爾也沒紀錄的真實情形。
          [ "2026-08-03", "1", "0", "0", "1" ],
          [ "2026-08-10", "0", "1", "0", "1" ]
        ]
      end

      it "fills missing calendar days within the range with zero-count records" do
        result = described_class.result(from: Date.new(2026, 8, 1), to: Date.new(2026, 8, 10))

        expect(result.daily_kpi_for_range.map { |d| d[:date] }).to eq(
          (Date.new(2026, 8, 1)..Date.new(2026, 8, 10)).map(&:iso8601)
        )
        expect(result.daily_kpi_for_range.find { |d| d[:date] == "2026-08-05" })
          .to eq(date: "2026-08-05", complaint: 0, testing: 0, other: 0, total: 0)
        expect(result.daily_kpi_for_range.find { |d| d[:date] == "2026-08-03" }[:complaint]).to eq(1)
      end

      it "caps the filled range at today, not the full selected range, when the range extends into the future" do
        travel_to(Date.new(2026, 8, 5)) do
          result = described_class.result(from: Date.new(2026, 8, 1), to: Date.new(2026, 8, 31))

          expect(result.daily_kpi_for_range.last[:date]).to eq("2026-08-05")
        end
      end

      it "does not fill gaps for an open-ended range (only one bound given)" do
        result = described_class.result(from: Date.new(2026, 8, 1), to: nil)

        expect(result.daily_kpi_for_range.map { |d| d[:date] }).to eq([ "2026-08-03", "2026-08-10" ])
      end
    end

    # status 傳空陣列（不是 nil）：nil 代表「controller 完全沒收到 status query param」，
    # 會套用 DEFAULT_STATUSES（只顯示「新建立」），空陣列則代表「使用者主動送出表單、
    # 全部取消勾選」，視為不篩選狀態——這裡的 fixture 混雜「處理中」「新建立」「已確認」
    # 三種狀態，要用空陣列才測得出「不篩選」的效果，傳 nil 會被誤篩成只剩「新建立」兩筆。
    describe "q/type filters and issue_kpis" do
      let(:issue_rows) do
        [
          %w[issue_id subject type tracker status assigned_to start_date due_date work_days sheet_name project total_hours],
          [ "1001", "客訴逾期未結", "Complaint", "臭蟲", "處理中", "王贊勛",
            "2026/8/1", "2026/8/10", "", "raw_2026", "P1", "2" ],
          [ "1002", "測試無到期日", "TestingBug", "臭蟲", "新建立", "蔡秉逸",
            "2026/8/12", "", "", "raw_2026", "P1", "0.5" ],
          [ "1003", "已完成客訴", "Complaint", "臭蟲", "已確認", "黃靖益",
            "2026/7/1", "2026/7/5", "", "raw_2026", "P1", "1.25" ],
          [ "1004", "類型欄空白", "", "臭蟲", "新建立", "陳謹皓",
            "2026/8/3", "", "", "raw_2026", "P1", "0" ],
          [ "1005", "類型欄寫Other", "Other", "臭蟲", "新建立", "陳謹皓",
            "2026/8/4", "", "", "raw_2026", "P1", "0" ]
        ]
      end

      around { |example| travel_to(Date.new(2026, 8, 19)) { example.run } }

      it "filters filtered_issues by q, case-insensitive, matching subject/issue_id/assigned_to" do
        result = described_class.result(status: [], q: "王贊勛")

        expect(result.filtered_issues.map { |i| i[:issue_id] }).to eq([ "1001" ])
      end

      it "filters filtered_issues by exact type match" do
        result = described_class.result(status: [], type: "Complaint")

        # 依議題編號降冪排序（見下面的排序測試），1003 排在 1001 前面。
        expect(result.filtered_issues.map { |i| i[:issue_id] }).to eq([ "1003", "1001" ])
      end

      # 原始順序是 raw_2023～raw_2027 分頁依序串接，等於「最舊的排最前面」；改為依議題編號
      # 降冪，數字比較（不是字串比較，字串排序會把 "999" 排在 "1002" 後面）。
      it "sorts filtered_issues by issue_id descending (newest first), not sheet-concatenation order" do
        result = described_class.result(status: [])

        expect(result.filtered_issues.map { |i| i[:issue_id] }).to eq(%w[1005 1004 1003 1002 1001])
      end

      # 類型篩選下拉的「其他」選項要同時比對到「類型欄位真的空白」跟「類型欄位寫著 Other」
      # 這兩種原始值——對使用者來說兩者是同一件事，篩選時不該分開（見 issue_type_category）。
      it "matches both a blank type and a literal Other value when filtering by the Other category" do
        result = described_class.result(status: [], type: "Other")

        expect(result.filtered_issues.map { |i| i[:issue_id] }).to eq([ "1005", "1004" ])
      end

      it "exposes the fixed 3-category list as types, not whatever raw values happen to be in the data" do
        result = described_class.result(status: [])

        expect(result.types).to eq(%w[Complaint TestingBug Other])
      end

      it "computes issue_kpis from the filtered (not paginated) issue set, excluding done issues" do
        result = described_class.result(status: [])

        # 1001（處理中、客訴、已逾期）／1002（新建立、測試、無到期日）／1004／1005（新建立、
        # 類型空白或 Other、無到期日）都算 pending；1003（已確認）已完成，數字都不算它，
        # 但 total_hours_sum 不分完成與否，五筆的花費工時（2 + 0.5 + 1.25 + 0 + 0）都要加總。
        expect(result.issue_kpis).to eq(
          pending: 4, urgent_complaints: 1, total_hours_sum: 3.75
        )
      end
    end

    describe "issue_kpis SLA fallback when due_date is blank (客訴兩天內要完成／測試當天要完成)" do
      let(:issue_rows) do
        [
          %w[issue_id subject type tracker status assigned_to start_date due_date work_days sheet_name project total_hours],
          # 客訴，開始於「今天」，尚在 2 天 SLA 內 → 不算逾期
          [ "2001", "今天回報的客訴", "Complaint", "臭蟲", "處理中", "x", "2026/8/19", "", "", "raw_2026", "P", "1" ],
          # 客訴，開始於 4 天前，超過 2 天 SLA → 算逾期（也算緊急客訴）
          [ "2002", "四天前的客訴", "Complaint", "臭蟲", "處理中", "x", "2026/8/15", "", "", "raw_2026", "P", "2" ],
          # 測試（個人責任），開始於「今天」，尚在當天 SLA 內 → 不算逾期
          [ "2003", "今天開的測試", "TestingBug", "臭蟲", "新建立", "x", "2026/8/19", "", "", "raw_2026", "P", "3" ],
          # 測試（個人責任），開始於昨天，超過當天 SLA → 算逾期（但不是客訴，不算緊急客訴）
          [ "2004", "昨天開的測試", "TestingBug", "臭蟲", "新建立", "x", "2026/8/18", "", "", "raw_2026", "P", "4" ],
          # Other 類型沒有對應 SLA，即使開很久也不算逾期
          [ "2005", "其他類型舊議題", "Other", "臭蟲", "新建立", "x", "2026/1/1", "", "", "raw_2026", "P", "5" ]
        ]
      end

      around { |example| travel_to(Date.new(2026, 8, 19)) { example.run } }

      it "only counts a Complaint issue past its implicit SLA deadline as urgent when due_date is blank" do
        result = described_class.result(status: [])

        # 2002 客訴逾期 → urgent_complaints；2004 測試逾期但不是客訴，不算緊急客訴。
        expect(result.issue_kpis).to eq(
          pending: 5, urgent_complaints: 1, total_hours_sum: 15.0
        )
      end
    end

    context "when IssueSheetsClient raises Google::Apis::ClientError status 404" do
      before do
        error = Google::Apis::ClientError.new("Not Found")
        allow(error).to receive(:status_code).and_return(404)
        allow(IssueSheetsClient).to receive(:fetch_month_kpi_rows).and_raise(error)
      end

      it "returns failure_code: :sheet_not_found" do
        expect(result).not_to be_success
        expect(result.failure_code).to eq(:sheet_not_found)
        expect(result.message).to include("找不到指定分頁或試算表")
      end
    end

    context "when IssueSheetsClient raises Google::Apis::ClientError with 'Unable to parse range'" do
      before do
        error = Google::Apis::ClientError.new("Unable to parse range: raw_2099!A:K")
        allow(error).to receive(:status_code).and_return(400)
        allow(IssueSheetsClient).to receive(:fetch_issue_rows).and_raise(error)
      end

      it "returns failure_code: :sheet_not_found" do
        expect(result).not_to be_success
        expect(result.failure_code).to eq(:sheet_not_found)
      end
    end

    context "when IssueSheetsClient raises Google::Apis::ClientError status 403" do
      before do
        error = Google::Apis::ClientError.new("Forbidden")
        allow(error).to receive(:status_code).and_return(403)
        allow(IssueSheetsClient).to receive(:fetch_daily_kpi_rows).and_raise(error)
      end

      it "returns failure_code: :access_denied" do
        expect(result).not_to be_success
        expect(result.failure_code).to eq(:access_denied)
        expect(result.message).to include("資料來源存取權限不足")
      end
    end

    context "when IssueSheetsClient raises Google::Apis::ClientError with another status code" do
      before do
        error = Google::Apis::ClientError.new("Bad Request")
        allow(error).to receive(:status_code).and_return(400)
        allow(IssueSheetsClient).to receive(:fetch_issue_rows).and_raise(error)
      end

      it "returns failure_code: :internal_error" do
        expect(result).not_to be_success
        expect(result.failure_code).to eq(:internal_error)
        expect(result.message).to include("Google Sheets API 錯誤")
      end
    end

    context "when IssueSheetsClient raises a StandardError (e.g. missing credentials)" do
      before do
        allow(IssueSheetsClient).to receive(:fetch_month_kpi_rows)
          .and_raise(StandardError.new("找不到 Google Service Account 憑證"))
      end

      it "returns failure_code: :internal_error" do
        expect(result).not_to be_success
        expect(result.failure_code).to eq(:internal_error)
        expect(result.message).to include("未預期的內部錯誤")
      end
    end

    context "when Google::Apis::RateLimitError is raised" do
      before do
        allow(IssueSheetsClient).to receive(:fetch_daily_kpi_rows)
          .and_raise(Google::Apis::RateLimitError.new("Rate limit exceeded"))
      end

      it "returns failure_code: :internal_error" do
        expect(result).not_to be_success
        expect(result.failure_code).to eq(:internal_error)
      end
    end

    context "when a later fetch fails after earlier ones succeeded" do
      before do
        error = Google::Apis::ClientError.new("Forbidden")
        allow(error).to receive(:status_code).and_return(403)
        allow(IssueSheetsClient).to receive(:fetch_issue_rows).and_raise(error)
      end

      it "fails the whole request rather than a partial success (需求 6.2)" do
        # month_kpi／daily_kpi 已在 fetch_issue_rows 拋出例外前解析完成並賦值給 output，
        # 但 fail! 不會清除先前已設定的 output——真正的「整體失敗」契約在於 result.success?
        # 為 false，呼叫端（IssuesController）依 rails-standards.md 慣例一律先檢查
        # success? 再決定是否使用任何欄位，不會因 month_kpi 有值就誤判為部分成功。
        expect(result).not_to be_success
        expect(result.failure_code).to eq(:access_denied)
        expect(result.issues).to be_nil
        expect(result.project_breakdown).to be_nil
      end
    end
  end
  # 以下三個 class method 是本 Actor 與 Summary::BuildPmWeeklyReport 共用的判斷定義
  # （見 warroom-pm-weekly-report spec 任務 1）；instance 端的 KPI 計算也走同一組方法，
  # 故此處的行為即是 306 頁面 KPI 與 PM 週報週別歸屬的共同契約。
  describe ".done?" do
    it "treats statuses containing 完成/確認/關閉/解決/結束 as done" do
      [ "已完成", "已確認", "已關閉", "已解決", "已結束" ].each do |status|
        expect(described_class.done?({ status: status })).to be(true)
      end
    end

    it "treats 新建立/處理中 as not done" do
      expect(described_class.done?({ status: "新建立" })).to be(false)
      expect(described_class.done?({ status: "處理中" })).to be(false)
      expect(described_class.done?({ status: nil })).to be(false)
    end
  end

  describe ".effective_due_date" do
    it "uses the sheet due date when present, tagged :sheet" do
      issue = { type: "Complaint", start_date: "2026-09-01", due_date: "2026-09-10" }
      expect(described_class.effective_due_date(issue)).to eq([ Date.new(2026, 9, 10), :sheet ])
    end

    it "derives Complaint due dates as start_date + 2 days when the sheet has none, tagged :sla" do
      issue = { type: "Complaint", start_date: "2026-09-01", due_date: nil }
      expect(described_class.effective_due_date(issue)).to eq([ Date.new(2026, 9, 3), :sla ])
    end

    it "derives TestingBug due dates as the start date itself (SLA 0 天)" do
      issue = { type: "TestingBug", start_date: "2026-09-01", due_date: nil }
      expect(described_class.effective_due_date(issue)).to eq([ Date.new(2026, 9, 1), :sla ])
    end

    it "returns [nil, nil] for types without an SLA (Other) and no sheet due date" do
      issue = { type: "Other", start_date: "2026-09-01", due_date: nil }
      expect(described_class.effective_due_date(issue)).to eq([ nil, nil ])
    end

    it "returns [nil, nil] when the type has an SLA but there is no start date to derive from" do
      issue = { type: "Complaint", start_date: nil, due_date: nil }
      expect(described_class.effective_due_date(issue)).to eq([ nil, nil ])
    end

    it "returns [nil, nil] for an unparseable sheet due date rather than falling back to the SLA" do
      # 髒資料不該反而被判成「有到期日」：既有 issue_overdue? 的行為是解析失敗一律不算逾期，
      # 若此處退回 SLA 推算，會讓一筆填了亂碼的客訴突然變成逾期。
      issue = { type: "Complaint", start_date: "2026-09-01", due_date: "未定" }
      expect(described_class.effective_due_date(issue)).to eq([ nil, nil ])
    end
  end

  describe ".overdue?" do
    around { |example| travel_to(Date.new(2026, 9, 15)) { example.run } }

    it "is true when the sheet due date has passed" do
      expect(described_class.overdue?({ type: "Other", due_date: "2026-09-14" })).to be(true)
    end

    it "is false when the sheet due date is today or later" do
      expect(described_class.overdue?({ type: "Other", due_date: "2026-09-15" })).to be(false)
      expect(described_class.overdue?({ type: "Other", due_date: "2026-09-16" })).to be(false)
    end

    it "is true when the SLA-derived due date has passed" do
      issue = { type: "Complaint", start_date: "2026-09-10", due_date: nil }
      expect(described_class.overdue?(issue)).to be(true)
    end

    it "is false when there is no usable due date at all" do
      expect(described_class.overdue?({ type: "Other", start_date: "2026-01-01", due_date: nil })).to be(false)
    end
  end
end
