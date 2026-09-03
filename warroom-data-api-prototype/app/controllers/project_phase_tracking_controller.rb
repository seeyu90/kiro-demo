class ProjectPhaseTrackingController < ApplicationController
  include YearFilterable

  VIEWS = %w[list gantt].freeze
  DEFAULT_VIEW = "list".freeze
  # 預設狀態篩選就是「未完成」，使用者能明確選「全部狀態」（比照 resolve_year 慣例，以
  # params.key? 區分「使用者選了全部狀態」與「表單根本還沒送出過」）。
  DEFAULT_STATUS = "未完成".freeze

  def index
    year = resolve_year
    result = Sheets::FetchPhaseTracking.result(year: year)
    if result.success?
      build_success(result, year)
    else
      build_failure(result.message)
    end
  end

  private

  def resolve_status
    return params[:status].presence if params.key?(:status)

    DEFAULT_STATUS
  end

  def build_success(result, year)
    all_cards = PhaseTrackingCardBlueprint.render_as_hash(result.cards)
    @view = VIEWS.include?(params[:view]) ? params[:view] : DEFAULT_VIEW
    @profiles_unavailable = result.profiles_unavailable
    @available_years = result.available_years

    @customers = all_cards.map { |c| c[:customer] }.compact.uniq
    @statuses = all_cards.map { |c| c[:status] }.compact.uniq
    @pms = all_cards.map { |c| c[:pm] }.compact.uniq

    @selected_customer = params[:customer].presence
    @selected_status = resolve_status
    @selected_pm = params[:pm].presence
    @selected_year = year
    @selected_query = params[:q].presence

    filtered = all_cards.select do |c|
      (@selected_customer.blank? || c[:customer] == @selected_customer) &&
        (@selected_status.blank? || c[:status] == @selected_status) &&
        (@selected_pm.blank? || c[:pm] == @selected_pm) &&
        matches_query?(c, @selected_query)
    end

    @cards = sort_by_planned_completion(filtered)
    @error = nil
  end

  # 議題／專案代碼搜尋：issue_id 有時是描述性名稱（如「202412 優化」），有時是純 Redmine ID
  # （如「4515」，這種情況 issue_name 會另外補上人類可讀名稱如「現場報工」），故對
  # issue_id／issue_name／project 三欄都做不分大小寫的子字串比對（不做斷詞或模糊搜尋），
  # 符合其一即算命中。
  def matches_query?(card, query)
    return true if query.blank?

    needle = query.downcase
    [ card[:issue_id], card[:issue_name], card[:project] ].any? { |v| v.to_s.downcase.include?(needle) }
  end

  # 固定依預計完成日期排序，不給使用者選。排序鍵值相同者維持原始相對順序（穩定排序）——
  # 明確把原始 index 當第二排序鍵，不依賴 sort_by 本身是否穩定。
  def sort_by_planned_completion(cards)
    cards.each_with_index.sort_by { |c, i| [ c[:planned_completion_date] || "9999-99-99", i ] }.map(&:first)
  end

  def build_failure(message)
    @view = DEFAULT_VIEW
    @profiles_unavailable = false
    @available_years = []
    @customers = []
    @statuses = []
    @pms = []
    @selected_customer = nil
    @selected_status = nil
    @selected_pm = nil
    @selected_year = nil
    @selected_query = nil
    @cards = []
    @error = message
  end
end
