class HomeController < ApplicationController
  def index
  end

  # 全站唯一的「重新整理資料」入口。原本各頁自己帶 refresh 參數，但那只會強制重抓該頁用到的
  # 那一份試算表，使用者得逐頁按一次才能讓整個戰情室的資料同步到最新。
  #
  # 本應用的 Rails.cache 只用來存各 Sheets client 的原始列資料（見 app/clients/，無其他用途），
  # 因此直接整組清除即可，不需逐一列舉各 client 的 cache key（新增 client 時也不會漏掉）。
  # 清除後不在這裡重新抓取：一次抓六份試算表會讓這個請求卡住十幾秒，且任一份失敗就得處理
  # 部分成功；改為下次進入各頁面時各自重抓，失敗也只影響該頁。
  def refresh
    Rails.cache.clear
    redirect_to root_path, notice: "已重新整理：接下來開啟任一頁面，都會重新向試算表抓取最新資料（第一次開啟會多等幾秒）。"
  end
end
