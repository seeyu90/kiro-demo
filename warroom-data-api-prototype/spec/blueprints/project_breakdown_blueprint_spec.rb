require "rails_helper"

RSpec.describe ProjectBreakdownBlueprint do
  expected_fields = %i[project complaint testing other total].freeze

  record_examples = [
    { project: "Virtuous HRM", complaint: 1, testing: 1, other: 0, total: 2 },
    { project: "未分類", complaint: 0, testing: 0, other: 1, total: 1 }
  ].freeze

  record_examples.each do |record|
    it "renders exactly the expected fields for #{record[:project].inspect}" do
      expect(described_class.render_as_hash(record).keys).to match_array(expected_fields)
    end
  end
end
