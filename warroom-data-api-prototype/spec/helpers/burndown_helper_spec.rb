require "rails_helper"

RSpec.describe BurndownHelper, type: :helper do
  def issue(estimated_hours:, actual_series:, ideal_series:, reported_remaining_hours: nil)
    {
      estimated_hours: estimated_hours,
      actual_series: actual_series,
      ideal_series: ideal_series,
      reported_remaining_hours: reported_remaining_hours
    }
  end

  describe "#burndown_status" do
    it "returns :on_track when the latest actual remaining is at or ahead of the ideal line" do
      i = issue(
        estimated_hours: 10.0,
        actual_series: [ { date: "2026-08-10", hours: 5.0 } ],
        ideal_series: [ { date: "2026-08-10", hours: 5.0 } ]
      )

      expect(helper.burndown_status(i)).to eq(key: :on_track, label: "正常")
    end

    it "returns :at_risk when the gap is a moderate share of the estimate" do
      i = issue(
        estimated_hours: 10.0,
        actual_series: [ { date: "2026-08-10", hours: 6.5 } ],
        ideal_series: [ { date: "2026-08-10", hours: 5.0 } ]
      )

      expect(helper.burndown_status(i)).to eq(key: :at_risk, label: "略慢")
    end

    it "returns :over when actual remaining is far above the ideal line" do
      i = issue(
        estimated_hours: 10.0,
        actual_series: [ { date: "2026-08-10", hours: 9.0 } ],
        ideal_series: [ { date: "2026-08-10", hours: 5.0 } ]
      )

      expect(helper.burndown_status(i)).to eq(key: :over, label: "超支")
    end

    it "returns :unknown when estimated_hours is zero" do
      i = issue(
        estimated_hours: 0,
        actual_series: [ { date: "2026-08-10", hours: 1.0 } ],
        ideal_series: [ { date: "2026-08-10", hours: 1.0 } ]
      )

      expect(helper.burndown_status(i)[:key]).to eq(:unknown)
    end

    it "returns :unknown when either series is blank" do
      i = issue(estimated_hours: 10.0, actual_series: [], ideal_series: [])

      expect(helper.burndown_status(i)[:key]).to eq(:unknown)
    end

    it "returns :over when the actual remaining is already negative, even if the ideal line is also near zero" do
      # 迴歸測試：完成日已過、理想線落在 0 附近時，單純比較「落差」會誤判負值剩餘（已超支）為
      # 正常（因為負值落差 <= 門檻）。負值剩餘本身就是超支的鐵證，須優先判斷。
      i = issue(
        estimated_hours: 166.0,
        actual_series: [ { date: "2026-08-10", hours: -40.75 } ],
        ideal_series: [ { date: "2026-07-27", hours: 0.0 } ]
      )

      expect(helper.burndown_status(i)).to eq(key: :over, label: "超支")
    end

    it "falls back to the nearest ideal date when there is no exact date match" do
      i = issue(
        estimated_hours: 10.0,
        actual_series: [ { date: "2026-08-11", hours: 5.0 } ],
        ideal_series: [ { date: "2026-08-10", hours: 5.0 }, { date: "2026-08-24", hours: 0.0 } ]
      )

      expect(helper.burndown_status(i)).to eq(key: :on_track, label: "正常")
    end
  end

  describe "#burndown_per_assignee_status" do
    let(:issue_dates) { { start_date: "2026-08-01", due_date: "2026-08-15" } }

    def per_assignee_entry(estimated_hours:, cumulative_series:)
      { estimated_hours: estimated_hours, cumulative_series: cumulative_series }
    end

    it "does not flag someone who simply has a bigger share of the work" do
      # 兩人同一天進度都是「剛好符合自己份量的時間進度」，即使花的絕對人時差很多
      # （20 vs 4），兩人都不該被標記——份量本來就不一樣。
      today = issue_dates.merge(estimated_hours: 999) # estimated_hours 不影響這個方法本身
      big_share = per_assignee_entry(estimated_hours: 40.0, cumulative_series: [ { date: "2026-08-08", hours: 20.0 } ])
      small_share = per_assignee_entry(estimated_hours: 8.0, cumulative_series: [ { date: "2026-08-08", hours: 4.0 } ])

      expect(helper.burndown_per_assignee_status(big_share, today)[:key]).to eq(:on_track)
      expect(helper.burndown_per_assignee_status(small_share, today)[:key]).to eq(:on_track)
    end

    it "flags the person who is behind relative to their own allocation, not the one with more raw hours" do
      i = issue_dates.merge(estimated_hours: 999)
      # 8/8 是開案（8/1）到完成（8/15）中間，時間進度 50%。
      behind = per_assignee_entry(estimated_hours: 40.0, cumulative_series: [ { date: "2026-08-08", hours: 5.0 } ])
      on_track_with_fewer_hours = per_assignee_entry(estimated_hours: 8.0, cumulative_series: [ { date: "2026-08-08", hours: 4.0 } ])

      expect(helper.burndown_per_assignee_status(behind, i)[:key]).to eq(:over)
      expect(helper.burndown_per_assignee_status(on_track_with_fewer_hours, i)[:key]).to eq(:on_track)
    end

    it "returns :over when someone has already consumed more than their own estimate" do
      i = issue_dates.merge(estimated_hours: 999)
      pa = per_assignee_entry(estimated_hours: 8.0, cumulative_series: [ { date: "2026-08-08", hours: 9.0 } ])

      expect(helper.burndown_per_assignee_status(pa, i)).to eq(key: :over, label: "超支")
    end

    it "returns :unknown when the person's own estimated_hours is zero" do
      i = issue_dates.merge(estimated_hours: 999)
      pa = per_assignee_entry(estimated_hours: 0, cumulative_series: [ { date: "2026-08-08", hours: 1.0 } ])

      expect(helper.burndown_per_assignee_status(pa, i)[:key]).to eq(:unknown)
    end

    it "returns :unknown when the issue has no valid start/due date to compute time progress" do
      i = { start_date: nil, due_date: nil, estimated_hours: 999 }
      pa = per_assignee_entry(estimated_hours: 8.0, cumulative_series: [ { date: "2026-08-08", hours: 4.0 } ])

      expect(helper.burndown_per_assignee_status(pa, i)[:key]).to eq(:unknown)
    end
  end

  describe "#burndown_remaining_hours" do
    it "prefers reported_remaining_hours when present" do
      i = issue(estimated_hours: 10.0, actual_series: [ { date: "2026-08-10", hours: 5.0 } ],
                 ideal_series: [], reported_remaining_hours: 3.0)

      expect(helper.burndown_remaining_hours(i)).to eq(3.0)
    end

    it "falls back to the latest actual_series point when reported_remaining_hours is absent" do
      i = issue(estimated_hours: 10.0,
                 actual_series: [ { date: "2026-08-03", hours: 8.0 }, { date: "2026-08-10", hours: 5.0 } ],
                 ideal_series: [])

      expect(helper.burndown_remaining_hours(i)).to eq(5.0)
    end
  end

  describe "#burndown_consumed_hours" do
    it "computes estimated_hours minus the remaining hours" do
      i = issue(estimated_hours: 10.0, actual_series: [ { date: "2026-08-10", hours: 4.0 } ], ideal_series: [])

      expect(helper.burndown_consumed_hours(i)).to eq(6.0)
    end

    it "returns nil when remaining hours cannot be determined" do
      i = issue(estimated_hours: 10.0, actual_series: [], ideal_series: [])

      expect(helper.burndown_consumed_hours(i)).to be_nil
    end
  end
end
