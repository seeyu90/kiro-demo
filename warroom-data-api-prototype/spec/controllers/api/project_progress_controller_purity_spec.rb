require "rails_helper"

# Property 5（需求 8.2）：Controller 純粹性
# Controller action 原始碼中不得直接參照 MockData 模組或呼叫任何日期轉換方法
RSpec.describe "Api::ProjectProgressController purity" do
  let(:source) do
    File.read(Rails.root.join("app/controllers/api/project_progress_controller.rb"))
  end

  it "does not reference the MockData module" do
    expect(source).not_to match(/MockData/)
  end

  it "does not call date-conversion methods" do
    expect(source).not_to match(/normalize_date|Date\.parse|\.strftime/)
  end
end
