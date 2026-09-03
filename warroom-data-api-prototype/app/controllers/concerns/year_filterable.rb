# frozen_string_literal: true

# 年度篩選預設「今年」，但使用者能透過下拉選單明確選「全部年度」（表單一律送出 year
# 參數，即使值是空字串，用 `params.key?` 區分「使用者選了全部年度」與「表單根本還沒
# 送出過」這兩種情況，只有後者才套用今年當預設值）。原本 project_history_controller 與
# project_phase_tracking_controller 各自重複實作同一段邏輯，抽成這個共用 concern。
module YearFilterable
  extend ActiveSupport::Concern

  private

  def resolve_year
    return params[:year].presence if params.key?(:year)

    Date.current.year.to_s
  end
end
