require "rails_helper"

# Property 9（需求 4.1、4.2、4.3、4.4、4.5）：錯誤回應格式一致性
# 對 SheetsApiClient.fetch_rows 拋出的各種例外情境，API 回應 JSON body 必須包含 error.code 與 error.message 兩個鍵
RSpec.describe "Api::ProjectProgress error format", type: :request do
  [
    { description: "Google::Apis::ClientError (404)", error: Google::Apis::ClientError.new("Not Found", status_code: 404) },
    { description: "Google::Apis::ClientError (403)", error: Google::Apis::ClientError.new("Forbidden", status_code: 403) },
    { description: "unexpected StandardError", error: StandardError.new("Credentials not found") }
  ].each do |example_case|
    context "with #{example_case[:description]}" do
      before do
        allow(SheetsApiClient).to receive(:fetch_rows).and_raise(example_case[:error])
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
end
