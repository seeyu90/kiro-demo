---
inclusion: always
---

# Rails 開發規範（Steering）

## 適用範圍

本檔適用於 `.kiro/specs/<spec-name>/` 中明確宣告「Rails 例外」的 spec（即需要真實可運作的後端邏輯，
而非 `project-standards.md` 所述的純靜態展示站）。宣告方式：該 spec 的 `requirements.md` 需在
「技術棧說明」段落明確註明採用 Ruby on Rails 獨立伺服器實作的理由，並聲明不受
`project-standards.md`「技術限制」「響應式設計」段落約束；但仍須遵守「資料與語言」段落
（繁體中文介面；資料是否為模擬資料需由該 spec 自行明確聲明）與 karpathy-guidelines 的最簡方案原則。

目前已知採用本規範的 spec：`warroom-data-api-prototype`、`warroom-data-api-real-source`。

## 分層慣例

固定分層順序，各層職責單一，不得越界：

- **Controller**（`app/controllers/`）：僅呼叫對應 Actor 並將結果渲染為 JSON 或交給 View，
  不包含任何資料讀取、外部 API 呼叫或轉換邏輯。
- **Actor**（`app/actors/`，依領域分目錄如 `app/actors/sheets/`）：遵循 `service_actor` gem 慣例，
  以 `call` 方法作為唯一執行入口，繼承 `ApplicationActor`；封裝單一商業邏輯（讀取、正規化、驗證、
  分組），透過 `output :xxx` 宣告輸出欄位。
- **Client**（`app/clients/`）：封裝單一外部服務的 API 呼叫（例如 `ProjectProgressSheetsClient` 封裝
  Google Sheets API），只負責取得原始資料，不做業務層轉換或驗證。
- **Blueprint**（`app/blueprints/`，Blueprinter gem）：定義輸出欄位的單一來源，Controller 與 View
  共用同一份 Blueprint，欄位清單不得在其他地方重複列舉。

## 統一錯誤格式

所有錯誤回應一律為：

```json
{ "error": { "code": "<錯誤代碼>", "message": "<描述>" } }
```

Actor 以 `fail!(failure_code: :xxx, message: "...")` 回傳失敗，Controller 依 `failure_code` 對應 HTTP
狀態碼（慣用對應表，可依 spec 需求擴充）：

| failure_code | HTTP status | 情境 |
|---|---|---|
| `sheet_not_found` | 404 | 找不到指定分頁或試算表 |
| `access_denied` | 403 | 資料來源存取權限不足 |
| `invalid_data_format` | 422 | 資料缺少必要欄位或格式不符預期 |
| `internal_error` | 500 | 憑證載入失敗、逾時、配額超過或其他未預期例外 |

## Google Sheets 憑證存放

- 憑證僅能從下列來源讀取，不得硬寫於任何原始碼檔案或提交至版控：
  1. Rails encrypted credentials（`Rails.application.credentials.dig(:google_sheets, :service_account_json)`）— 本機開發建議
  2. 環境變數 `GOOGLE_SHEETS_CREDENTIALS_JSON` — CI/CD 或正式部署建議
- Client 初始化時依序嘗試上述來源，優先 Rails credentials，找不到才回退環境變數；兩者皆無時視為
  憑證缺失，交由呼叫端 Actor 以 `failure_code: :internal_error` 回傳失敗。
- 認證 scope 一律使用唯讀範圍 `https://www.googleapis.com/auth/spreadsheets.readonly`，不請求寫入權限。
- 含金鑰內容的檔案（`config/credentials.yml.enc` 對應的 `config/master.key` 等）須列入 `.gitignore`。
- 新增串接新試算表時，於該 spec 的 README 記載憑證設定方式，可參考
  `warroom-data-api-prototype/README.md` 既有段落格式。

## 其他慣例

- Google Sheets API 回傳字串會被標記為 `ASCII-8BIT`，即使實際內容是合法 UTF-8；讀取後需重新標記為
  UTF-8（`force_encoding(Encoding::UTF_8)`），避免後續與程式碼中的中文常值字串併接時噴
  `Encoding::CompatibilityError`。
- Google Sheets API 會省略列尾端的空白儲存格；解析前務必先補滿（pad）至固定欄位數，再進行欄位對應
  或附加額外標記欄位，避免欄位錯位。
- 個別紀錄缺少必要欄位時，僅跳過該筆紀錄，不使整個 request 失敗（真實試算表資料難免有少量不完整列）。
- 資料正規化（如日期格式）失敗時保留原始字串值，不拋出例外、不視為 `invalid_data_format` 錯誤。
