require "rails_helper"

RSpec.describe IssuesHelper, type: :helper do
  describe "#attribution_label" do
    it "maps Complaint to 專案共同責任" do
      expect(helper.attribution_label("Complaint")).to eq("專案共同責任")
    end

    it "maps TestingBug to 個人責任" do
      expect(helper.attribution_label("TestingBug")).to eq("個人責任")
    end

    it "maps anything else to 其他" do
      expect(helper.attribution_label("Other")).to eq("其他")
      expect(helper.attribution_label(nil)).to eq("其他")
    end
  end

  describe "#attribution_class" do
    it "maps Complaint to attribution-shared" do
      expect(helper.attribution_class("Complaint")).to eq("attribution-shared")
    end

    it "maps TestingBug to attribution-individual" do
      expect(helper.attribution_class("TestingBug")).to eq("attribution-individual")
    end

    it "maps anything else to attribution-other" do
      expect(helper.attribution_class("Other")).to eq("attribution-other")
    end
  end

  describe "#trend_chart_points" do
    it "assigns evenly spaced x coordinates across the plot width, first/last at the left/right padding" do
      records = [
        { date: "2026-08-01", total: 1 },
        { date: "2026-08-02", total: 2 },
        { date: "2026-08-03", total: 3 }
      ]

      points = helper.trend_chart_points(records)

      expect(points.first[:x]).to eq(IssuesHelper::TREND_PADDING_LEFT)
      expect(points.last[:x]).to eq(IssuesHelper::TREND_WIDTH - IssuesHelper::TREND_PADDING_RIGHT)
    end

    it "places the point with the max total at the top (smallest y)" do
      records = [
        { date: "2026-08-01", total: 1 },
        { date: "2026-08-02", total: 5 },
        { date: "2026-08-03", total: 3 }
      ]

      points = helper.trend_chart_points(records)

      expect(points[1][:y]).to be < points[0][:y]
      expect(points[1][:y]).to be < points[2][:y]
    end

    it "does not raise when all totals are 0 (avoids division by zero)" do
      records = [{ date: "2026-08-01", total: 0 }, { date: "2026-08-02", total: 0 }]

      expect { helper.trend_chart_points(records) }.not_to raise_error
    end

    it "does not raise for a single record (avoids division by zero on step_x)" do
      records = [{ date: "2026-08-01", total: 5 }]

      points = helper.trend_chart_points(records)

      expect(points.size).to eq(1)
      expect(points.first[:x]).to eq(IssuesHelper::TREND_PADDING_LEFT)
    end

    it "returns an empty array for an empty input" do
      expect(helper.trend_chart_points([])).to eq([])
    end
  end

  describe "#trend_chart_polyline" do
    it "joins x,y pairs with spaces" do
      points = [{ x: 1.0, y: 2.0 }, { x: 3.5, y: 4.5 }]

      expect(helper.trend_chart_polyline(points)).to eq("1.0,2.0 3.5,4.5")
    end
  end

  describe "#trend_chart_y_ticks" do
    it "returns 3 ticks at 0, mid, and max of the total values" do
      records = [{ total: 0 }, { total: 4 }, { total: 8 }]

      ticks = helper.trend_chart_y_ticks(records)

      expect(ticks.map { |t| t[:value] }).to eq([0, 4, 8])
    end

    it "places the value-0 tick at the bottom (largest y) and the max tick at the top (smallest y)" do
      records = [{ total: 0 }, { total: 10 }]

      ticks = helper.trend_chart_y_ticks(records)

      expect(ticks.first[:y]).to be > ticks.last[:y]
    end

    it "does not raise when all totals are 0" do
      expect { helper.trend_chart_y_ticks([{ total: 0 }]) }.not_to raise_error
    end
  end

  describe "#trend_chart_x_labels" do
    it "shows one label per record when count is within TREND_MAX_X_LABELS" do
      records = [{ date: "2026-08-01" }, { date: "2026-08-02" }, { date: "2026-08-03" }]

      labels = helper.trend_chart_x_labels(records)

      expect(labels.map { |l| l[:text] }).to eq(["08/01", "08/02", "08/03"])
    end

    it "caps the number of labels at TREND_MAX_X_LABELS when there are more records, including first and last" do
      records = (1..10).map { |d| { date: format("2026-08-%02d", d) } }

      labels = helper.trend_chart_x_labels(records)

      expect(labels.size).to eq(IssuesHelper::TREND_MAX_X_LABELS)
      expect(labels.first[:text]).to eq("08/01")
      expect(labels.last[:text]).to eq("08/10")
    end

    it "returns an empty array for an empty input" do
      expect(helper.trend_chart_x_labels([])).to eq([])
    end

    it "returns a single label for a single record" do
      labels = helper.trend_chart_x_labels([{ date: "2026-08-05" }])

      expect(labels.map { |l| l[:text] }).to eq(["08/05"])
    end
  end
end
