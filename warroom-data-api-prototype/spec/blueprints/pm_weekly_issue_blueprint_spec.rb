require "rails_helper"

RSpec.describe PmWeeklyIssueBlueprint do
  expected_fields = %i[
    issue_id subject type status assigned_to project effective_due_date due_date_estimated
  ].freeze

  let(:record) do
    {
      issue_id: "4547", subject: "未匯入行事曆", type: "Complaint", tracker: "臭蟲",
      status: "新建立", assigned_to: "黃靖益", start_date: "2026-09-16", due_date: "2026-09-18",
      work_days: 3, project: "Virtuous HRM", total_hours: 0.75,
      effective_due_date: Date.new(2026, 9, 18), due_date_estimated: false
    }
  end

  it "renders exactly the fields the PM weekly report needs" do
    expect(described_class.render_as_hash(record).keys).to match_array(expected_fields)
  end

  it "carries the estimated flag so the view can mark SLA-derived due dates" do
    sla_record = record.merge(due_date: nil, effective_due_date: Date.new(2026, 9, 18), due_date_estimated: true)

    expect(described_class.render_as_hash(sla_record)[:due_date_estimated]).to be(true)
  end

  it "does not leak 306 detail-page fields (tracker／work_days／total_hours) into this page" do
    keys = described_class.render_as_hash(record).keys

    expect(keys).not_to include(:tracker, :work_days, :total_hours, :start_date, :due_date)
  end
end
