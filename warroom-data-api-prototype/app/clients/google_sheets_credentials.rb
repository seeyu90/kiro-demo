# frozen_string_literal: true

# ProjectProgressSheetsClient（305）與 IssueSheetsClient（306）共用同一組 Google Cloud
# Service Account 憑證，讀取策略（Rails credentials 優先，環境變數 fallback）原本在兩個
# client 各自重複一份，抽成共用 module 避免日後修改時要同步改兩處。
# 使用端須定義 SCOPES 常數（讀取 scope 陣列）。
module GoogleSheetsCredentials
  private

  def credentials
    json = rails_credentials_json || env_credentials_json
    raise "找不到 Google Service Account 憑證，請設定 Rails credentials 或環境變數 GOOGLE_SHEETS_CREDENTIALS_JSON" if json.nil?

    Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(json),
      scope: self.class::SCOPES
    )
  end

  def rails_credentials_json
    raw = Rails.application.credentials.dig(:google_sheets, :service_account_json)
    raw.present? ? raw.to_s : nil
  rescue => _e
    nil
  end

  def env_credentials_json
    json = ENV["GOOGLE_SHEETS_CREDENTIALS_JSON"]
    json.present? ? json : nil
  end
end
