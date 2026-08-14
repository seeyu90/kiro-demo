class MonthKpiBlueprint < Blueprinter::Base
  identifier :year_month

  fields :year_month, :complaint, :testing, :total_bug, :block_rate,
         :completed, :unresolved, :avg_days, :sla_rate
end
