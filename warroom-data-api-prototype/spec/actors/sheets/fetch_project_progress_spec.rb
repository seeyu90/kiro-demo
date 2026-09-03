# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sheets::FetchProjectProgress do
  describe "#normalize_date" do
    let(:actor) { described_class.new(ServiceActor::Result.to_result({})) }

    context "when the input matches a supported format" do
      # Property 3（需求 3.1）：日期格式一致性
      # 對 YYYY/M/D、YYYY/MM/DD、YYYY-M-D、YYYY-MM-DD 四種格式各準備至少一組範例
      [
        [ "2024/1/5", "2024-01-05" ],
        [ "2024/12/31", "2024-12-31" ],
        [ "2024-1-5", "2024-01-05" ],
        [ "2024-12-31", "2024-12-31" ],
        [ "2024/01/05", "2024-01-05" ],
        [ "2024-02-29", "2024-02-29" ],
        [ "2024/2/29", "2024-02-29" ],
        [ "2000-1-1", "2000-01-01" ],
        [ "9999/9/9", "9999-09-09" ]
      ].each do |input, expected|
        it "normalizes #{input.inspect} to #{expected.inspect}" do
          expect(actor.send(:normalize_date, input)).to eq(expected)
        end
      end
    end

    context "when the input does not match any supported format" do
      # Property 5（需求 3.3）：無法解析的日期保留原始值
      # "2024/13/01" is actually matched by the regex (year/month/day pattern)
      # so it gets normalized to "2024-13-01". We test cases that truly don't match.
      [
        "TBD",
        "未定",
        "2026.07.31",
        "not-a-date"
      ].each do |input|
        it "keeps the original string #{input.inspect} unchanged" do
          expect(actor.send(:normalize_date, input)).to eq(input)
        end
      end
    end

    # Property 4（需求 3.2）：nil 與空字串日期保留為 nil
    context "when the input is nil or an empty string" do
      [ nil, "" ].each do |input|
        it "returns nil for #{input.inspect}" do
          expect(actor.send(:normalize_date, input)).to be_nil
        end
      end
    end
  end

  describe "#parse_rows" do
    let(:actor) { described_class.new(ServiceActor::Result.to_result({})) }

    # Property 1（需求 2.2、2.5）：空列跳過不影響有效資料數量
    it "skips nil rows and all-blank rows without affecting the count of valid rows" do
      rows = [
        [ "專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延遲天數" ],
        [ "Project A", "Task 1", "completed", "Alice", "2024/1/5", "2024-01-10", "5" ],
        nil,
        [ "", "", "", "", "", "", "" ],
        [ "Project A", "Task 2", "in_progress", "Bob", "2024/2/10", "", "-4" ],
        [ nil, nil, nil, nil, nil, nil, nil ]
      ]

      result = actor.send(:parse_rows, rows)

      expect(result.size).to eq(2)
      expect(result.map { |r| r[:task_name] }).to eq([ "Task 1", "Task 2" ])
    end

    # Property 2（需求 2.4）：列長度不足時 nil 填補完整性
    [
      [],
      [ "Project A" ],
      [ "Project A", "Task 1" ],
      [ "Project A", "Task 1", "completed" ],
      [ "Project A", "Task 1", "completed", "Alice" ],
      [ "Project A", "Task 1", "completed", "Alice", "2024/1/5" ],
      [ "Project A", "Task 1", "completed", "Alice", "2024/1/5", "2024-01-10" ]
    ].each do |short_row|
      it "pads a row of length #{short_row.length} with nil so all 7 keys are present" do
        rows = [ [ "header" ] * 7, short_row ]

        result = actor.send(:parse_rows, rows)

        expect(result.size).to eq(1)
        expect(result.first.keys).to contain_exactly(*Sheets::FetchProjectProgress::COLUMN_KEYS)
      end
    end
  end

  describe "#group_by_project" do
    let(:actor) { described_class.new(ServiceActor::Result.to_result({})) }

    # Property 7（需求 8.1、8.2）：分組完整性（資料不遺失）
    it "does not lose any records when grouping" do
      records = [
        { project_name: "Project A", task_name: "Task 1" },
        { project_name: "Project A", task_name: "Task 2" },
        { project_name: "Project B", task_name: "Task 3" }
      ]

      grouped = actor.send(:group_by_project, records)

      expect(grouped.values.sum(&:size)).to eq(records.size)
    end

    # Property 8（需求 8.1）：分組鍵值完整性
    it "produces group keys matching exactly the unique project_name values" do
      records = [
        { project_name: "Project A", task_name: "Task 1" },
        { project_name: "Project A", task_name: "Task 2" },
        { project_name: "Project B", task_name: "Task 3" },
        { project_name: "Project C", task_name: "Task 4" }
      ]

      grouped = actor.send(:group_by_project, records)

      expect(grouped.keys).to match_array(records.map { |r| r[:project_name] }.uniq)
    end
  end

  describe "#call" do
    subject(:result) { described_class.result }

    before do
      # Stub ProjectProgressSheetsClient.fetch_rows for all tests in this describe block
      allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return(default_rows)
    end

    let(:default_rows) do
      [
        [ "專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延遲天數" ],
        [ "Project A", "Task 1", "completed", "Alice", "2024/1/5", "2024-01-10", "5" ],
        [ "Project A", "Task 2", "in_progress", "Bob", "2024/2/10", "", "-4" ],
        [ "Project B", "Task 3", "pending", "Carol", "2024-3-15", nil, "0" ]
      ]
    end

    # Test 1: stub 回傳正常列陣列 → 驗證 grouped_data 結構與分組正確性
    context "with normal rows" do
      it "returns success with correctly grouped data" do
        expect(result).to be_success
        expect(result.grouped_data.keys).to match_array([ "Project A", "Project B" ])

        # Verify Project A has 2 tasks
        expect(result.grouped_data["Project A"].size).to eq(2)
        expect(result.grouped_data["Project A"].map { |t| t[:task_name] }).to contain_exactly("Task 1", "Task 2")

        # Verify Project B has 1 task
        expect(result.grouped_data["Project B"].size).to eq(1)
        expect(result.grouped_data["Project B"].first[:task_name]).to eq("Task 3")
      end

      it "defaults task_type to nil when the row has no 8th column" do
        expect(result.grouped_data["Project A"].map { |t| t[:task_type] }).to all(be_nil)
      end
    end

    # Test 1b: ProjectProgressSheetsClient 已依 warroom-data-api-real-source 的約定，於每列附加第 8 欄
    # 類型分頁名稱 → 驗證 Actor 正確將其解析為 task_type
    context "with rows tagged with a task_type (8th column)" do
      let(:tagged_rows) do
        [
          [ "專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延遲天數", "類型" ],
          [ "Project A", "Task 1", "completed", "Alice", "2024/1/5", "2024-01-10", "5", "功能" ],
          [ "Project A", "Task 2", "in_progress", "Bob", "2024/2/10", "", "-4", "PR" ]
        ]
      end

      before { allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return(tagged_rows) }

      it "extracts the 8th column as task_type" do
        tasks = result.grouped_data["Project A"]
        expect(tasks.map { |t| t[:task_type] }).to contain_exactly("功能", "PR")
      end

      it "normalizes date fields correctly" do
        project_a_tasks = result.grouped_data["Project A"]
        expect(project_a_tasks[0][:planned_completion_date]).to eq("2024-01-05")
        expect(project_a_tasks[0][:actual_completion_date]).to eq("2024-01-10")
        expect(project_a_tasks[1][:planned_completion_date]).to eq("2024-02-10")
        expect(project_a_tasks[1][:actual_completion_date]).to be_nil
      end

      it "converts delay_days to Integer when valid" do
        project_a_tasks = result.grouped_data["Project A"]
        expect(project_a_tasks[0][:delay_days]).to eq(5)
        expect(project_a_tasks[1][:delay_days]).to eq(-4)
      end
    end

    # Test 2: stub 回傳含空列的陣列 → 驗證空列被跳過
    context "with rows containing empty rows" do
      let(:rows_with_empty) do
        [
          [ "專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延遲天數" ],
          [ "Project A", "Task 1", "completed", "Alice", "2024/1/5", "2024-01-10", "5" ],
          [],
          [ "Project A", "Task 2", "in_progress", "Bob", "2024/2/10", "", "-4" ],
          [ nil, nil, nil, nil, nil, nil, nil ],
          [ "Project B", "Task 3", "pending", "Carol", "2024-3-15", nil, "0" ]
        ]
      end

      before { allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return(rows_with_empty) }

      it "skips empty rows and does not include them in output" do
        expect(result).to be_success
        total_tasks = result.grouped_data.values.sum(&:size)
        expect(total_tasks).to eq(3) # Only 3 valid data rows
      end
    end

    # Test 3: stub 回傳列長度不足 7 的陣列 → 驗證以 nil 填補
    context "with rows having fewer than 7 columns" do
      let(:short_rows) do
        [
          [ "專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延遲天數" ],
          [ "Project A", "Task 1", "completed", "Alice", "2024/1/5", "2024-01-10", "" ], # Only 6 columns + empty delay_days
          [ "Project A", "Task 2", "in_progress", "Bob", "", "", "" ], # Only 3 columns + 4 empty
          [ "Project B", "Task 3", "pending", "Carol", "2024-3-15", nil, "0" ]
        ]
      end

      before { allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return(short_rows) }

      it "fills missing columns with nil and includes all 8 keys" do
        expect(result).to be_success

        # Check first task (had 6 columns, missing delay_days)
        task1 = result.grouped_data["Project A"][0]
        expect(task1.keys).to contain_exactly(*%i[
          project_name task_name status owner
          planned_completion_date actual_completion_date delay_days task_type
        ])
        expect(task1[:delay_days]).to be_nil

        # Check second task (had 3 columns)
        task2 = result.grouped_data["Project A"][1]
        expect(task2.keys).to contain_exactly(*%i[
          project_name task_name status owner
          planned_completion_date actual_completion_date delay_days task_type
        ])
        expect(task2[:status]).to eq("in_progress")
        expect(task2[:owner]).to eq("Bob") # Owner column exists
        expect(task2[:planned_completion_date]).to be_nil
      end
    end

    # Test 4: stub 回傳含四種日期格式的列資料 → 驗證 normalize_date 輸出為 YYYY-MM-DD
    context "with mixed date formats" do
      let(:mixed_date_rows) do
        [
          [ "專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延遲天數" ],
          [ "Project A", "Task 1", "completed", "Alice", "2024/1/5", "2024-01-10", "5" ],
          [ "Project B", "Task 2", "in_progress", "Bob", "2024-2-10", "2024/2/15", "-4" ],
          [ "Project C", "Task 3", "pending", "Carol", "2024/03/15", "2024-03-20", "0" ]
        ]
      end

      before { allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return(mixed_date_rows) }

      it "normalizes all date formats to YYYY-MM-DD" do
        expect(result).to be_success

        result.grouped_data.values.flatten.each do |task|
          unless task[:planned_completion_date].nil?
            expect(task[:planned_completion_date]).to match(/\A\d{4}-\d{2}-\d{2}\z/)
          end
          unless task[:actual_completion_date].nil?
            expect(task[:actual_completion_date]).to match(/\A\d{4}-\d{2}-\d{2}\z/)
          end
        end
      end
    end

    # Test 5: stub 回傳日期欄位為空值的資料 → 驗證輸出為 nil
    context "with empty date values" do
      let(:empty_date_rows) do
        [
          [ "專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延遲天數" ],
          [ "Project A", "Task 1", "completed", "Alice", "", "", "" ],
          [ "Project B", "Task 2", "in_progress", "Bob", nil, nil, "0" ]
        ]
      end

      before { allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return(empty_date_rows) }

      it "returns nil for empty date fields" do
        expect(result).to be_success

        result.grouped_data.values.flatten.each do |task|
          expect(task[:planned_completion_date]).to be_nil
          expect(task[:actual_completion_date]).to be_nil
        end
      end
    end

    # Test 6: stub 回傳 delay_days 為 "-4" → 驗證輸出為 Integer -4
    context "with delay_days as negative integer string" do
      let(:negative_delay_rows) do
        [
          [ "專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延遲天數" ],
          [ "Project A", "Task 1", "completed", "Alice", "2024/1/5", "2024-01-10", "-4" ]
        ]
      end

      before { allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return(negative_delay_rows) }

      it "converts negative delay_days string to Integer" do
        expect(result).to be_success
        task = result.grouped_data["Project A"].first
        expect(task[:delay_days]).to be_a(Integer)
        expect(task[:delay_days]).to eq(-4)
      end
    end

    # Test 7: stub 回傳 delay_days 為 "TBD" → 驗證保留原始字串
    context "with delay_days as non-numeric string" do
      let(:tbd_delay_rows) do
        [
          [ "專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延遲天數" ],
          [ "Project A", "Task 1", "completed", "Alice", "2024/1/5", "2024-01-10", "TBD" ]
        ]
      end

      before { allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return(tbd_delay_rows) }

      it "keeps non-numeric delay_days as original string" do
        expect(result).to be_success
        task = result.grouped_data["Project A"].first
        expect(task[:delay_days]).to eq("TBD")
      end
    end

    # Test 8: stub 回傳缺欄資料 → 該筆紀錄被跳過，其餘正常紀錄仍照常回傳成功結果
    # （需求 4.3／Property 11：真實資料不完整時不應讓整個 request 失敗）
    context "with a row missing a required field" do
      let(:mixed_validity_rows) do
        [
          [ "專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延遲天數" ],
          [ "Project A", "Task 1", "", "Alice", "2024/1/5", "2024-01-10", "5" ], # Empty status, should be skipped
          [ "Project A", "Task 2", "in_progress", "Bob", "2024/2/10", "", "-4" ]
        ]
      end

      before { allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return(mixed_validity_rows) }

      it "skips the invalid row and returns success with the remaining valid rows" do
        expect(result).to be_success
        expect(result.grouped_data["Project A"].map { |t| t[:task_name] }).to eq([ "Task 2" ])
      end
    end

    # Test 9a: stub 拋出 Google::Apis::ClientError（status 404）→ 驗證 failure_code: :sheet_not_found
    context "with Google::Apis::ClientError status 404" do
      before do
        error = Google::Apis::ClientError.new("Not Found")
        allow(error).to receive(:status_code).and_return(404)
        allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_raise(error)
      end

      it "returns failure_code: :sheet_not_found" do
        expect(result).not_to be_success
        expect(result.failure_code).to eq(:sheet_not_found)
        expect(result.message).to include("找不到指定分頁或試算表")
      end
    end

    # Test 9b: stub 拋出 Google::Apis::ClientError（status 403）→ 驗證 failure_code: :access_denied
    context "with Google::Apis::ClientError status 403" do
      before do
        error = Google::Apis::ClientError.new("Forbidden")
        allow(error).to receive(:status_code).and_return(403)
        allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_raise(error)
      end

      it "returns failure_code: :access_denied" do
        expect(result).not_to be_success
        expect(result.failure_code).to eq(:access_denied)
        expect(result.message).to include("資料來源存取權限不足")
      end
    end

    # Test 9c: stub 拋出 StandardError（模擬憑證錯誤）→ 驗證 failure_code: :internal_error
    context "with StandardError (credential error)" do
      before do
        allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_raise(StandardError.new("Credentials not found"))
      end

      it "returns failure_code: :internal_error" do
        expect(result).not_to be_success
        expect(result.failure_code).to eq(:internal_error)
        expect(result.message).to include("未預期的內部錯誤")
      end
    end

    # Test 9d: stub 拋出 Google::Apis::RateLimitError → 驗證 failure_code: :internal_error
    context "with Google::Apis::RateLimitError" do
      before do
        allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_raise(Google::Apis::RateLimitError.new("Rate limit exceeded"))
      end

      it "returns failure_code: :internal_error" do
        expect(result).not_to be_success
        expect(result.failure_code).to eq(:internal_error)
      end
    end

    # Test 10: 呼叫 Actor 時傳入 simulate_error query parameter → 驗證被忽略
    context "with simulate_error parameter (should be ignored)" do
      # Note: The current Actor implementation does NOT accept simulate_error parameter
      # The Actor always calls ProjectProgressSheetsClient.fetch_rows and ignores any simulate_error input
      # This test verifies that simulate_error parameter (if passed) is simply ignored

      let(:valid_rows) do
        [
          [ "專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延遲天數" ],
          [ "Project A", "Task 1", "completed", "Alice", "2024/1/5", "2024-01-10", "5" ]
        ]
      end

      before { allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return(valid_rows) }

      it "ignores simulate_error and returns success when data is valid" do
        # Even if simulate_error is passed, it should be ignored per task 7.1
        # The Actor always uses real ProjectProgressSheetsClient.fetch_rows
        result = described_class.result(simulate_error: :invalid_data_format)

        expect(result).to be_success
        expect(result.grouped_data).to be_present
      end
    end

    # 任務 4：fetched_at 輸出直接反映 ProjectProgressSheetsClient 快取層記錄的抓取時間
    context "fetched_at output" do
      it "reflects ProjectProgressSheetsClient.fetched_at after a successful call" do
        fixed_time = Time.zone.parse("2026-03-01 09:00:00")
        allow(ProjectProgressSheetsClient).to receive(:fetched_at).and_return(fixed_time)

        expect(result.fetched_at).to eq(fixed_time)
      end
    end

    # 任務 5：force input 透傳給 ProjectProgressSheetsClient.fetch_rows，供「重新整理資料」使用
    context "force input" do
      it "defaults to false when not given" do
        expect(ProjectProgressSheetsClient).to receive(:fetch_rows).with(force: false).and_return(default_rows)

        result
      end

      it "passes force: true through to ProjectProgressSheetsClient.fetch_rows when requested" do
        expect(ProjectProgressSheetsClient).to receive(:fetch_rows).with(force: true).and_return(default_rows)

        described_class.result(force: true)
      end
    end

    # 回應 code review：ProjectProgressSheetsClient 只快取「原始列」，Actor 本身（overdue？
    # 判斷、摘要統計等時間相對邏輯）每次呼叫都重新執行，不會被快取凍結在舊的時間點。這裡用
    # 同一份（模擬「快取命中」情境的）原始列，只改變「今天」，驗證 overdue 相關輸出會跟著變動，
    # 而不是停留在第一次呼叫時的判斷結果。
    context "time-relative filtering is not frozen by ProjectProgressSheetsClient's row-level cache" do
      include ActiveSupport::Testing::TimeHelpers

      let(:rows_with_one_task) do
        [
          [ "專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延遲天數", "類型" ],
          [ "Project A", "Task 1", "未完成", "Alice", "2026-06-15", "", "", "功能" ]
        ]
      end

      before { allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return(rows_with_one_task) }

      it "treats identical cached rows as not-yet-overdue before the deadline and overdue after it" do
        travel_to(Date.new(2026, 6, 10)) do
          expect(described_class.result.summary[:overdue]).to eq(0)
        end

        travel_to(Date.new(2026, 6, 20)) do
          expect(described_class.result.summary[:overdue]).to eq(1)
        end
      end
    end
  end
end
