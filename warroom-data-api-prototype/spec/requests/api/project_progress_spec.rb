require "rails_helper"

RSpec.describe "Api::ProjectProgress", type: :request do
  describe "GET /api/project_progress" do
    before do
      get "/api/project_progress"
    end

    it "returns HTTP 200" do
      expect(response).to have_http_status(200)
    end

    it "returns JSON with grouped project data" do
      json = JSON.parse(response.body)

      expect(json).to be_a(Hash)
      expect(json.keys).to match_array(MockData::ProjectProgress::RECORDS.map { |r| r[:project_name] }.uniq)

      json.each_value do |tasks|
        expect(tasks).to be_an(Array)
        tasks.each do |task|
          expect(task.keys).to match_array(%w[project_name task_name status owner planned_completion_date actual_completion_date delay_days])
        end
      end
    end

    it "normalizes all date fields to ISO 8601 format" do
      json = JSON.parse(response.body)

      json.each_value do |tasks|
        tasks.each do |task|
          date_fields = %w[planned_completion_date actual_completion_date]
          date_fields.each do |field|
            value = task[field]
            if value.present?
              expect(value).to match(/\A\d{4}-\d{2}-\d{2}\z/)
            end
          end
        end
      end
    end
  end

  describe "GET /api/project_progress with simulate_error=sheet_not_found" do
    before do
      get "/api/project_progress", params: { simulate_error: "sheet_not_found" }
    end

    it "returns HTTP 404" do
      expect(response).to have_http_status(404)
    end

    it "returns unified error format" do
      json = JSON.parse(response.body)

      expect(json).to have_key("error")
      expect(json["error"]).to be_a(Hash)
      expect(json["error"]).to have_key("code")
      expect(json["error"]).to have_key("message")
      expect(json["error"]["code"]).to eq("sheet_not_found")
    end
  end

  describe "GET /api/project_progress with simulate_error=invalid_data_format" do
    before do
      get "/api/project_progress", params: { simulate_error: "invalid_data_format" }
    end

    it "returns HTTP 422" do
      expect(response).to have_http_status(422)
    end

    it "returns unified error format" do
      json = JSON.parse(response.body)

      expect(json).to have_key("error")
      expect(json["error"]).to have_key("code")
      expect(json["error"]).to have_key("message")
      expect(json["error"]["code"]).to eq("invalid_data_format")
    end
  end

  describe "GET /api/project_progress with simulate_error=access_denied" do
    before do
      get "/api/project_progress", params: { simulate_error: "access_denied" }
    end

    it "returns HTTP 403" do
      expect(response).to have_http_status(403)
    end

    it "returns unified error format" do
      json = JSON.parse(response.body)

      expect(json).to have_key("error")
      expect(json["error"]).to have_key("code")
      expect(json["error"]).to have_key("message")
      expect(json["error"]["code"]).to eq("access_denied")
    end
  end

  describe "GET /api/project_progress with simulate_error=internal_error" do
    before do
      get "/api/project_progress", params: { simulate_error: "internal_error" }
    end

    it "returns HTTP 500" do
      expect(response).to have_http_status(500)
    end

    it "returns unified error format" do
      json = JSON.parse(response.body)

      expect(json).to have_key("error")
      expect(json["error"]).to have_key("code")
      expect(json["error"]).to have_key("message")
      expect(json["error"]["code"]).to eq("internal_error")
    end
  end
end
