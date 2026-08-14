require "rails_helper"

RSpec.describe DailyKpiBlueprint do
  expected_fields = %i[date complaint testing other total].freeze

  record_examples = [
    { date: "2026-08-13", complaint: 0, testing: 1, other: 0, total: 1 },
    { date: "2026-08-01", complaint: 0, testing: 0, other: 0, total: 0 }
  ].freeze

  record_examples.each do |record|
    it "renders exactly the expected fields for #{record[:date].inspect}" do
      expect(described_class.render_as_hash(record).keys).to match_array(expected_fields)
    end
  end
end
