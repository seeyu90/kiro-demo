require "rails_helper"

# Property 4（需求 3.5）：錯誤格式一致性
# 對任意觸發 Actor 失敗的輸入，API 回應 JSON body 必須包含 error.code 與 error.message 兩個鍵
RSpec.describe "Api::ProjectProgress error format", type: :request do
  [
    { description: "simulate_error=sheet_not_found", params: { simulate_error: "sheet_not_found" } },
    { description: "simulate_error=invalid_data_format", params: { simulate_error: "invalid_data_format" } },
    { description: "simulate_error=access_denied", params: { simulate_error: "access_denied" } },
    { description: "simulate_error=internal_error", params: { simulate_error: "internal_error" } }
  ].each do |example_case|
    context "with #{example_case[:description]}" do
      before { get "/api/project_progress", params: example_case[:params] }

      it "returns a JSON body with error.code and error.message" do
        json = JSON.parse(response.body)

        expect(json).to have_key("error")
        expect(json["error"]).to have_key("code")
        expect(json["error"]).to have_key("message")
      end
    end
  end

  context "with a real fixture that is missing a required field" do
    before do
      stub_const("MockData::ProjectProgress::RECORDS", [
        {
          project_name: "P",
          task_name: "T",
          status: "",
          owner: "o",
          planned_completion_date: nil,
          actual_completion_date: nil,
          delay_days: nil
        }
      ])
      get "/api/project_progress"
    end

    it "returns a JSON body with error.code and error.message" do
      json = JSON.parse(response.body)

      expect(json).to have_key("error")
      expect(json["error"]).to have_key("code")
      expect(json["error"]).to have_key("message")
    end
  end
end
