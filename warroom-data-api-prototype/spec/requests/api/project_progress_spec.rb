require "rails_helper"

RSpec.describe "Api::ProjectProgress", type: :request do
  let(:header_row) { ["專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延誤"] }
  let(:valid_rows) do
    [
      header_row,
      ["Project A", "Task 1", "已完成", "Alice", "2026/1/5", "2026/1/6", "1"],
      ["Project A", "Task 2", "進行中", "Bob", "2026/2/10", "", ""],
      ["Project B", "Task 3", "已確認", "Carol", "2026-3-1", "2026-3-1", "0"]
    ]
  end

  describe "GET /api/project_progress" do
    before do
      allow(SheetsApiClient).to receive(:fetch_rows).and_return(valid_rows)
      get "/api/project_progress"
    end

    it "returns HTTP 200" do
      expect(response).to have_http_status(200)
    end

    it "returns JSON with grouped project data" do
      json = JSON.parse(response.body)

      expect(json).to be_a(Hash)
      expect(json.keys).to match_array(["Project A", "Project B"])
      expect(json["Project A"].map { |t| t["task_name"] }).to match_array(["Task 1", "Task 2"])
      expect(json["Project B"].map { |t| t["task_name"] }).to eq(["Task 3"])

      json.each_value do |tasks|
        tasks.each do |task|
          expect(task.keys).to match_array(%w[project_name task_name status owner planned_completion_date actual_completion_date delay_days task_type])
        end
      end
    end

    it "normalizes all date fields to ISO 8601 format" do
      json = JSON.parse(response.body)

      json.each_value do |tasks|
        tasks.each do |task|
          %w[planned_completion_date actual_completion_date].each do |field|
            value = task[field]
            expect(value).to match(/\A\d{4}-\d{2}-\d{2}\z/) if value.present?
          end
        end
      end
    end

    it "converts delay_days to Integer or nil" do
      json = JSON.parse(response.body)
      task1 = json["Project A"].find { |t| t["task_name"] == "Task 1" }
      task2 = json["Project A"].find { |t| t["task_name"] == "Task 2" }

      expect(task1["delay_days"]).to eq(1)
      expect(task2["delay_days"]).to be_nil
      expect(task2["actual_completion_date"]).to be_nil
    end
  end

  describe "GET /api/project_progress when SheetsApiClient raises ClientError (404)" do
    before do
      error = Google::Apis::ClientError.new("Not Found")
      allow(error).to receive(:status_code).and_return(404)
      allow(SheetsApiClient).to receive(:fetch_rows).and_raise(error)
      get "/api/project_progress"
    end

    it "returns HTTP 404" do
      expect(response).to have_http_status(404)
    end

    it "returns unified error format" do
      json = JSON.parse(response.body)

      expect(json).to have_key("error")
      expect(json["error"]).to have_key("code")
      expect(json["error"]).to have_key("message")
      expect(json["error"]["code"]).to eq("sheet_not_found")
    end
  end

  describe "GET /api/project_progress when SheetsApiClient raises ClientError (403)" do
    before do
      error = Google::Apis::ClientError.new("Forbidden")
      allow(error).to receive(:status_code).and_return(403)
      allow(SheetsApiClient).to receive(:fetch_rows).and_raise(error)
      get "/api/project_progress"
    end

    it "returns HTTP 403" do
      expect(response).to have_http_status(403)
    end

    it "returns unified error format" do
      json = JSON.parse(response.body)

      expect(json["error"]["code"]).to eq("access_denied")
      expect(json["error"]).to have_key("message")
    end
  end

  # 需求 4.3：真實資料中缺必要欄位的列會被跳過、不納入結果，其餘正常資料仍回傳成功（非 422）
  describe "GET /api/project_progress when a row is missing a required field" do
    let(:rows_with_blank_field) do
      [
        header_row,
        ["", "Task 1", "已完成", "Alice", "2026/1/5", "2026/1/6", "1"], # blank project_name, skipped
        ["Project A", "Task 2", "進行中", "Bob", "2026/2/10", "", ""]
      ]
    end

    before do
      allow(SheetsApiClient).to receive(:fetch_rows).and_return(rows_with_blank_field)
      get "/api/project_progress"
    end

    it "skips the invalid row and returns HTTP 200 with the remaining valid data" do
      expect(response).to have_http_status(200)

      json = JSON.parse(response.body)
      expect(json.keys).to eq(["Project A"])
      expect(json["Project A"].map { |t| t["task_name"] }).to eq(["Task 2"])
    end
  end

  describe "GET /api/project_progress when SheetsApiClient raises StandardError" do
    before do
      allow(SheetsApiClient).to receive(:fetch_rows).and_raise(StandardError.new("憑證載入失敗"))
      get "/api/project_progress"
    end

    it "returns HTTP 500" do
      expect(response).to have_http_status(500)
    end

    it "returns unified error format" do
      json = JSON.parse(response.body)

      expect(json["error"]["code"]).to eq("internal_error")
      expect(json["error"]).to have_key("message")
    end
  end

  # 需求 5.3：simulate_error 機制已移除，query parameter 被忽略、不產生任何效果
  describe "GET /api/project_progress?simulate_error=sheet_not_found" do
    before do
      allow(SheetsApiClient).to receive(:fetch_rows).and_return(valid_rows)
      get "/api/project_progress", params: { simulate_error: "sheet_not_found" }
    end

    it "ignores the parameter and returns HTTP 200 with normal data" do
      expect(response).to have_http_status(200)

      json = JSON.parse(response.body)
      expect(json.keys).to match_array(["Project A", "Project B"])
    end
  end
end
