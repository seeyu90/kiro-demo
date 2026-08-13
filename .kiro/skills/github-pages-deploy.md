# GitHub Pages 發布技能

來源：https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site

## 本專案發布方式

**Deploy from a branch**（不使用 GitHub Actions）

- Branch：`main`
- 資料夾：`/docs`
- 所有網站檔案必須放在 `docs/` 目錄下

## 設定步驟（一次性）

1. 前往 GitHub repo → Settings → Pages
2. Build and deployment > Source：選 **Deploy from a branch**
3. Branch 選 `main`，資料夾選 `/docs`
4. 按 Save

完成後，每次 push 到 `main`，`docs/` 內的變更會自動發布。

## 驗證標準

- Settings > Pages 顯示 `Your site is live at https://<user>.github.io/<repo>/`
- 修改 `docs/index.html` 並 push 後，約 1–2 分鐘內線上頁面反映變更

## 注意事項

- `docs/` 目錄必須存在於 `main` branch；若刪除會觸發 build error
- 不需要 `.nojekyll` 檔案（純靜態檔案，Jekyll 不會干擾）
- 不使用 `gh-pages` branch，也不需要任何 CI workflow

## 檔案結構規範

```
docs/
├── index.html      # 網站入口
├── style.css       # 樣式
└── app.js          # 邏輯（如有需要）
```
