require "rails_helper"

RSpec.describe IssueBlueprint do
  expected_fields = %i[
    issue_id subject type tracker status assigned_to start_date due_date work_days project total_hours
  ].freeze

  record_examples = [
    {
      issue_id: "4547", subject: "未匯入行事曆", type: "Complaint", tracker: "臭蟲",
      status: "已結束", assigned_to: "黃靖益", start_date: "2026-01-02", due_date: "2026-01-06",
      work_days: 3, project: "Virtuous HRM", total_hours: 0.75
    },
    {
      issue_id: "5165", subject: "白名單申請時間錯誤", type: "TestingBug", tracker: "臭蟲",
      status: "新建立", assigned_to: nil, start_date: "2026-08-12", due_date: nil,
      work_days: nil, project: "Virtuous HRM", total_hours: nil
    }
  ].freeze

  record_examples.each do |record|
    it "renders exactly the expected fields for #{record[:issue_id].inspect}" do
      expect(described_class.render_as_hash(record).keys).to match_array(expected_fields)
    end
  end

  it "does not expose an :attribution or :sheet_name key (view-only derived fields)" do
    record = record_examples.first
    keys = described_class.render_as_hash(record).keys

    expect(keys).not_to include(:attribution, :sheet_name)
  end
end
