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
