require "rails_helper"

RSpec.describe ProjectTaskBlueprint do
  # Property 7（需求 8.4）：Blueprint 欄位完整性
  # 對任意任務紀錄，render_as_hash 輸出必須恰好包含全部 7 個欄位，不多不少
  EXPECTED_FIELDS = %i[
    project_name
    task_name
    status
    owner
    planned_completion_date
    actual_completion_date
    delay_days
  ].freeze

  MockData::ProjectProgress::RECORDS.each do |record|
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
      delay_days: nil
    }

    expect(described_class.render_as_hash(minimal_record).keys).to match_array(EXPECTED_FIELDS)
  end
end
