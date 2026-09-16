require "rails_helper"
require "nokogiri"

# icon.svg 曾經因為註解裡出現「--」（XML 不允許註解含連續兩個 hyphen）而整份解析失敗，
# 瀏覽器一個圖元都畫不出來、favicon 直接退回別的來源。這種錯誤在 server 端 curl 檔案內容
# 看不出來（位元組是對的），只有真的丟進 XML parser 才會炸，所以用一個 spec 守住。
RSpec.describe "public 靜態資產" do
  it "public/icon.svg 是合法的 XML（SVG 是 XML，註解不得含 --）" do
    doc = Nokogiri::XML(Rails.root.join("public/icon.svg").read, &:strict)

    expect(doc.errors).to be_empty
    expect(doc.root.name).to eq("svg")
  end
end
