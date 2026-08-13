require "rails_helper"

RSpec.describe Sheets::FetchProjectProgress do
  subject(:actor) { described_class.new(ServiceActor::Result.to_result({})) }

  describe "#normalize_date" do
    # Property 2（需求 4.1、4.2）：日期格式一致性
    # 對任意符合支援格式的日期輸入，輸出必須符合 /\A\d{4}-\d{2}-\d{2}\z/
    context "when the input matches a supported format" do
      [
        "2024/1/5",
        "2024/12/31",
        "2024-1-5",
        "2024-12-31",
        "2024/01/05",
        "2024-02-29",
        "2024/2/29",
        "2000-1-1",
        "9999/9/9"
      ].each do |input|
        it "normalizes #{input.inspect} to ISO 8601 (YYYY-MM-DD)" do
          expect(actor.send(:normalize_date, input)).to match(/\A\d{4}-\d{2}-\d{2}\z/)
        end
      end
    end

    context "when the input does not match any supported format" do
      it "keeps the original string unchanged" do
        expect(actor.send(:normalize_date, "not-a-date")).to eq("not-a-date")
      end
    end

    # Property 3（需求 4.3）：空值保留
    # 對任意 nil 或空字串輸入，normalize_date 輸出必定為 nil
    context "when the input is nil or an empty string" do
      [ nil, "" ].each do |input|
        it "returns nil for #{input.inspect}" do
          expect(actor.send(:normalize_date, input)).to be_nil
        end
      end
    end
  end

  describe "#call" do
    subject(:result) { described_class.result }

    base_record = {
      status: "completed",
      owner: "Someone",
      planned_completion_date: nil,
      actual_completion_date: nil,
      delay_days: nil
    }

    [
      {
        description: "the real MockData::ProjectProgress::RECORDS",
        records: MockData::ProjectProgress::RECORDS
      },
      {
        description: "a single-project record set",
        records: [
          base_record.merge(project_name: "Solo Project", task_name: "Only task")
        ]
      },
      {
        description: "a multi-project record set with uneven task counts",
        records: [
          base_record.merge(project_name: "P1", task_name: "T1"),
          base_record.merge(project_name: "P1", task_name: "T2"),
          base_record.merge(project_name: "P2", task_name: "T3")
        ]
      }
    ].each do |example_case|
      context "with #{example_case[:description]}" do
        before { stub_const("MockData::ProjectProgress::RECORDS", example_case[:records]) }

        # Property 1（需求 2.1、2.2）：分組完整性
        # 對任意非空 RECORDS，grouped_data 所有陣列元素總數必須等於 RECORDS 筆數
        it "keeps every record in the grouped output" do
          expect(result.grouped_data.values.sum(&:size)).to eq(example_case[:records].size)
        end

        # Property 6（需求 2.1、2.3）：分組鍵值完整性
        # grouped_data 鍵值集合必須與原始 RECORDS 中 project_name 唯一值集合完全相同
        it "groups by exactly the unique project names present in RECORDS" do
          expect(result.grouped_data.keys).to match_array(example_case[:records].map { |r| r[:project_name] }.uniq)
        end
      end
    end

    context "with normal data" do
      it "succeeds and returns grouped_data keyed by project_name" do
        expect(result).to be_success
        expect(result.grouped_data.keys).to match_array(MockData::ProjectProgress::RECORDS.map { |r| r[:project_name] }.uniq)
        expect(result.grouped_data.values.sum(&:size)).to eq(MockData::ProjectProgress::RECORDS.size)
      end

      it "normalizes the date fields of every task" do
        result.grouped_data.each_value do |tasks|
          tasks.each do |task|
            expect(task[:planned_completion_date]).to match(/\A\d{4}-\d{2}-\d{2}\z/).or(be_nil)
            expect(task[:actual_completion_date]).to match(/\A\d{4}-\d{2}-\d{2}\z/).or(be_nil)
          end
        end
      end
    end

    context "with a real fixture that is missing a required field" do
      before do
        stub_const("MockData::ProjectProgress::RECORDS", [
          base_record.merge(project_name: "P", task_name: "T", status: "")
        ])
      end

      it "fails with failure_code: :invalid_data_format" do
        expect(result).not_to be_success
        expect(result.failure_code).to eq(:invalid_data_format)
      end
    end

    context "with simulate_error" do
      {
        sheet_not_found: :sheet_not_found,
        invalid_data_format: :invalid_data_format,
        access_denied: :access_denied,
        internal_error: :internal_error
      }.each do |simulate_error, expected_failure_code|
        it "returns failure_code: #{expected_failure_code.inspect} for simulate_error: #{simulate_error.inspect}" do
          result = described_class.result(simulate_error: simulate_error)

          expect(result).not_to be_success
          expect(result.failure_code).to eq(expected_failure_code)
        end
      end
    end
  end
end
