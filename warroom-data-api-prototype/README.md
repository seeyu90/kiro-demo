# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

---

## Google Sheets API Service Account 憑證設定

本專案使用 Google Sheets API 讀取 305 專案進度資料，需設定 Service Account 憑證。

### 憑證注入方式

提供兩種方式設定憑證，任選一種即可：

#### 方式一：Rails encrypted credentials（本機開發建議）

1. 使用編輯指令：

   ```bash
   rails credentials:edit
   ```

2. 加入以下內容（`your-service-account-json` 為 Service Account JSON 檔案內容，請以實際內容替換）：

   ```yaml
   google_sheets:
     service_account_json: |-
       {
         "type": "service_account",
         "project_id": "your-project-id",
         "private_key_id": "your-private-key-id",
         "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
         "client_email": "your-service-account@your-project-id.iam.gserviceaccount.com",
         "client_id": "your-client-id",
         "auth_uri": "https://accounts.google.com/o/oauth2/auth",
         "token_uri": "https://oauth2.googleapis.com/token",
         "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
         "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/..."
       }
   ```

3. `config/credentials.yml.enc` 已列入 `.gitignore`，**切勿提交至版控**。

4. `config/master.key` 用於解密 `credentials.yml.enc`，請妥善保管，**切勿提交至版控**。

#### 方式二：環境變數（CI/CD 或正式部署建議）

設定環境變數 `GOOGLE_SHEETS_CREDENTIALS_JSON`，值為 Service Account JSON 字串（去除換行與多餘空白）：

```bash
export GOOGLE_SHEETS_CREDENTIALS_JSON='{"type":"service_account","project_id":"...","private_key":"...","client_email":"...","client_id":"...","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://oauth2.googleapis.com/token","auth_provider_x509_cert_url":"https://www.googleapis.com/oauth2/v1/certs","client_x509_cert_url":"https://www.googleapis.com/robot/v1/metadata/x509/..."}'
```

部署平台範例：

- **Heroku**：`heroku config:set GOOGLE_SHEETS_CREDENTIALS_JSON='...'`
- **Docker**：`-e GOOGLE_SHEETS_CREDENTIALS_JSON='...'`
- **GitHub Actions**：在 Repository Secrets 設定後於 workflow 中引用

### 憑證取得步驟

1. 至 [Google Cloud Console](https://console.cloud.google.com/)
2. 建立或選取專案
3. 啟用 Google Sheets API
4. 建立 Service Account 並下載 JSON 金鑰檔
5. 將 JSON 檔內容複製至上述任一設定方式

### 憑證優先順序

系統會依序嘗試以下來源：

1. Rails encrypted credentials（`google_sheets.service_account_json`）
2. 環境變數（`GOOGLE_SHEETS_CREDENTIALS_JSON`）

任一來源有有效憑證即可。

### 確認憑證設定成功

設定完成後，訪問 `/api/project_progress` 若回傳 305 專案進度資料，表示憑證設定成功。

若回傳 `500 Internal Server Error` 並包含「找不到 Google Service Account 憑證」等錯誤訊息，請檢查憑證設定。
