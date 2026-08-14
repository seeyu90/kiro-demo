class ProjectBreakdownBlueprint < Blueprinter::Base
  identifier :project

  fields :project, :complaint, :testing, :other, :total
end
