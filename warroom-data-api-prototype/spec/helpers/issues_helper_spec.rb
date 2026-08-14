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
    it "assigns evenly spaced x coordinates across the width, first at padding and last at width-padding" do
      records = [
        { date: "2026-08-01", total: 1 },
        { date: "2026-08-02", total: 2 },
        { date: "2026-08-03", total: 3 }
      ]

      points = helper.trend_chart_points(records)

      expect(points.first[:x]).to eq(IssuesHelper::TREND_CHART_PADDING)
      expect(points.last[:x]).to eq(IssuesHelper::TREND_CHART_WIDTH - IssuesHelper::TREND_CHART_PADDING)
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
      expect(points.first[:x]).to eq(IssuesHelper::TREND_CHART_PADDING)
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
end
