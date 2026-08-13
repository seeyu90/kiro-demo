require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  describe "GET /dashboard" do
    before { get "/dashboard" }

    it "returns HTTP 200" do
      expect(response).to have_http_status(200)
    end

    it "renders the project dropdown with all project names" do
      expect(response.body).to include("全部專案")

      MockData::ProjectProgress::RECORDS.map { |r| r[:project_name] }.uniq.each do |project_name|
        expect(response.body).to include(project_name)
      end
    end

    it "renders every project's task blocks" do
      MockData::ProjectProgress::RECORDS.each do |record|
        expect(response.body).to include(record[:task_name])
      end
    end
  end

  describe "GET /dashboard?project=XXX" do
    let(:selected_project) { "Project Alpha" }
    let(:other_project_task_names) do
      MockData::ProjectProgress::RECORDS
        .reject { |r| r[:project_name] == selected_project }
        .map { |r| r[:task_name] }
    end
    let(:selected_project_task_names) do
      MockData::ProjectProgress::RECORDS
        .select { |r| r[:project_name] == selected_project }
        .map { |r| r[:task_name] }
    end

    before { get "/dashboard", params: { project: selected_project } }

    it "returns HTTP 200" do
      expect(response).to have_http_status(200)
    end

    it "renders only the selected project's task blocks" do
      selected_project_task_names.each do |task_name|
        expect(response.body).to include(task_name)
      end

      other_project_task_names.each do |task_name|
        expect(response.body).not_to include(task_name)
      end
    end

    it "keeps the selected project pre-selected in the dropdown" do
      expect(response.body).to match(/<option [^>]*selected="selected"[^>]*value="#{Regexp.escape(selected_project)}"/)
    end
  end
end
