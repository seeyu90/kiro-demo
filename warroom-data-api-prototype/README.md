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

## 目前功能

本專案為戰情室 Dashboard 原型，串接 Google Sheets 資料來源，目前提供三個路由：

| 路由 | 說明 |
| --- | --- |
| `/dashboard` | 305 專案進度：依專案分組檢視任務進度、逾期與本週到期任務 |
| `/issues` | 306 臭蟲議題：月度／每日 KPI、依專案分類統計、議題明細 |
| `/burndown` | 307 人時燃盡追蹤：依議題呈現理想／實際剩餘人時燃盡圖，支援專案／人員／狀態篩選（見下方「307 人時燃盡追蹤」段落） |

三者各自獨立串接不同分頁／試算表，互不影響。詳細規格與任務清單見
`.kiro/specs/`（`warroom-data-api-real-source`、`warroom-issue-dashboard-real-source`、
`warroom-project-burndown-tracking`）。

### 307 人時燃盡追蹤

- 同一議題若拆給多位人員分別填寫（同 `議題 ID`），會自動合併為一張卡片（人員清單、預估／
  剩餘人時加總、週人時加總；起訖日取合法列中的最早開案／最晚完成）
- 議題狀態優先讀取試算表「狀態」欄位（未開始／執行中／已完成），欄位無法辨識（空白或髒資料）
  時退回以完成日期與今天比較判斷；預設篩選只顯示進行中議題
- 單一議題燃盡圖只顯示開案週之後的資料，理想線頭尾補上開案／完成錨點，確保斜線完整畫到底；
  Y 軸支援負值（實際人時超支時剩餘人時可能為負），並固定畫出「剩餘 = 0」的參考線
- 同一議題有多位人員時，卡片下方會顯示各人員累積消耗人時的堆疊圖，另附總預估人時參考線

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

設定完成後，訪問 `/api/project_progress` 若回傳 305 專案進度資料，表示憑證設定成功（`/burndown`
也可用來驗證，會讀取 307 試算表資料）。

若回傳 `500 Internal Server Error` 並包含「找不到 Google Service Account 憑證」等錯誤訊息，請檢查憑證設定。
