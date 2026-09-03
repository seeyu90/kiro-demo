# frozen_string_literal: true

# 305／306／307 三頁共用的起訖日期區間篩選：解析 params[:from]／params[:to] 成 Date（或 nil）。
# 無法解析（空白、格式錯誤）一律視為「沒有限制」而非拋例外擋頁面——日期篩選是錦上添花的
# 篩選條件，不該讓使用者打錯日期格式就整頁掛掉。
module DateRangeFilterable
  extend ActiveSupport::Concern

  private

  def resolve_date_range
    [ parse_filter_date(params[:from]), parse_filter_date(params[:to]) ]
  end

  def parse_filter_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
