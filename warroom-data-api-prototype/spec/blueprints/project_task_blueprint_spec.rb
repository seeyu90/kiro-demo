require "rails_helper"

RSpec.describe ProjectTaskBlueprint do
  # Property 10（需求 6.1、7.3）：Blueprint 欄位完整性
  # 對真實任務 Hash（非 MockData）範例，render_as_hash 輸出必須恰好包含全部 7 個欄位，不多不少
  EXPECTED_FIELDS = %i[
    project_name
    task_name
    status
    owner
    planned_completion_date
    actual_completion_date
    delay_days
    task_type
  ].freeze

  REAL_TASK_EXAMPLES = [
    {
      project_name: "Project A",
      task_name: "Task 1",
      status: "completed",
      owner: "Alice",
      planned_completion_date: "2024-01-05",
      actual_completion_date: "2024-01-10",
      delay_days: 5,
      task_type: "功能"
    },
    {
      project_name: "Project B",
      task_name: "Task 2",
      status: "pending",
      owner: "Carol",
      planned_completion_date: nil,
      actual_completion_date: nil,
      delay_days: nil,
      task_type: "PR"
    }
  ].freeze

  REAL_TASK_EXAMPLES.each do |record|
    it "renders exactly the 7 expected fields for #{record[:task_name].inspect}" do
      expect(described_class.render_as_hash(record).keys).to match_array(EXPECTED_FIELDS)
    end
  end

  it "renders exactly the 7 expected fields for a minimal record" do
    minimal_record = {
      project_name: "P",
      task_name: "T",
      status: "s",
      owner: "o",
      planned_completion_date: nil,
      actual_completion_date: nil,
      delay_days: nil,
      task_type: nil
    }

    expect(described_class.render_as_hash(minimal_record).keys).to match_array(EXPECTED_FIELDS)
  end
end
