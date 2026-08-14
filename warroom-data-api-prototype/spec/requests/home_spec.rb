require "rails_helper"

RSpec.describe "Home", type: :request do
  describe "GET /" do
    before { get "/" }

    it "returns HTTP 200" do
      expect(response).to have_http_status(200)
    end

    it "does not call either ProjectProgressSheetsClient or IssueSheetsClient (需求 10.3)" do
      expect(ProjectProgressSheetsClient).not_to receive(:fetch_rows)
      expect(IssueSheetsClient).not_to receive(:fetch_month_kpi_rows)

      get "/"
    end

    it "renders a link to /dashboard" do
      expect(response.body).to match(%r{<a class="entry-card" href="/dashboard">})
    end

    it "renders a link to /issues" do
      expect(response.body).to match(%r{<a class="entry-card" href="/issues">})
    end

    it "renders the theme toggle button" do
      expect(response.body).to include('id="theme-toggle"')
    end
  end

  describe "GET /dashboard is still directly reachable after root changed to home#index" do
    before do
      allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return([["專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延誤"]])
      get "/dashboard"
    end

    it "returns HTTP 200" do
      expect(response).to have_http_status(200)
    end

    it "renders a back link to the entry page" do
      expect(response.body).to match(%r{<a class="back-link" href="/">})
    end
  end

  describe "GET /issues renders a back link to the entry page" do
    before do
      allow(IssueSheetsClient).to receive(:fetch_month_kpi_rows).and_return([%w[year_month 客訴 測試 總Bug 攔截率 完成數 未結案 平均天數 SLA達標率 Top3]])
      allow(IssueSheetsClient).to receive(:fetch_daily_kpi_rows).and_return([%w[日期 客訴 測試 其他 總計]])
      allow(IssueSheetsClient).to receive(:fetch_issue_rows).and_return([%w[issue_id subject type tracker status assigned_to start_date due_date work_days sheet_name project]])
      get "/issues"
    end

    it "renders a back link to the entry page" do
      expect(response.body).to match(%r{<a class="back-link" href="/">})
    end
  end
end
