require "rails_helper"

RSpec.describe "ProjectHistory", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    travel_to(Date.new(2026, 8, 16)) { example.run }
  end

  def overview_section(body)
    body[%r{<section class="issue-section">.*}m]
  end

  let(:roster_header) { %w[專案 專案縮寫 狀態 比例 生效月份 失效月份 負責RD 客戶 PM] }
  let(:roster_rows) do
    [
      roster_header,
      [ "AG 亞炬", "亞炬 Platform", "維護", "40%", "2026/01", "", "王贊勛", "亞炬", "呂俐禎" ],
      [ "Virtuous HRM", "HRM", "維護", "40%", "2026/01", "", "黃靖益", "AMAS", "楊欣翰" ]
    ]
  end

  let(:progress_header) { [ "專案名稱", "任務名稱", "狀態", "負責人", "預計完成日期", "實際完成日期", "延誤", "類型" ] }
  let(:progress_rows) do
    [
      progress_header,
      [ "AG 亞炬", "API 效能優化", "未完成", "王贊勛", "2026/08/22", "", "", "功能" ],
      [ "Virtuous HRM", "請假模組串接", "完成", "黃靖益", "2026/07/06", "2026/07/08", "2", "功能" ]
    ]
  end

  let(:burndown_header) { %w[剩餘人時 專案 議題 人員 議題ID 開案日期 完成日期 狀態 預估人時] }
  # 兩個專案都給一筆 2026 年開案的議題，讓總覽頁在「年度」預設今年（travel_to 2026/08/16）的
  # 篩選下，兩個專案都還會出現在清單裡（需求：無 307 對應議題的專案在選定年度下不列出）。
  let(:burndown_rows) do
    [
      burndown_header + [ "08/12", "08/05" ],
      [ "8", "AG 亞炬", "API 效能優化", "王贊勛", "1001", "2026/07/08", "2026/08/22", "執行中", "40", "1", "1" ],
      [ "0", "Virtuous HRM", "請假模組串接", "黃靖益", "2001", "2026/07/01", "2026/08/10", "已完成", "10", "1", "1" ]
    ]
  end

  before do
    allow(ProjectRosterSheetsClient).to receive(:fetch_rows).and_return(roster_rows)
    allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_return(progress_rows)
    allow(BurndownSheetsClient).to receive(:fetch_rows).and_return(burndown_rows)
  end

  describe "GET /project_history (overview)" do
    before { get "/project_history" }

    it "returns HTTP 200" do
      expect(response).to have_http_status(200)
    end

    # 麵包屑（含目前選中的專案名稱）放在 turbo_frame_tag 裡面才能隨切換專案/篩選正確更新；
    # 但這代表「入口頁」連結必須標記 data-turbo-frame="_top" 才能跳出 frame 做完整頁面導覽
    # ——沒有這個屬性的話，Turbo 會想在 "/" 首頁的回應裡找同一個 frame id，找不到就顯示
    # "Content missing"（因為 home#index 沒有這個 frame，之前實測遇過這個問題）。
    it "marks the entry-page breadcrumb link to break out of the turbo frame" do
      expect(response.body).to match(%r{<a[^>]*data-turbo-frame="_top"[^>]*>入口頁</a>})
    end

    it "lists both projects as expandable cards, joined with roster customer/pm" do
      expect(response.body).to include("AG 亞炬").and include("亞炬").and include("呂俐禎")
      expect(response.body).to include("Virtuous HRM").and include("AMAS").and include("楊欣翰")
      expect(response.body).to include("project-card-summary")
    end

    # 卡片原地展開（<details>/<summary>），展開後的議題明細表格顯示每個議題自己的完成狀態
    # （已完成／進行中），不是專案層級的單一完成日期（那組欄位已移除，見需求變更）。
    it "shows each issue's own status in the expanded breakdown (done vs in progress)" do
      expect(response.body).to include("已完成").and include("進行中")
    end

    # 統計工時（進度％、已消耗/預估工時）以卡片標題列的 tag 呈現，AG 亞炬在 burndown_rows 有
    # 對應議題（依工時比例算出進度%）。
    it "shows a 統計工時 tag with a hours-pair (aligned consumed/estimated) summary in the card header" do
      expect(response.body).to include("tag-hours")
      expect(response.body).to match(%r{tag-hours">\s*<span class="hours-pair">.*?</span>\s*</span>}m)
    end
  end

  describe "GET /project_history — 專案在選定年度沒有任何 307 對應議題時不列出" do
    it "excludes a project entirely when the burndown fetch succeeds but returns no issues for it in the selected year" do
      allow(BurndownSheetsClient).to receive(:fetch_rows).and_return([ burndown_header + [ "08/12", "08/05" ] ])

      get "/project_history"

      section = overview_section(response.body)
      expect(section).not_to include("AG 亞炬")
      expect(section).not_to include("Virtuous HRM")
    end

    # 307 讀取失敗時（不是「查得到但沒有這個年度的資料」）維持既有降級慣例，不清空整個清單。
    it "still lists all projects (with empty task breakdowns) when the burndown fetch itself fails" do
      error = Google::Apis::ClientError.new("Forbidden")
      allow(error).to receive(:status_code).and_return(403)
      allow(BurndownSheetsClient).to receive(:fetch_rows).and_raise(error)

      get "/project_history"

      expect(overview_section(response.body)).to include("AG 亞炬").and include("Virtuous HRM")
    end

    # 選「全部年度」時不套用這條排除規則——沒有任何年度對應議題的專案仍然要看得到（例如剛建立
    # 的專案），工時欄顯示 —。
    it "shows a project with no 307 match at all when '全部年度' is selected explicitly, with a — hours tag" do
      allow(BurndownSheetsClient).to receive(:fetch_rows).and_return([ burndown_header + [ "08/12", "08/05" ] ])

      get "/project_history", params: { year: "" }

      section = overview_section(response.body)
      expect(section).to include("AG 亞炬").and include("Virtuous HRM")
      expect(section).to match(%r{tag-hours">\s*—\s*</span>})
    end
  end

  describe "GET /project_history?customer=... (filter)" do
    it "shows only the matching project" do
      get "/project_history", params: { customer: "AMAS" }

      section = overview_section(response.body)
      expect(section).to include("Virtuous HRM")
      expect(section).not_to include("AG 亞炬")
    end

    it "shows the empty state when the filter matches nothing" do
      get "/project_history", params: { customer: "AMAS", pm: "呂俐禎" }

      expect(overview_section(response.body)).to include("目前無符合條件的專案")
    end
  end

  describe "GET /project_history — 風險排序（含逾期任務的專案排最前）" do
    # 305 這裡只用來讓兩個專案都出現在總覽（不影響排序——排序依 307 DurationTask 的
    # due_date 判斷逾期，見需求 4.4）。
    let(:progress_rows) do
      [
        progress_header,
        [ "Virtuous HRM", "請假模組串接", "未完成", "黃靖益", "2026/12/01", "", "", "功能" ],
        [ "AG 亞炬", "API 效能優化", "未完成", "王贊勛", "2026/01/01", "", "", "功能" ]
      ]
    end
    # 307 順序刻意讓「不逾期」的 Virtuous HRM 排在「已逾期」的 AG 亞炬前面，驗證排序後的輸出
    # 順序被翻轉：AG 亞炬 的 due_date（07/15）早於今天（travel_to 2026/08/16），且狀態未完成
    # ＝逾期；Virtuous HRM 的 due_date（12/01）還沒到。
    let(:burndown_rows) do
      [
        burndown_header + [ "08/12" ],
        [ "5", "Virtuous HRM", "請假模組串接", "黃靖益", "2002", "2026/07/01", "2026/12/01", "執行中", "10", "5" ],
        [ "5", "AG 亞炬", "API 效能優化", "王贊勛", "2001", "2026/07/01", "2026/07/15", "執行中", "10", "5" ]
      ]
    end

    it "lists the project with an overdue task before the one without, regardless of original 305/307 order" do
      get "/project_history"

      section = overview_section(response.body)
      expect(section.index("AG 亞炬")).to be < section.index("Virtuous HRM")
    end
  end

  describe "GET /project_history?view=gantt" do
    it "renders an SVG gantt chart instead of the table" do
      get "/project_history", params: { view: "gantt" }

      expect(response.body).to include('class="gantt-svg"')
      expect(response.body).not_to include("<table")
    end

    it "renders a month timeline axis (gridlines + rotated labels) so bars have a date reference" do
      get "/project_history", params: { view: "gantt" }

      expect(response.body).to include("gantt-month-gridline")
      expect(response.body).to include("gantt-month-label")
      expect(response.body).to match(/\d{4}\/\d{2}/) # 至少一個 YYYY/MM 標籤
    end

    it "renders a dashed today reference line" do
      get "/project_history", params: { view: "gantt" }

      expect(response.body).to include("gantt-today-line")
    end

    # 需求 4.1：圖例說明各色塊意義。
    it "renders a legend explaining the gantt colors" do
      get "/project_history", params: { view: "gantt" }

      expect(response.body).to include("gantt-legend")
      expect(response.body).to include("預計時程").and include("逾期未完成")
    end

    # 需求 1：AG 亞炬 對應到 burndown_rows 的議題，畫成預計/實際雙條時程區間。
    it "renders planned/actual dual-bar styling for the project with matching 307 data" do
      get "/project_history", params: { view: "gantt" }

      expect(response.body).to include("gantt-task-planned")
      expect(response.body).to include("gantt-task-actual-track")
    end

    # hover 提示：每個色塊（含依工時填色、疊在最上層的那一段）都要有自己的 <title>，
    # 不然滑鼠停在已填色的區域會完全沒有提示（疊在上層的元素會擋住底下 track 的 title，
    # 之前只有 planned／actual-track 兩層有 <title>，fill 那層沒有——迴歸測試）。
    it "shows the issue name via a native SVG tooltip, including on the hours-filled portion of the bar" do
      get "/project_history", params: { view: "gantt" }

      expect(response.body).to match(%r{<rect[^>]*class="gantt-task-actual-fill-\w+"[^>]*>\s*<title>[^<]*API 效能優化[^<]*</title>\s*</rect>})
    end
  end

  describe "GET /project_history when a core data source (305) fails" do
    before do
      error = Google::Apis::ClientError.new("Forbidden")
      allow(error).to receive(:status_code).and_return(403)
      allow(ProjectProgressSheetsClient).to receive(:fetch_rows).and_raise(error)
      get "/project_history"
    end

    it "returns HTTP 200 and shows the error message instead of raising" do
      expect(response).to have_http_status(200)
      expect(response.body).to include("錯誤")
      expect(response.body).to include("資料來源存取權限不足")
    end

    it "does not render the filter form or any data section" do
      frame = response.body[%r{<turbo-frame id="project-history-content">.*?</turbo-frame>}m]
      expect(frame).not_to include("apply-filters-btn")
      expect(frame).not_to include("<form")
    end
  end

  describe "GET /project_history when only the roster (300_員工專案) source fails" do
    before do
      error = Google::Apis::ClientError.new("Forbidden")
      allow(error).to receive(:status_code).and_return(403)
      allow(ProjectRosterSheetsClient).to receive(:fetch_rows).and_raise(error)
      get "/project_history"
    end

    # Roster 只是客戶/PM 的補充資料，不是本頁面的核心資料（305/306/307 才是），失敗時不應該
    # 擋住整頁——這是實測發現 300_員工專案跟 305/306/307 是不同試算表、不同擁有者、共用權限
    # 各自獨立設定後才改的設計（見 fetch_project_history.rb#call 的附註）。
    it "still renders the overview successfully (degrades gracefully) instead of showing an error page" do
      expect(response).to have_http_status(200)
      expect(response.body).not_to include("錯誤：")
      expect(response.body).to include("AG 亞炬").or include("Virtuous HRM")
    end

    it "shows customer/pm as — for every project since the roster couldn't be read" do
      expect(response.body).to include("—")
    end
  end
end
