require "rails_helper"

RSpec.describe ProjectHistoryHelper, type: :helper do
  let(:min_date) { Date.new(2026, 7, 1) }
  let(:max_date) { Date.new(2026, 9, 1) }

  describe "#gantt_chart_domain" do
    it "computes the min/max date range from tasks' start_date/due_date" do
      travel_to Date.new(2026, 8, 16) do
        rows = [
          { tasks: [
            { start_date: "2026-01-05", due_date: "2026-03-20" }
          ] }
        ]

        min, max = helper.gantt_chart_domain(rows)

        expect(min).to eq(Date.new(2026, 1, 5))
        expect(max).to be >= Date.new(2026, 3, 20)
      end
    end
  end

  describe "#gantt_chart_month_ticks" do
    # 迴歸測試：使用者截圖回報「三月疊到標題」——min_date 是 3/15（不是當月 1 號）時，第一個
    # 月份刻度（3/1）早於 min_date，算出來的 x 座標會小於 GANTT_PADDING_LEFT，沒 clamp 的話
    # 格線／標籤會畫進專案列標籤欄，蓋住專案名稱文字。
    it "clamps the first tick to GANTT_PADDING_LEFT when min_date falls mid-month" do
      min = Date.new(2026, 3, 15)
      max = Date.new(2026, 8, 1)

      ticks = helper.gantt_chart_month_ticks(min, max)

      expect(ticks.first[:label]).to eq("2026/03")
      expect(ticks.first[:x]).to eq(ProjectHistoryHelper::GANTT_PADDING_LEFT.to_f)
    end
  end

  # 每個任務畫成「預計」「實際」上下兩條窄條（比照使用者提供的參考圖）：預計＝規劃時程
  # （start_date～due_date，不受完成狀態影響）；實際＝依準時／逾期上色，右界規則同換源前。
  describe "#gantt_chart_task_rect" do
    it "always spans the planned bar from start_date to due_date, regardless of completion" do
      task = { task_name: "API 效能優化", start_date: "2026-07-08", due_date: "2026-08-22",
               done: false, estimated_hours: 40, consumed_hours: 10.0 }

      rect = helper.gantt_chart_task_rect(task, min_date, max_date)

      due_x = helper.send(:gantt_chart_x, "2026-08-22", min_date, max_date)
      expect((rect[:x] + rect[:planned_width]).round(1)).to eq(due_x.round(1))
    end

    it "keeps the actual bar at due_date (not extended) when not yet due" do
      travel_to Date.new(2026, 7, 20) do
        task = { task_name: "API 效能優化", start_date: "2026-07-08", due_date: "2026-08-22",
                 done: false, estimated_hours: 40, consumed_hours: 10.0 }

        rect = helper.gantt_chart_task_rect(task, min_date, max_date)

        expect(rect[:overdue]).to be false
        due_x = helper.send(:gantt_chart_x, "2026-08-22", min_date, max_date)
        expect((rect[:x] + rect[:actual_width]).round(1)).to eq(due_x.round(1))
      end
    end

    it "extends the actual bar to today and marks overdue when unfinished past due_date" do
      travel_to Date.new(2026, 9, 1) do
        task = { task_name: "逾期任務", start_date: "2026-07-08", due_date: "2026-08-01",
                 done: false, estimated_hours: 10, consumed_hours: nil }

        rect = helper.gantt_chart_task_rect(task, min_date, max_date)

        expect(rect[:overdue]).to be true
        today_x = helper.send(:gantt_chart_x, Date.current.iso8601, min_date, max_date)
        expect((rect[:x] + rect[:actual_width]).round(1)).to eq(today_x.round(1))
      end
    end

    it "stops the actual bar at due_date (not today) once done, even past due_date" do
      travel_to Date.new(2026, 9, 1) do
        task = { task_name: "已完成任務", start_date: "2026-07-08", due_date: "2026-08-01",
                 done: true, estimated_hours: 10, consumed_hours: 10.0 }

        rect = helper.gantt_chart_task_rect(task, min_date, max_date)

        expect(rect[:overdue]).to be false
        due_x = helper.send(:gantt_chart_x, "2026-08-01", min_date, max_date)
        expect((rect[:x] + rect[:actual_width]).round(1)).to eq(due_x.round(1))
      end
    end

    it "fills a portion of the actual bar proportional to consumed/estimated hours" do
      task = { task_name: "填色任務", start_date: "2026-07-08", due_date: "2026-08-08",
               done: false, estimated_hours: 40, consumed_hours: 10.0 }

      rect = helper.gantt_chart_task_rect(task, min_date, max_date)

      expect(rect[:fill_width]).to eq((rect[:actual_width] * 0.25).round(2))
    end

    it "does not fill (fill_width 0) when the issue has no actual_series-derived consumed_hours" do
      task = { task_name: "資料不足", start_date: "2026-07-08", due_date: "2026-08-08",
               done: false, estimated_hours: 40, consumed_hours: nil }

      rect = helper.gantt_chart_task_rect(task, min_date, max_date)

      expect(rect[:fill_width]).to eq(0.0)
    end
  end

  # 「進度」欄的百分比 clamp 在 100%，議題早完成時看不出「其實花了預估的好幾倍工時」，
  # 只有工時欄的原始數字看得出來，故超支時額外用警示色標示（需求：不同花費比例要有不同顯示）。
  describe "#hours_pair" do
    it "marks the pair as overspent when consumed hours exceed estimated hours" do
      html = helper.hours_pair(22, 18)

      expect(html).to include("hours-pair-overspent")
    end

    it "does not mark as overspent when consumed hours are within the estimate" do
      html = helper.hours_pair(13.5, 34)

      expect(html).not_to include("hours-pair-overspent")
    end

    it "does not mark as overspent when consumed exactly equals estimated" do
      html = helper.hours_pair(10, 10)

      expect(html).not_to include("hours-pair-overspent")
    end

    it "returns — without crashing when either value is nil" do
      expect(helper.hours_pair(nil, 10)).to eq("—")
      expect(helper.hours_pair(10, nil)).to eq("—")
    end
  end
end
