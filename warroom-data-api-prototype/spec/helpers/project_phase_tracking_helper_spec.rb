require "rails_helper"

RSpec.describe ProjectPhaseTrackingHelper, type: :helper do
  # 迴歸測試：使用者反應「延誤已完成」「延誤未完成」原本分別跟「完成」「未完成」共用同一種
  # 顏色，字面上寫著「延誤」卻看不出跟準時的差別，兩個「延誤」值必須有自己專屬的樣式。
  describe "#phase_tracking_status_class" do
    it "gives the two 延誤 statuses their own class, distinct from their non-delayed counterparts" do
      expect(helper.phase_tracking_status_class("延誤已完成")).to eq("tag-status-delayed")
      expect(helper.phase_tracking_status_class("延誤未完成")).to eq("tag-status-delayed")
      expect(helper.phase_tracking_status_class("完成")).not_to eq(helper.phase_tracking_status_class("延誤已完成"))
      expect(helper.phase_tracking_status_class("未完成")).not_to eq(helper.phase_tracking_status_class("延誤未完成"))
    end

    it "keeps 暫緩 on its own class and truly unknown values on the generic fallback" do
      expect(helper.phase_tracking_status_class("暫緩")).to eq("tag-status-paused")
      expect(helper.phase_tracking_status_class("這不是真實資料裡出現過的值")).to eq("tag-status")
    end

    # 「進行中」是稽核真實資料時發現、規格文件原本沒列出的第 6 種原始狀態值（修正 current_stage
    # 選錯階段的 bug 後才第一次真的浮現到畫面上），語意上跟「未完成」同一類，歸到同一個 class。
    it "treats 進行中 the same as 未完成 — both mean still in progress, no delay signal" do
      expect(helper.phase_tracking_status_class("進行中")).to eq(helper.phase_tracking_status_class("未完成"))
    end
  end

  # 迴歸測試：使用者看到一整排「未完成」卡片的「預計完成」日期其實都已經過了今天，反應
  # 「不應該用紅色加強已經逾期的概念嗎」。
  describe "#phase_tracking_overdue?" do
    around { |example| travel_to(Date.new(2026, 9, 19)) { example.run } }

    it "is true for an unfinished status whose planned_completion_date has already passed" do
      expect(helper.phase_tracking_overdue?("未完成", "2026-09-01")).to be true
      expect(helper.phase_tracking_overdue?("延誤未完成", "2026-09-01")).to be true
      expect(helper.phase_tracking_overdue?("進行中", "2026-09-01")).to be true
    end

    it "is false when the planned_completion_date is today or still in the future" do
      expect(helper.phase_tracking_overdue?("未完成", "2026-09-19")).to be false
      expect(helper.phase_tracking_overdue?("未完成", "2026-10-08")).to be false
    end

    it "is false once the stage is actually done, even if the date is in the past — it's not still overdue" do
      expect(helper.phase_tracking_overdue?("完成", "2026-09-01")).to be false
      expect(helper.phase_tracking_overdue?("延誤已完成", "2026-09-01")).to be false
    end

    it "is false for 暫緩 — deliberately paused, not something to flag as overdue" do
      expect(helper.phase_tracking_overdue?("暫緩", "2026-09-01")).to be false
    end

    it "is false when there is no planned_completion_date to judge by" do
      expect(helper.phase_tracking_overdue?("未完成", nil)).to be false
    end
  end

  # 迴歸測試：使用者反應甘特圖側欄標籤讓瀏覽器對「LXPMS - v2.0 調整（5005）」整串自動換行，
  # 容易斷在名稱／ID 中間難以辨識，要求固定拆成「專案代碼 - ID」／「議題名稱」兩行。
  describe "#phase_gantt_chart_label_lines" do
    it "puts the project code and issue id on the first line, the issue name on the second" do
      card = { project: "LXPMS", issue_id: "5005", issue_name: "v2.0 調整" }

      expect(helper.phase_gantt_chart_label_lines(card)).to eq([ "LXPMS - 5005", "v2.0 調整" ])
    end

    it "returns a single line when there is no issue_name" do
      card = { project: "LXPMS", issue_id: "5005", issue_name: nil }

      expect(helper.phase_gantt_chart_label_lines(card)).to eq([ "LXPMS - 5005" ])
    end
  end

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
      # current_stage_name 傳 nil（或不相符的名稱）＝這個階段不是「目前階段」，維持修正前的
      # 既有行為；下面另有專門測試「未完成不代表沒有進度條」新增的 in_progress 情境。
      it "returns nil when the stage has no primary record, or has no actual_date and isn't the current stage" do
        expect(helper.phase_gantt_chart_actual_segment([ stage(primary: false) ], 0, domain, width, nil)).to be_nil
        expect(helper.phase_gantt_chart_actual_segment([ stage(planned_date: "2026-01-01", actual_date: nil) ], 0, domain, width, nil)).to be_nil
      end

      it "spans from the previous stage's own actual_date to this stage's actual_date, marked :delayed when genuinely late" do
        stages = [
          stage(planned_date: "2026-02-01", actual_date: "2026-02-05"),
          stage(planned_date: "2026-03-10", actual_date: "2026-03-20")
        ]

        segment = helper.phase_gantt_chart_actual_segment(stages, 1, domain, width, nil)

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

        segment = helper.phase_gantt_chart_actual_segment(stages, 1, domain, width, nil)

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

        segment = helper.phase_gantt_chart_actual_segment(stages, 1, domain, width, nil)

        expect(segment[:variant]).to eq(:early)
        expect(segment[:diff_days]).to eq(0)
      end

      it "skips an earlier stage that isn't completed yet when chaining the actual track (not its planned_date)" do
        stages = [
          stage(planned_date: "2026-01-15", actual_date: "2026-01-20"), # 有 actual，是銜接點
          stage(planned_date: "2026-02-01", actual_date: nil), # 還沒完成，下軌沒有它，跳過
          stage(planned_date: "2026-03-10", actual_date: "2026-03-10")
        ]

        segment = helper.phase_gantt_chart_actual_segment(stages, 2, domain, width, nil)

        x1 = helper.phase_gantt_chart_x(Date.new(2026, 1, 20), domain, width)
        expect(segment[:x]).to eq(x1.round(2))
      end

      it "falls back to its own actual_date (zero-width, clamped) when it's the first stage with actual data" do
        segment = helper.phase_gantt_chart_actual_segment(
          [ stage(planned_date: "2026-03-10", actual_date: "2026-03-10") ], 0, domain, width, nil
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

        segment = helper.phase_gantt_chart_actual_segment(stages, 1, narrow_domain, narrow_width, nil)

        expect(segment[:width]).to be >= ProjectPhaseTrackingHelper::GANTT_MIN_SEGMENT_WIDTH
      end

      # 迴歸測試：使用者反應「未完成不代表沒有進度條」——這個階段還沒有 actual_date，但它是
      # 議題「目前階段」（current_stage_name 相符），代表真的在做，不該完全不畫。
      describe "the current, not-yet-completed stage" do
        around { |example| travel_to(Date.new(2026, 9, 19)) { example.run } }

        it "draws a segment extending to today (not to the future planned_date) when still within its deadline" do
          # 前一階段有明確的 actual_date（銜接點），跟「今日」隔了好幾個月，確保量到的終點
          # 不是被 GANTT_MIN_SEGMENT_WIDTH 的最小寬度撐開，而是真的落在 Date.current。
          stages = [
            stage(planned_date: "2026-05-01", actual_date: "2026-06-01"),
            stage(planned_date: "2026-10-08", actual_date: nil)
          ]

          segment = helper.phase_gantt_chart_actual_segment(stages, 1, domain, width, "x")

          expect(segment).not_to be_nil
          expect(segment[:variant]).to eq(:in_progress)
          expect(segment[:diff_days]).to be_nil
          x2 = helper.phase_gantt_chart_x(Date.current, domain, width)
          expect(segment[:x] + segment[:width]).to eq(x2.round(2))
        end

        it "marks :delayed (not :in_progress) once today has passed the planned_date, even though still unfinished" do
          stages = [ stage(planned_date: "2026-09-08", actual_date: nil) ]

          segment = helper.phase_gantt_chart_actual_segment(stages, 0, domain, width, "x")

          expect(segment[:variant]).to eq(:delayed)
        end

        it "still returns nil for a not-yet-completed stage that is NOT the current stage — a later stage having a pre-scheduled record doesn't mean work has started on it" do
          stages = [
            stage(planned_date: "2026-01-01", actual_date: "2026-01-01"),
            stage(planned_date: "2026-10-08", actual_date: nil) # 有記錄但還沒開始，不是目前階段
          ]

          segment = helper.phase_gantt_chart_actual_segment(stages, 1, domain, width, "開發")

          expect(segment).to be_nil
        end
      end
    end
  end
end
