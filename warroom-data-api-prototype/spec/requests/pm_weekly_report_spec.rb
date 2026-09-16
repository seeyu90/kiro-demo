require "rails_helper"

# 日期固定在 2026/09/18（星期五，PM 實際寫週報的那天）：
#   本週 = 2026/09/14（一）～ 2026/09/20（日）／下週 = 2026/09/21（一）～ 2026/09/27（日）
# 依既有慣例 stub Client 層，讓 Controller → Actor → Client 整條鏈真的跑過一遍。
RSpec.describe "PmWeeklyReport", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Date.new(2026, 9, 18)) { example.run } }

  let(:progress_header) { [ "專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延誤", "類型" ] }
  let(:progress_rows) do
    [
      progress_header,
      [ "AG 亞炬", "很久以前就該完成", "未完成", "王贊勛", "2026/08/01", "", "48", "功能" ],
      [ "AG 亞炬", "本週日到期", "未完成", "王贊勛", "2026/09/20", "", "", "功能" ],
      # 預計 9/14、實際 9/16 完成，試算表的「延誤」欄為 2——用來確認本週已完成會顯示
      # 試算表的延誤天數（事實紀錄），而不是逾期區塊那種即時計算的天數
      [ "Virtuous HRM", "本週三完成的", "完成", "黃靖益", "2026/09/14", "2026/09/16", "2", "功能" ],
      [ "Virtuous HRM", "下週二到期", "未完成", "黃靖益", "2026/09/22", "", "", "PR" ],
      [ "Virtuous HRM", "還沒排期", "未完成", "黃靖益", "", "", "", "功能" ]
    ]
  end

  let(:issue_header) do
    %w[issue_id subject type tracker status assigned_to start_date due_date work_days sheet_name project total_hours]
  end
  let(:issue_rows) do
    [
      issue_header,
      [ "101", "登入失敗", "Complaint", "Bug", "新建立", "王贊勛", "2026/08/20", "2026/09/01", "2", "", "AG 亞炬", "1" ],
      [ "103", "下週要處理", "Other", "Bug", "新建立", "黃靖益", "2026/09/15", "2026/09/22", "1", "", "Virtuous HRM", "0" ],
      [ "106", "沒到期日也沒 SLA", "Other", "Bug", "新建立", "王贊勛", "2026/09/01", "", "1", "", "AG 亞炬", "1" ]
    ]
  end

  let(:month_kpi_rows) { [ %w[year_month 客訴 測試 總Bug 攔截率 完成數 未結案 平均天數 SLA達標率 Top3] ] }
  let(:daily_kpi_rows) { [ %w[日期 客訴 測試 其他 總計] ] }

  let(:phase_rows) do
    [
      [ "HRM", "9001", "報表模組", "開發", "2026-09-01", nil, "延誤未完成", "等客戶回覆", "HRM|9001|開發", "2026" ]
    ]
  end
  let(:profile_rows) do
    [
      %w[Github/Notion Redmine專案 303專案 客戶 PM 狀態],
      [ "HRM", "Virtuous HRM", "HRM", "AMAS", "楊欣翰", "維護" ]
    ]
  end

  before do
    allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return(progress_rows)
    allow(ProjectProgressSheetsClient).to receive(:fetched_at).and_return(Time.zone.parse("2026-09-18 09:00"))
    allow(IssueSheetsClient).to receive(:fetch_month_kpi_rows).and_return(month_kpi_rows)
    allow(IssueSheetsClient).to receive(:fetch_daily_kpi_rows).and_return(daily_kpi_rows)
    allow(IssueSheetsClient).to receive(:fetch_issue_rows).and_return(issue_rows)
    allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_return(phase_rows)
    allow(ProjectProfilesSheetsClient).to receive(:fetch_rows).and_return(profile_rows)
  end

  it "renders all four sections with 200" do
    get "/pm_weekly_report"

    expect(response).to have_http_status(200)
    expect(response.body).to include("逾期未完成（")
    expect(response.body).to include("本週工作（")
    expect(response.body).to include("下週工作（")
    expect(response.body).to include("階段追蹤（")
    expect(response.body).to include("2026/09/14 ~ 2026/09/20")
    expect(response.body).to include("2026/09/21 ~ 2026/09/27")
    expect(response.body).to include("很久以前就該完成")
    expect(response.body).to include("本週三完成的")
    expect(response.body).to include("還沒排期")
    expect(response.body).to include("登入失敗")
    expect(response.body).to include("報表模組")
    expect(response.body).to include("另有 1 筆未定到期日議題")
  end

  it "filters 305/306 by project but leaves the phase-tracking section untouched" do
    get "/pm_weekly_report", params: { project: "AG 亞炬" }

    expect(response).to have_http_status(200)
    expect(response.body).to include("很久以前就該完成")
    expect(response.body).not_to include("本週三完成的")
    expect(response.body).not_to include("下週要處理")
    expect(response.body).to include("報表模組")
    expect(response.body).to include("階段追蹤（1）")
  end

  it "renders an error message and no sections when 305 fails" do
    allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_raise(Google::Apis::ClientError.new("notFound"))

    get "/pm_weekly_report"

    expect(response).to have_http_status(200)
    expect(response.body).to include("error-message")
    expect(response.body).not_to include("逾期未完成（")
  end

  # 降級提示裡的資料源名稱要單獨比對：「306 臭蟲議題」「專案階段追蹤」在頁面別處也是區塊
  # 標題，直接對整份 body 做 include 分不出提示列到底列了哪幾個資料源。
  def degradation_notice
    response.body[%r{<p class="freshness-label">.*?</p>}m]
  end

  it "shows a degradation notice naming only 306 when 306 fails, and still renders 305 與階段追蹤" do
    allow(IssueSheetsClient).to receive(:fetch_issue_rows).and_raise(Google::Apis::ClientError.new("notFound"))

    get "/pm_weekly_report"

    expect(response).to have_http_status(200)
    expect(degradation_notice).to include("部分資料來源目前無法讀取")
    expect(degradation_notice).to include("306 臭蟲議題")
    expect(degradation_notice).not_to include("專案階段追蹤")
    expect(response.body).to include("很久以前就該完成")
    expect(response.body).to include("報表模組")
  end

  # 讀不到 ≠ 沒有：降級時筆數要顯示「—」、空清單要講「讀不到」，不能沿用「目前無…」的
  # 空狀態文字——需求 1.4 保留空區塊正是為了讓 PM 分辨「確實沒有」與「漏抓」。
  it "does not pass off an unreadable 306 as an empty one" do
    allow(IssueSheetsClient).to receive(:fetch_issue_rows).and_raise(Google::Apis::ClientError.new("notFound"))

    get "/pm_weekly_report"

    expect(response.body).to include("306 臭蟲議題（—）")
    expect(response.body).to include("此資料來源目前無法讀取，清單暫時無法顯示。")
    expect(response.body).not_to include("本週無到期的議題。")
    expect(response.body).not_to include("306 臭蟲議題（0）")
  end

  it "shows a degradation notice naming only 階段追蹤 when it fails, and still renders 305／306" do
    allow(PhaseRecordsSheetsClient).to receive(:fetch_rows).and_raise(Google::Apis::ClientError.new("notFound"))

    get "/pm_weekly_report"

    expect(response).to have_http_status(200)
    expect(degradation_notice).to include("專案階段追蹤")
    expect(degradation_notice).not_to include("306 臭蟲議題")
    expect(response.body).to include("階段追蹤（—）")
    expect(response.body).to include("此資料來源目前無法讀取，清單暫時無法顯示。")
    expect(response.body).not_to include("目前無逾期或本週／下週到期的階段項目。")
    expect(response.body).to include("很久以前就該完成")
    expect(response.body).to include("登入失敗")
  end

  it "renders no degradation notice when every data source is healthy" do
    get "/pm_weekly_report"

    expect(degradation_notice).to be_nil
  end

  it "still says 確實沒有 for a source that is healthy but genuinely has nothing this week" do
    get "/pm_weekly_report"

    # 306 這週真的沒有到期議題（fixture 只有逾期的 101、下週的 103、未定的 106）
    expect(response.body).to include("本週無到期的議題。")
    expect(response.body).not_to include("此資料來源目前無法讀取，清單暫時無法顯示。")
  end

  it "shows the sheet 延誤天數 for tasks completed this week (當初延遲了幾天的事實紀錄)" do
    get "/pm_weekly_report"

    completed_section = response.body[/本週已完成（1）.*?<\/table>/m]
    expect(completed_section).to include("延誤天數")
    expect(completed_section).to include("+2 天")
  end
end
