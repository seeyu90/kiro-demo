# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sheets::FetchProjectBurndown do
  include ActiveSupport::Testing::TimeHelpers

  let(:actor) { described_class.new(ServiceActor::Result.to_result({})) }
  let(:fixed_header) { %w[剩餘人時 專案 議題 人員 議題ID 開案日期 完成日期 狀態 預估人時] }

  before { travel_to(Date.new(2026, 8, 14)) }
  after { travel_back }

  describe "#parse_week_dates" do
    it "infers this year for a recent week column within the 3-day tolerance window" do
      header = fixed_header + [ "08/10" ]

      result = actor.send(:parse_week_dates, header)

      expect(result).to eq([ { index: 9, date: Date.new(2026, 8, 10) } ])
    end

    it "steps back a year for the first column when it would land more than 3 days in the future" do
      travel_back
      travel_to(Date.new(2026, 1, 2))
      header = fixed_header + [ "01/10" ]

      result = actor.send(:parse_week_dates, header)

      expect(result).to eq([ { index: 9, date: Date.new(2025, 1, 10) } ])
    end

    it "keeps this year for the first column within the 3-day tolerance window" do
      travel_back
      travel_to(Date.new(2026, 1, 2))
      header = fixed_header + [ "01/04" ]

      result = actor.send(:parse_week_dates, header)

      expect(result).to eq([ { index: 9, date: Date.new(2026, 1, 4) } ])
    end

    it "decrements the year for a later (earlier-week) column that crosses the year boundary" do
      header = fixed_header + [ "01/05", "12/29" ]

      result = actor.send(:parse_week_dates, header)

      expect(result).to eq([
        { index: 9, date: Date.new(2026, 1, 5) },
        { index: 10, date: Date.new(2025, 12, 29) }
      ])
    end

    it "does not cross years for normal descending same-year weeks" do
      header = fixed_header + [ "08/10", "08/03", "07/27" ]

      result = actor.send(:parse_week_dates, header)

      expect(result.map { |w| w[:date] }).to eq([
        Date.new(2026, 8, 10), Date.new(2026, 8, 3), Date.new(2026, 7, 27)
      ])
    end

    it "skips a column with an impossible date without raising, and without disrupting later columns" do
      header = fixed_header + [ "08/10", "02/30", "07/27" ]

      result = actor.send(:parse_week_dates, header)

      expect(result.map { |w| w[:index] }).to eq([ 9, 11 ])
      expect(result.map { |w| w[:date] }).to eq([ Date.new(2026, 8, 10), Date.new(2026, 7, 27) ])
    end

    it "ignores non MM/DD header cells" do
      header = fixed_header + [ "備註", "08/10" ]

      result = actor.send(:parse_week_dates, header)

      expect(result).to eq([ { index: 10, date: Date.new(2026, 8, 10) } ])
    end

    it "returns an empty array when there are no week columns" do
      expect(actor.send(:parse_week_dates, fixed_header)).to eq([])
    end
  end

  describe "#compute_actual_series" do
    it "subtracts cumulative weekly hours from estimated_hours, oldest week first" do
      sorted = [
        { index: 9, date: Date.new(2026, 8, 3) },
        { index: 8, date: Date.new(2026, 8, 10) }
      ]

      result = actor.send(:compute_actual_series, sorted, [ 4.0, 3.0 ], 10.0)

      expect(result).to eq([
        { date: "2026-08-03", hours: 6.0 },
        { date: "2026-08-10", hours: 3.0 }
      ])
    end

    it "treats blank weekly hours (already normalized to 0.0 by the caller) as no consumption" do
      sorted = [ { index: 8, date: Date.new(2026, 8, 10) } ]

      result = actor.send(:compute_actual_series, sorted, [ 0.0 ], 5.0)

      expect(result).to eq([ { date: "2026-08-10", hours: 5.0 } ])
    end
  end

  describe "#compute_ideal_series" do
    let(:sorted) do
      [
        { index: 9, date: Date.new(2026, 8, 1) },
        { index: 8, date: Date.new(2026, 8, 15) }
      ]
    end

    it "linearly interpolates remaining hours between start_date and due_date" do
      result = actor.send(:compute_ideal_series, sorted, "2026-08-01", "2026-08-31", 30.0)

      # 2026-08-01 是週六，start_date 錨點正規化到當週週一（2026-07-27）後排在最前面；
      # 2026-08-31 本身已是週一，直接當作 due_date 錨點。
      expect(result).to eq([
        { date: "2026-07-27", hours: 30.0 },
        { date: "2026-08-01", hours: 30.0 },
        { date: "2026-08-15", hours: 16.0 },
        { date: "2026-08-31", hours: 0.0 }
      ])
    end

    it "clamps weeks before start_date to the full estimated hours" do
      result = actor.send(:compute_ideal_series, sorted, "2026-08-10", "2026-08-31", 21.0)

      expect(result.first).to eq({ date: "2026-08-01", hours: 21.0 })
    end

    it "clamps weeks after due_date to 0" do
      result = actor.send(:compute_ideal_series, sorted, "2026-07-01", "2026-08-10", 10.0)

      expect(result.last).to eq({ date: "2026-08-15", hours: 0.0 })
    end

    it "appends start_date/due_date anchor points snapped to that week's Monday, so the diagonal always reaches full/zero even beyond the given week columns" do
      # 2026-08-01 是週六，正規化到週一是 2026-07-27；2026-08-31 已經是週一，維持不變。
      result = actor.send(:compute_ideal_series, sorted, "2026-08-01", "2026-08-31", 30.0)

      expect(result.first).to eq({ date: "2026-07-27", hours: 30.0 })
      expect(result.last).to eq({ date: "2026-08-31", hours: 0.0 })
    end

    it "does not duplicate an anchor when a week column already lands exactly on that Monday" do
      sorted_with_monday = [ { index: 8, date: Date.new(2026, 8, 10) } ]
      # start_date 已經是週一（2026-08-10），跟週欄位本身重複，不應該出現兩筆同日期的資料點。
      result = actor.send(:compute_ideal_series, sorted_with_monday, "2026-08-10", "2026-08-31", 21.0)

      expect(result.map { |p| p[:date] }).to eq([ "2026-08-10", "2026-08-31" ])
      expect(result.first[:hours]).to eq(21.0)
    end

    it "lets the due_date anchor win over the ratio-computed value when a week column falls on the same Monday-normalized date but due_date itself isn't a Monday" do
      # start_date=2026-07-06（週一），due_date=2026-08-19（週三，正規化到週一是 2026-08-17）。
      # 週欄位剛好也有 2026-08-17：若沒有優先保留錨點，該點會被算成 estimated_hours*(2/44)
      # ≈ 1.82 而不是保證的 0.0（迴歸測試：修正前 uniq 保留的是 points，不是 anchors）。
      sorted_with_collision = [ { index: 8, date: Date.new(2026, 8, 17) } ]

      result = actor.send(:compute_ideal_series, sorted_with_collision, "2026-07-06", "2026-08-19", 40.0)

      expect(result.find { |p| p[:date] == "2026-08-17" }[:hours]).to eq(0.0)
    end

    it "returns an empty array when start_date is missing" do
      expect(actor.send(:compute_ideal_series, sorted, nil, "2026-08-31", 10.0)).to eq([])
    end

    it "returns an empty array when due_date is missing" do
      expect(actor.send(:compute_ideal_series, sorted, "2026-08-01", nil, 10.0)).to eq([])
    end

    it "returns an empty array when due_date is not after start_date" do
      expect(actor.send(:compute_ideal_series, sorted, "2026-08-10", "2026-08-10", 10.0)).to eq([])
    end
  end

  describe "#parse_issues" do
    let(:header) { fixed_header + [ "08/10", "08/03" ] }

    it "maps fixed columns A~I to the expected keys and computes both series" do
      rows = [ [ "2", "AG 亞炬", "議題A", "王贊勛", "1001", "2026/08/01", "2026/08/15", "執行中", "10", "3", "2" ] ]

      result = actor.send(:parse_issues, rows, actor.send(:parse_week_dates, header))

      expect(result.size).to eq(1)
      issue = result.first
      expect(issue).to include(
        issue_id: "1001", project: "AG 亞炬", issue_title: "議題A", assignees: [ "王贊勛" ],
        start_date: "2026-08-01", due_date: "2026-08-15", status: "in_progress", estimated_hours: 10.0,
        reported_remaining_hours: 2.0
      )
      expect(issue[:actual_series]).to eq([
        { date: "2026-08-03", hours: 8.0 },
        { date: "2026-08-10", hours: 5.0 }
      ])
      expect(issue[:ideal_series]).not_to be_empty
    end

    it "treats a blank weekly cell as 0 hours instead of raising" do
      rows = [ [ "", "P", "T", "A", "1001", "2026/08/01", "2026/08/15", "", "10", "", "2" ] ]

      result = actor.send(:parse_issues, rows, actor.send(:parse_week_dates, header))

      expect(result.first[:actual_series].last[:hours]).to eq(8.0) # 10 - (2+0)
    end

    it "skips a row when project is blank" do
      rows = [ [ "2", "", "T", "A", "1001", "", "", "", "10", "", "" ] ]

      expect(actor.send(:parse_issues, rows, [])).to eq([])
    end

    it "skips a row when issue_title is blank" do
      rows = [ [ "2", "P", "", "A", "1001", "", "", "", "10", "", "" ] ]

      expect(actor.send(:parse_issues, rows, [])).to eq([])
    end

    it "skips a row when issue_id is blank" do
      rows = [ [ "2", "P", "T", "A", "", "", "", "", "10", "", "" ] ]

      expect(actor.send(:parse_issues, rows, [])).to eq([])
    end

    it "skips blank rows" do
      rows = [ [ "2", "P", "T", "A", "1001", "", "", "", "10", "", "" ], [], Array.new(11) ]

      expect(actor.send(:parse_issues, rows, []).size).to eq(1)
    end

    it "defaults estimated_hours to 0.0 when the cell is blank" do
      rows = [ [ "", "P", "T", "A", "1001", "", "", "", "", "", "" ] ]

      expect(actor.send(:parse_issues, rows, []).first[:estimated_hours]).to eq(0.0)
    end

    it "parses a thousands-separator formatted number cell (e.g. FORMATTED_VALUE returning \"1,200\") instead of silently zeroing it" do
      rows = [ [ "", "P", "T", "A", "1001", "", "", "", "1,200", "", "" ] ]

      expect(actor.send(:parse_issues, rows, []).first[:estimated_hours]).to eq(1200.0)
    end

    context "status merging (依 issue_id 合併後推斷議題整體狀態)" do
      it "maps a valid single-row status to :status (未開始/執行中 → in_progress, 已完成 → done)" do
        row = ->(status) { [ "", "P", "T", "A", "1001", "", "", status, "10", "", "" ] }

        expect(actor.send(:parse_issues, [ row.call("未開始") ], []).first[:status]).to eq("in_progress")
        expect(actor.send(:parse_issues, [ row.call("執行中") ], []).first[:status]).to eq("in_progress")
        expect(actor.send(:parse_issues, [ row.call("已完成") ], []).first[:status]).to eq("done")
      end

      it "treats unrecognized status values (blank, stray numbers) as nil, not a valid status" do
        expect(actor.send(:parse_issues, [ [ "", "P", "T", "A", "1001", "", "", "", "10", "", "" ] ], []).first[:status]).to be_nil
        expect(actor.send(:parse_issues, [ [ "", "P", "T", "A", "1001", "", "", "3.5", "10", "", "" ] ], []).first[:status]).to be_nil
      end

      it "when rows disagree, treats the issue as in_progress unless every valid row says 已完成" do
        rows = [
          [ "", "P", "T", "A", "1001", "", "", "執行中", "5", "", "" ],
          [ "", "P", "T", "B", "1001", "", "", "已完成", "5", "", "" ]
        ]

        expect(actor.send(:parse_issues, rows, []).first[:status]).to eq("in_progress")
      end

      it "returns done only when every row with a recognized status says 已完成" do
        rows = [
          [ "", "P", "T", "A", "1001", "", "", "已完成", "5", "", "" ],
          [ "", "P", "T", "B", "1001", "", "", "已完成", "5", "", "" ]
        ]

        expect(actor.send(:parse_issues, rows, []).first[:status]).to eq("done")
      end

      it "falls back to nil when no row in the group has a recognized status" do
        rows = [
          [ "", "P", "T", "A", "1001", "", "", "2", "5", "", "" ],
          [ "", "P", "T", "B", "1001", "", "", "", "5", "", "" ]
        ]

        expect(actor.send(:parse_issues, rows, []).first[:status]).to be_nil
      end
    end

    context "when multiple rows share the same issue_id (same issue split across assignees)" do
      let(:header) { fixed_header + [ "08/10", "08/03" ] }
      let(:week_dates) { actor.send(:parse_week_dates, header) }

      it "merges them into a single issue: sums estimated_hours, reported_remaining_hours and weekly hours, unions assignees" do
        rows = [
          [ "-31.5", "立翔 PMS", "v2.0 調整", "黃紹鈞", "5005", "2026/07/09", "2026/08/06", "執行中", "121", "16", "" ],
          [ "-22.25", "立翔 PMS", "v2.0 調整", "沈舫竹", "5005", "2026/07/09", "2026/08/06", "執行中", "31", "4", "3.75" ]
        ]

        result = actor.send(:parse_issues, rows, week_dates)

        expect(result.size).to eq(1)
        issue = result.first
        expect(issue[:issue_id]).to eq("5005")
        expect(issue[:assignees]).to eq([ "黃紹鈞", "沈舫竹" ])
        expect(issue[:estimated_hours]).to eq(152.0)
        expect(issue[:reported_remaining_hours]).to eq(-53.75)
        expect(issue[:start_date]).to eq("2026-07-09")
        expect(issue[:due_date]).to eq("2026-08-06")
        # actual_series: cumulative weekly hours summed across both rows each week (oldest first)
        # week 08/03 (index 9): 0 + 3.75 = 3.75 → remaining 152 - 3.75 = 148.25
        # week 08/10 (index 8): 16 + 4 = 20 → cumulative 23.75 → remaining 152 - 23.75 = 128.25
        expect(issue[:actual_series]).to eq([
          { date: "2026-08-03", hours: 148.25 },
          { date: "2026-08-10", hours: 128.25 }
        ])
      end

      it "keeps each assignee's own cumulative consumed hours (running total from 0, not remaining hours)" do
        # 供堆疊圖使用：多人份的累積人時堆疊起來天生就是同一個基準（疊到頂＝議題整體累積消耗），
        # 用累積消耗而不是剩餘人時，才不會因為「個人份量 vs. 團隊總量」基準不同而誤導判讀。
        rows = [
          [ "-31.5", "立翔 PMS", "v2.0 調整", "黃紹鈞", "5005", "2026/07/09", "2026/08/06", "執行中", "121", "16", "" ],
          [ "-22.25", "立翔 PMS", "v2.0 調整", "沈舫竹", "5005", "2026/07/09", "2026/08/06", "執行中", "31", "4", "3.75" ]
        ]

        result = actor.send(:parse_issues, rows, week_dates)
        per_assignee = result.first[:per_assignee]

        expect(per_assignee.map { |pa| pa[:assignee] }).to eq([ "黃紹鈞", "沈舫竹" ])
        expect(per_assignee.map { |pa| pa[:estimated_hours] }).to eq([ 121.0, 31.0 ])
        expect(per_assignee[0][:cumulative_series]).to eq([
          { date: "2026-08-03", hours: 0.0 },
          { date: "2026-08-10", hours: 16.0 }
        ])
        expect(per_assignee[1][:cumulative_series]).to eq([
          { date: "2026-08-03", hours: 3.75 },
          { date: "2026-08-10", hours: 7.75 }
        ])
      end

      it "still counts a row's weekly hours toward the issue's actual_series even when that row's assignee is blank" do
        # 迴歸測試：議題整體 weekly_hours 一度被改成從「依人員分組後的週人時」加總推導，
        # 導致人員欄空白（但週人時有填）的列被排除在議題整體消耗之外，estimated_hours 卻仍把
        # 該列算進去，造成剩餘人時被高估且沒有任何錯誤或警告。
        rows = [
          [ "", "P", "T", "黃紹鈞", "9003", "", "", "執行中", "10", "3", "2" ],
          [ "", "P", "T", "", "9003", "", "", "執行中", "5", "1", "1" ]
        ]

        result = actor.send(:parse_issues, rows, week_dates)
        issue = result.first

        expect(issue[:estimated_hours]).to eq(15.0) # 10 + 5
        # weekly_hours: 08/03: 2(黃紹鈞) + 1(無名) = 3；08/10: 3(黃紹鈞) + 1(無名) = 4
        expect(issue[:actual_series]).to eq([
          { date: "2026-08-03", hours: 12.0 }, # 15 - 3
          { date: "2026-08-10", hours: 8.0 }   # 15 - (3+4)
        ])
        # per_assignee 仍然略過人員欄空白的列（堆疊圖無法顯示沒有名字的人）。
        expect(issue[:per_assignee].map { |pa| pa[:assignee] }).to eq([ "黃紹鈞" ])
      end

      it "merges per_assignee entries for the same person instead of listing one entry per raw row (e.g. a correction row)" do
        # 迴歸測試：修正前 per_assignee_series 沒有依人員名稱合併，同一人拆成兩列時堆疊圖會
        # 畫出兩塊同色色塊。
        rows = [
          [ "", "P", "T", "黃紹鈞", "9002", "", "", "執行中", "10", "3", "2" ],
          [ "", "P", "T", "黃紹鈞", "9002", "", "", "執行中", "5", "1", "1" ],
          [ "", "P", "T", "陳小華", "9002", "", "", "執行中", "8", "2", "1" ]
        ]

        result = actor.send(:parse_issues, rows, week_dates)
        issue = result.first

        expect(issue[:assignees]).to eq([ "黃紹鈞", "陳小華" ])
        per_assignee = issue[:per_assignee]
        expect(per_assignee.map { |pa| pa[:assignee] }).to eq([ "黃紹鈞", "陳小華" ])
        expect(per_assignee[0][:estimated_hours]).to eq(15.0) # 10 + 5
        # header week columns are ["08/10", "08/03"] (index 8, 9); sorted ascending puts 08/03
        # first. Row1 weekly cells (idx8=08/10:"3", idx9=08/03:"2") → sorted [2, 3].
        # Row2 weekly cells (idx8=08/10:"1", idx9=08/03:"1") → sorted [1, 1]. Summed: [3, 4].
        expect(per_assignee[0][:cumulative_series]).to eq([
          { date: "2026-08-03", hours: 3.0 },
          { date: "2026-08-10", hours: 7.0 }
        ])
      end

      it "trims the issue's own actual_series/ideal_series to weeks on or after start_date, not the full sheet week range" do
        header = fixed_header + [ "08/10", "08/03", "07/27" ]
        week_dates = actor.send(:parse_week_dates, header)
        # start_date (08/03) falls between the 07/27 and 08/03 week columns, so only 08/03 and
        # 08/10 should appear — 07/27 (before the issue existed) should be trimmed out.
        rows = [
          [ "", "P", "T", "A", "1001", "2026/08/03", "2026/08/17", "執行中", "10", "3", "2", "1" ]
        ]

        result = actor.send(:parse_issues, rows, week_dates)
        issue = result.first

        expect(issue[:actual_series].map { |p| p[:date] }).to eq([ "2026-08-03", "2026-08-10" ])
        # cumulative from a clean start at the trimmed window: 08/03 hours=2 → remaining 10-2=8;
        # 08/10 hours=3 → cumulative 5 → remaining 10-5=5 (the 07/27 column's "1" must NOT count).
        expect(issue[:actual_series]).to eq([
          { date: "2026-08-03", hours: 8.0 },
          { date: "2026-08-10", hours: 5.0 }
        ])
      end

      it "does not trim out a week column that falls in the same Monday-start week as start_date, even if the exact date is later" do
        # 2026-08-10 is a Monday; 2026-08-13 (Thursday) is later in the same week. A naive exact-date
        # comparison would wrongly exclude the 08/10 column (真實案例：issue_id 5146，開案 08/13、
        # 週欄位只到 08/10）。
        header = fixed_header + [ "08/10" ]
        week_dates = actor.send(:parse_week_dates, header)
        rows = [ [ "7", "RAG", "優化 202608", "黃紹鈞", "5146", "2026/08/13", "", "未開始", "8", "1" ] ]

        result = actor.send(:parse_issues, rows, week_dates)

        expect(result.first[:actual_series]).to eq([ { date: "2026-08-10", hours: 7.0 } ])
      end

      it "still trims out a week column from an earlier Monday-start week than start_date" do
        header = fixed_header + [ "08/10" ]
        week_dates = actor.send(:parse_week_dates, header)
        # start_date (08/17, a Monday) is a full week after the 08/10 column's week — genuinely
        # not the same week, so 08/10 should still be trimmed out.
        rows = [ [ "", "P", "T", "A", "1001", "2026/08/17", "", "執行中", "10", "5" ] ]

        result = actor.send(:parse_issues, rows, week_dates)

        expect(result.first[:actual_series]).to eq([])
      end

      it "shows the full week range when the issue has no individually-valid start_date to trim from" do
        header = fixed_header + [ "08/10", "08/03" ]
        week_dates = actor.send(:parse_week_dates, header)
        rows = [ [ "", "P", "T", "A", "1001", "", "", "執行中", "10", "3", "2" ] ]

        result = actor.send(:parse_issues, rows, week_dates)

        expect(result.first[:actual_series].map { |p| p[:date] }).to eq([ "2026-08-03", "2026-08-10" ])
      end

      it "takes the earliest valid start_date and the latest valid due_date across rows, ignoring rows whose own range is invalid" do
        rows = [
          # due_date (07/27) is before start_date (08/06) — this row's own range is invalid
          [ "4.25", "HRM", "標準版 202608B", "沈舫竹", "5128", "2026/08/06", "2026/07/27", "執行中", "11", "", "" ],
          [ "23", "HRM", "標準版 202608B", "黃靖益", "5128", "2026/08/06", "2026/08/13", "未開始", "23", "", "" ]
        ]

        result = actor.send(:parse_issues, rows, week_dates)

        expect(result.first[:start_date]).to eq("2026-08-06")
        expect(result.first[:due_date]).to eq("2026-08-13")
      end

      it "returns nil start_date/due_date (and an empty ideal_series) when every row's own range is invalid" do
        rows = [
          [ "9.5", "亞炬 Else", "v2.0 公務車調整", "周詩御", "4769", "2026/03/20", "2026/03/20", "已完成", "44", "", "" ]
        ]

        result = actor.send(:parse_issues, rows, week_dates)

        expect(result.first[:start_date]).to be_nil
        expect(result.first[:due_date]).to be_nil
        expect(result.first[:ideal_series]).to eq([])
      end

      it "keeps reported_remaining_hours nil when every row in the group left it blank" do
        rows = [
          [ "", "P", "T", "A", "9001", "", "", "", "5", "", "" ],
          [ "", "P", "T", "B", "9001", "", "", "", "3", "", "" ]
        ]

        result = actor.send(:parse_issues, rows, week_dates)

        expect(result.first[:reported_remaining_hours]).to be_nil
      end
    end
  end

  describe "#call" do
    subject(:result) { described_class.result }

    let(:header) { fixed_header + [ "08/10" ] }
    let(:rows) do
      [
        header,
        [ "2", "AG 亞炬", "議題A", "王贊勛", "1001", "2026/08/01", "2026/08/15", "執行中", "10", "3" ]
      ]
    end

    before { allow(BurndownSheetsClient).to receive(:fetch_rows).and_return(rows) }

    it "populates issues from the client's rows" do
      expect(result.issues.map { |i| i[:issue_id] }).to eq([ "1001" ])
    end

    context "when BurndownSheetsClient raises Google::Apis::ClientError status 404" do
      before do
        error = Google::Apis::ClientError.new("Not Found")
        allow(error).to receive(:status_code).and_return(404)
        allow(BurndownSheetsClient).to receive(:fetch_rows).and_raise(error)
      end

      it "returns failure_code: :sheet_not_found" do
        expect(result).not_to be_success
        expect(result.failure_code).to eq(:sheet_not_found)
        expect(result.message).to include("找不到指定分頁或試算表")
      end
    end

    context "when BurndownSheetsClient raises Google::Apis::ClientError status 403" do
      before do
        error = Google::Apis::ClientError.new("Forbidden")
        allow(error).to receive(:status_code).and_return(403)
        allow(BurndownSheetsClient).to receive(:fetch_rows).and_raise(error)
      end

      it "returns failure_code: :access_denied" do
        expect(result).not_to be_success
        expect(result.failure_code).to eq(:access_denied)
        expect(result.message).to include("資料來源存取權限不足")
      end
    end

    context "when BurndownSheetsClient raises Google::Apis::ClientError with another status code" do
      before do
        error = Google::Apis::ClientError.new("Bad Request")
        allow(error).to receive(:status_code).and_return(400)
        allow(BurndownSheetsClient).to receive(:fetch_rows).and_raise(error)
      end

      it "returns failure_code: :internal_error" do
        expect(result).not_to be_success
        expect(result.failure_code).to eq(:internal_error)
        expect(result.message).to include("Google Sheets API 錯誤")
      end
    end

    context "when BurndownSheetsClient raises a StandardError (e.g. missing credentials)" do
      before do
        allow(BurndownSheetsClient).to receive(:fetch_rows)
          .and_raise(StandardError.new("找不到 Google Service Account 憑證"))
      end

      it "returns failure_code: :internal_error" do
        expect(result).not_to be_success
        expect(result.failure_code).to eq(:internal_error)
        expect(result.message).to include("未預期的內部錯誤")
      end
    end
  end
end
