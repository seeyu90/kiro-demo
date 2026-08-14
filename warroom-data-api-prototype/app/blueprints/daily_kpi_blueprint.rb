class DailyKpiBlueprint < Blueprinter::Base
  identifier :date

  fields :date, :complaint, :testing, :other, :total
end
