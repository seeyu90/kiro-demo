require "rails_helper"

RSpec.describe ProjectPhaseTrackingHelper, type: :helper do
  describe "#parse_date_only" do
    it "parses a strict YYYY-MM-DD string" do
      expect(helper.parse_date_only("2026-08-20")).to eq(Date.new(2026, 8, 20))
    end

    it "returns nil for nil, blank, or malformed input" do
      expect(helper.parse_date_only(nil)).to be_nil
      expect(helper.parse_date_only("")).to be_nil
      expect(helper.parse_date_only("2026/08/20")).to be_nil
      expect(helper.parse_date_only("2026-99-99")).to be_nil
    end
  end

  describe "#diff_days" do
    it "returns actual minus planned in days" do
      expect(helper.diff_days("2026-08-25", "2026-08-20")).to eq(5)
      expect(helper.diff_days("2026-08-15", "2026-08-20")).to eq(-5)
      expect(helper.diff_days("2026-08-20", "2026-08-20")).to eq(0)
    end

    it "returns nil when either date fails to parse" do
      expect(helper.diff_days(nil, "2026-08-20")).to be_nil
      expect(helper.diff_days("2026-08-20", nil)).to be_nil
    end
  end

  describe "#compute_row_state" do
    it "labels 完成 when actual_date is present, computing diff_days when planned_date also present" do
      state = helper.compute_row_state("2026-08-20", "2026-08-25")
      expect(state).to eq(completion_label: "已完成", diff_days: 5)
    end

    it "labels 已完成 with nil diff_days when planned_date is missing" do
      state = helper.compute_row_state(nil, "2026-08-25")
      expect(state).to eq(completion_label: "已完成", diff_days: nil)
    end

    it "labels 未完成 when only planned_date is present" do
      state = helper.compute_row_state("2026-08-20", nil)
      expect(state).to eq(completion_label: "未完成", diff_days: nil)
    end

    it "labels — when neither date is present" do
      state = helper.compute_row_state(nil, nil)
      expect(state).to eq(completion_label: "—", diff_days: nil)
    end
  end

  describe "#phase_gantt_chart_domain" do
    it "returns nil when no row has a valid planned_date (empty-state)" do
      rows = [ { planned_date: nil, actual_date: nil }, { planned_date: "not-a-date", actual_date: nil } ]
      expect(helper.phase_gantt_chart_domain(rows)).to be_nil
    end

    it "takes the min planned_date and the max of (actual dates, today, min_date), then pads a month on each side" do
      travel_to Date.new(2026, 8, 16) do
        rows = [
          { planned_date: "2026-02-15", actual_date: "2026-02-18" },
          { planned_date: "2026-03-01", actual_date: nil }
        ]

        domain = helper.phase_gantt_chart_domain(rows)

        expect(domain[:min_date]).to eq(Date.new(2026, 1, 15))
        expect(domain[:max_date]).to eq(Date.new(2026, 9, 16))
      end
    end

    it "uses the latest actual_date as max_date when it is after today, still padded by a month" do
      travel_to Date.new(2026, 1, 1) do
        rows = [ { planned_date: "2025-12-01", actual_date: "2026-03-01" } ]

        domain = helper.phase_gantt_chart_domain(rows)

        expect(domain[:max_date]).to eq(Date.new(2026, 4, 1))
      end
    end

    it "pads min_date a month earlier too, not just max_date" do
      travel_to Date.new(2026, 1, 1) do
        rows = [ { planned_date: "2025-12-01", actual_date: nil } ]

        domain = helper.phase_gantt_chart_domain(rows)

        expect(domain[:min_date]).to eq(Date.new(2025, 11, 1))
      end
    end
  end

  describe "#phase_gantt_chart_svg_width" do
    it "returns GANTT_MIN_WIDTH for a short domain" do
      domain = { min_date: Date.new(2026, 8, 1), max_date: Date.new(2026, 8, 5) }
      expect(helper.phase_gantt_chart_svg_width(domain)).to eq(ProjectPhaseTrackingHelper::GANTT_MIN_WIDTH)
    end

    it "grows with the day span beyond the minimum" do
      domain = { min_date: Date.new(2026, 1, 1), max_date: Date.new(2026, 12, 31) }
      days = (domain[:max_date] - domain[:min_date]).to_i
      expected = ProjectPhaseTrackingHelper::GANTT_PADDING_LEFT +
        ProjectPhaseTrackingHelper::GANTT_PADDING_RIGHT +
        days * ProjectPhaseTrackingHelper::GANTT_PIXELS_PER_DAY
      expect(helper.phase_gantt_chart_svg_width(domain)).to eq(expected)
    end
  end

  describe "#phase_gantt_chart_month_ticks" do
    # 迴歸測試同 ProjectHistoryHelper 慣例：min_date 非當月 1 號時，第一個刻度（該月 1 號）
    # 算出來的 x 座標會小於 GANTT_PADDING_LEFT，須 clamp 避免畫進專案列標籤欄。
    it "clamps the first tick to GANTT_PADDING_LEFT when min_date falls mid-month" do
      domain = { min_date: Date.new(2026, 3, 15), max_date: Date.new(2026, 5, 1) }
      width = helper.phase_gantt_chart_svg_width(domain)

      ticks = helper.phase_gantt_chart_month_ticks(domain, width)

      expect(ticks.first[:label]).to eq("2026/03")
      expect(ticks.first[:x]).to eq(ProjectPhaseTrackingHelper::GANTT_PADDING_LEFT.to_f)
    end

    it "produces one tick per calendar month spanning the domain" do
      domain = { min_date: Date.new(2026, 1, 1), max_date: Date.new(2026, 3, 1) }
      width = helper.phase_gantt_chart_svg_width(domain)

      ticks = helper.phase_gantt_chart_month_ticks(domain, width)

      expect(ticks.map { |t| t[:label] }).to eq([ "2026/01", "2026/02", "2026/03" ])
    end
  end

  # 雙軌設計，分兩個獨立方法各自測試（見 ProjectPhaseTrackingHelper 附註）。
  describe "#phase_gantt_chart_planned_segment / #phase_gantt_chart_actual_segment" do
    let(:domain) { { min_date: Date.new(2026, 1, 1), max_date: Date.new(2026, 12, 31) } }
    let(:width) { helper.phase_gantt_chart_svg_width(domain) }

    def stage(planned_date: nil, actual_date: nil, primary: true)
      row = primary ? { planned_date: planned_date, actual_date: actual_date } : nil
      { stage: "x", primary: row, history: [] }
    end

    describe "#phase_gantt_chart_planned_segment" do
      it "returns nil when the stage has no primary record, or planned_date is missing" do
        expect(helper.phase_gantt_chart_planned_segment([ stage(primary: false) ], 0, domain, width)).to be_nil
        expect(helper.phase_gantt_chart_planned_segment([ stage(planned_date: nil) ], 0, domain, width)).to be_nil
      end

      it "spans from the previous stage's own planned_date to this stage's planned_date, regardless of completion" do
        stages = [
          stage(planned_date: "2026-02-01", actual_date: nil), # 前一階段還沒完成，也不影響上軌
          stage(planned_date: "2026-03-10", actual_date: "2026-03-20")
        ]

        segment = helper.phase_gantt_chart_planned_segment(stages, 1, domain, width)

        x1 = helper.phase_gantt_chart_x(Date.new(2026, 2, 1), domain, width)
        x2 = helper.phase_gantt_chart_x(Date.new(2026, 3, 10), domain, width)
        expect(segment[:x]).to eq(x1.round(2))
        expect(segment[:width]).to eq((x2 - x1).round(2))
        expect(segment[:stage]).to eq("x")
      end

      it "skips over an earlier STAGE_ORDER slot with no record at all to find the previous stage that has data" do
        stages = [
          stage(primary: false), # e.g. 需求確認，沒有任何記錄
          stage(planned_date: "2026-02-01"),
          stage(planned_date: "2026-03-10")
        ]

        segment = helper.phase_gantt_chart_planned_segment(stages, 2, domain, width)

        x1 = helper.phase_gantt_chart_x(Date.new(2026, 2, 1), domain, width)
        expect(segment[:x]).to eq(x1.round(2))
      end

      it "falls back to its own planned_date (zero-width, clamped) when it's the first stage with any data" do
        segment = helper.phase_gantt_chart_planned_segment([ stage(planned_date: "2026-03-10") ], 0, domain, width)

        x1 = helper.phase_gantt_chart_x(Date.new(2026, 3, 10), domain, width)
        expect(segment[:x]).to eq(x1.round(2))
        expect(segment[:width]).to be >= ProjectPhaseTrackingHelper::GANTT_MIN_SEGMENT_WIDTH
      end
    end

    describe "#phase_gantt_chart_actual_segment" do
      it "returns nil when the stage has no primary record, or has no actual_date yet (nothing 'actual' to draw)" do
        expect(helper.phase_gantt_chart_actual_segment([ stage(primary: false) ], 0, domain, width)).to be_nil
        expect(helper.phase_gantt_chart_actual_segment([ stage(planned_date: "2026-01-01", actual_date: nil) ], 0, domain, width)).to be_nil
      end

      it "spans from the previous stage's own actual_date to this stage's actual_date, marked :delayed when genuinely late" do
        stages = [
          stage(planned_date: "2026-02-01", actual_date: "2026-02-05"),
          stage(planned_date: "2026-03-10", actual_date: "2026-03-20")
        ]

        segment = helper.phase_gantt_chart_actual_segment(stages, 1, domain, width)

        expect(segment[:variant]).to eq(:delayed)
        expect(segment[:diff_days]).to eq(10)
        x1 = helper.phase_gantt_chart_x(Date.new(2026, 2, 5), domain, width)
        x2 = helper.phase_gantt_chart_x(Date.new(2026, 3, 20), domain, width)
        expect(segment[:x]).to eq(x1.round(2))
        expect(segment[:width]).to eq((x2 - x1).round(2))
      end

      it "marks :early when completed ahead of its own planned_date" do
        stages = [
          stage(planned_date: "2026-02-01", actual_date: "2026-02-01"),
          stage(planned_date: "2026-03-10", actual_date: "2026-03-01")
        ]

        segment = helper.phase_gantt_chart_actual_segment(stages, 1, domain, width)

        expect(segment[:variant]).to eq(:early)
        expect(segment[:diff_days]).to eq(-9)
      end

      it "marks :early (not :delayed) when diff_days is exactly 0 — genuinely on time, not late" do
        # 迴歸測試：`diff_days.negative?` 判斷會讓剛好準時（diff_days == 0）落到 else 分支被標成
        # :delayed（紅色），跟圖例文字「準時／提前完成＝綠色」自相矛盾。
        stages = [
          stage(planned_date: "2026-02-01", actual_date: "2026-02-01"),
          stage(planned_date: "2026-03-10", actual_date: "2026-03-10")
        ]

        segment = helper.phase_gantt_chart_actual_segment(stages, 1, domain, width)

        expect(segment[:variant]).to eq(:early)
        expect(segment[:diff_days]).to eq(0)
      end

      it "skips an earlier stage that isn't completed yet when chaining the actual track (not its planned_date)" do
        stages = [
          stage(planned_date: "2026-01-15", actual_date: "2026-01-20"), # 有 actual，是銜接點
          stage(planned_date: "2026-02-01", actual_date: nil), # 還沒完成，下軌沒有它，跳過
          stage(planned_date: "2026-03-10", actual_date: "2026-03-10")
        ]

        segment = helper.phase_gantt_chart_actual_segment(stages, 2, domain, width)

        x1 = helper.phase_gantt_chart_x(Date.new(2026, 1, 20), domain, width)
        expect(segment[:x]).to eq(x1.round(2))
      end

      it "falls back to its own actual_date (zero-width, clamped) when it's the first stage with actual data" do
        segment = helper.phase_gantt_chart_actual_segment(
          [ stage(planned_date: "2026-03-10", actual_date: "2026-03-10") ], 0, domain, width
        )

        x1 = helper.phase_gantt_chart_x(Date.new(2026, 3, 10), domain, width)
        expect(segment[:x]).to eq(x1.round(2))
        expect(segment[:width]).to be >= ProjectPhaseTrackingHelper::GANTT_MIN_SEGMENT_WIDTH
      end

      it "keeps a minimum 2px width when the previous boundary and this stage's actual_date land on the same pixel" do
        narrow_domain = { min_date: Date.new(2026, 1, 1), max_date: Date.new(2026, 1, 2) }
        narrow_width = helper.phase_gantt_chart_svg_width(narrow_domain)
        stages = [
          stage(planned_date: "2026-01-01", actual_date: "2026-01-01"),
          stage(planned_date: "2026-01-01", actual_date: "2026-01-01")
        ]

        segment = helper.phase_gantt_chart_actual_segment(stages, 1, narrow_domain, narrow_width)

        expect(segment[:width]).to be >= ProjectPhaseTrackingHelper::GANTT_MIN_SEGMENT_WIDTH
      end
    end
  end
end
