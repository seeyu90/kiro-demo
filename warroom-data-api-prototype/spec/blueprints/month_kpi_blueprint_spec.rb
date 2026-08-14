require "rails_helper"

RSpec.describe MonthKpiBlueprint do
  expected_fields = %i[
    year_month
    complaint
    testing
    total_bug
    block_rate
    completed
    unresolved
    avg_days
    sla_rate
  ].freeze

  record_examples = [
    {
      year_month: "2026-08", complaint: 15, testing: 9, total_bug: 24, block_rate: 37.5,
      completed: 6, unresolved: 3, avg_days: 3.1, sla_rate: 25.0
    },
    {
      year_month: "2026-07", complaint: 0, testing: 0, total_bug: 0, block_rate: nil,
      completed: 0, unresolved: 0, avg_days: nil, sla_rate: nil
    }
  ].freeze

  record_examples.each do |record|
    it "renders exactly the expected fields for #{record[:year_month].inspect}" do
      expect(described_class.render_as_hash(record).keys).to match_array(expected_fields)
    end
  end
end
