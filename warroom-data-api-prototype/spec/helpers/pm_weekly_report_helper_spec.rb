# frozen_string_literal: true

require "rails_helper"

RSpec.describe PmWeeklyReportHelper, type: :helper do
  include ActiveSupport::Testing::TimeHelpers

  describe "#pm_weekly_range_label" do
    it "renders a Monday-to-Sunday range as YYYY/MM/DD ~ YYYY/MM/DD" do
      range = Date.new(2026, 9, 14)..Date.new(2026, 9, 20)

      expect(helper.pm_weekly_range_label(range)).to eq("2026/09/14 ~ 2026/09/20")
    end

    it "renders a dash when there is no range (the 305 fetch failed)" do
      expect(helper.pm_weekly_range_label(nil)).to eq("—")
    end
  end

  describe "#pm_weekly_date_label" do
    it "formats both Date objects and normalized date strings as YYYY/MM/DD" do
      expect(helper.pm_weekly_date_label(Date.new(2026, 9, 18))).to eq("2026/09/18")
      expect(helper.pm_weekly_date_label("2026-09-18")).to eq("2026/09/18")
    end

    it "shows a dash for a blank value" do
      expect(helper.pm_weekly_date_label(nil)).to eq("—")
      expect(helper.pm_weekly_date_label("")).to eq("—")
    end

    it "shows an unparseable sheet value as-is so the PM can see the cell is malformed" do
      expect(helper.pm_weekly_date_label("九月十八")).to eq("九月十八")
    end
  end

  describe "#pm_weekly_overdue_days" do
    around { |example| travel_to(Date.new(2026, 9, 18)) { example.run } }

    it "counts days from the planned completion date to today" do
      expect(helper.pm_weekly_overdue_days({ planned_completion_date: "2026-09-14" })).to eq(4)
    end

    it "ignores the sheet's own 延遲天數 column (it does not advance with today's date)" do
      task = { planned_completion_date: "2026-09-14", delay_days: 99 }

      expect(helper.pm_weekly_overdue_days(task)).to eq(4)
    end

    it "returns nil when there is no usable planned date" do
      expect(helper.pm_weekly_overdue_days({ planned_completion_date: nil })).to be_nil
      expect(helper.pm_weekly_overdue_days({ planned_completion_date: "未定" })).to be_nil
    end
  end

  describe "#pm_weekly_due_date_label" do
    it "marks SLA-derived due dates as estimated" do
      issue = { effective_due_date: Date.new(2026, 9, 19), due_date_estimated: true }

      expect(helper.pm_weekly_due_date_label(issue)).to eq("2026/09/19（推算）")
    end

    it "leaves sheet-provided due dates unmarked" do
      issue = { effective_due_date: Date.new(2026, 9, 18), due_date_estimated: false }

      expect(helper.pm_weekly_due_date_label(issue)).to eq("2026/09/18")
    end
  end

  describe "#pm_weekly_freshness_label" do
    it "reports how long ago the 305 data was fetched" do
      travel_to(Time.zone.parse("2026-09-18 09:07")) do
        expect(helper.pm_weekly_freshness_label(Time.zone.parse("2026-09-18 09:04"))).to eq("資料更新於 3 分鐘前")
      end
    end

    it "says just-updated for a fetch that has only just happened" do
      travel_to(Time.zone.parse("2026-09-18 09:00:05")) do
        expect(helper.pm_weekly_freshness_label(Time.zone.parse("2026-09-18 09:00:00"))).to eq("資料剛剛更新")
      end
    end

    it "returns nil when the cache has no recorded fetch time" do
      expect(helper.pm_weekly_freshness_label(nil)).to be_nil
    end
  end

  describe "#pm_weekly_count" do
    it "flattens one grouped structure into a total item count" do
      grouped = { "AG 亞炬" => [ {}, {} ], "Virtuous HRM" => [ {} ] }

      expect(helper.pm_weekly_count(grouped)).to eq(3)
    end

    it "adds up several grouped structures (一個區塊由多個清單組成)" do
      tasks = { "AG 亞炬" => [ {}, {} ] }
      issues = { "Virtuous HRM" => [ {} ] }

      expect(helper.pm_weekly_count(tasks, issues)).to eq(3)
    end

    it "returns zero when every group is empty" do
      expect(helper.pm_weekly_count({}, {})).to eq(0)
    end

    it "shows a dash instead of 0 when the data source could not be read at all" do
      # 0 是「確實沒有」的斷言；降級時我們並不知道有沒有，不能把漏抓講成沒有（需求 1.4）
      expect(helper.pm_weekly_count({}, unavailable: true)).to eq("—")
    end
  end
end
