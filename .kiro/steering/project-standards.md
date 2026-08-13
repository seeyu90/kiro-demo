---
inclusion: always
---

# Project Standards (Steering)

## Active Skills
- **karpathy-guidelines** — 最簡方案、無多餘抽象、每項任務需有可驗證標準。

## 適用範圍
以下「技術限制」「檔案結構」「響應式設計」規則，適用於 `docs/` 目錄下、透過 GitHub Pages
發布的靜態課程展示站主體。

個別 spec（`.kiro/specs/<spec-name>/`）若有明確理由需要不同技術棧（例如需要真實可運作的
後端邏輯，而非靜態展示），可在該 spec 的 requirements.md 中明確註明例外與理由，該 spec
即不受本檔「技術限制」「響應式設計」段落約束；但仍須遵守「資料與語言」段落（模擬資料、
繁體中文介面）與 karpathy-guidelines 的最簡方案原則。目前已知例外：
`warroom-data-api-prototype`（改用 Ruby on Rails 獨立伺服器，見該 spec 的「技術棧說明」）。

## 技術限制（適用於 `docs/` 靜態站主體）
- 純 HTML／CSS／JavaScript，不使用任何框架（React、Vue、Angular 等）
- 不使用 Node.js、Vite 或任何建置工具
- 不呼叫外部 API

## 檔案結構
- 靜態站主體所有檔案放在 `docs/` 目錄下
- GitHub Pages 從 `main` 分支的 `docs/` 資料夾發布
- 不受「技術限制」約束的個別 spec（如 Rails 雛型），其程式碼可放在各自 spec 對應的獨立目錄下，不進入 `docs/`

## 資料與語言
- 所有資料使用模擬資料（hardcoded 或 JavaScript 物件）
- 介面語言使用繁體中文

## 響應式設計
- 須支援桌機、平板、手機
- 使用 CSS media query 實作

## 工作流程（依 karpathy-guidelines）
1. 每項工作開始前，先陳述可驗證的完成標準。
2. 選擇最簡單可行方案。
3. 只實作需要的部分。
4. 對照標準驗證後，才算完成。
