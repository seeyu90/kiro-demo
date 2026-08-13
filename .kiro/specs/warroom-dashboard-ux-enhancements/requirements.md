# 需求文件

## 簡介

戰情室靜態展示頁（`docs/index.html`）目前僅能依專案分組顯示任務列表，缺少「未完成任務」的辨識能力：
使用者無法一眼看出哪些任務已逾期、哪些本週到期，也看不到整體進度摘要。本 spec 為既有靜態展示頁
新增 UX 強化功能，聚焦於「未完成任務辨識」與「整體進度摘要」，不改動資料來源結構。

**不納入範圍**：後端 API 串接（本頁面仍為純前端 + 模擬資料）、任務排序、關鍵字搜尋、資料持久化
（篩選狀態不需跨頁面重新整理保留）、多語系。

**技術棧說明**：本 spec 隸屬 `docs/` 靜態站主體，須遵守 `.kiro/steering/project-standards.md` 的
技術限制（純 HTML/CSS/JS、無框架、無建置工具、模擬資料、繁體中文、響應式設計），無例外。

---

## 詞彙表

- **Dashboard_Page**：`docs/index.html`，本 spec 強化的靜態展示頁。
- **模擬資料**：`docs/js/app.js` 內的 `RECORDS` 陣列。
- **逾期任務（Overdue）**：`status` 不為 `completed`，且 `planned_completion_date` 早於今天日期的任務。
- **本週到期任務（Due This Week）**：`status` 不為 `completed`，且 `planned_completion_date` 不晚於本週
  週日 23:59（以瀏覽器當地時間判斷）的任務。**不限定下界**：任何已逾期任務（不論逾期多久）皆屬於
  本週到期任務的子集，「本週到期」在本 spec 中的意義是「不晚於本週結束前應處理」，而非「僅限本週
  Monday–Sunday 區間內」。
- **未完成任務**：`status` 為 `in_progress` 或 `pending`（非 `completed`）的任務。
- **今天**：使用者瀏覽頁面當下，瀏覽器 `new Date()` 所回傳的日期。
- **任務類型（Task Type）**：任務紀錄新增的分類欄位 `task_type`，對齊真實 Google Sheets 資料來源
  （`warroom-data-api-real-source`）的 5 個類型分頁：「功能」「PR」「調整」「遺漏」「臭蟲」。

---

## 需求

### 需求 1：狀態視覺化

**使用者故事：** 身為戰情室使用者，我希望任務狀態能以顏色與文字同時呈現，以便快速掃視且不依賴色覺分辨。

#### 驗收標準

1. THE **Dashboard_Page** SHALL 為「狀態」欄位新增樣式標籤（badge），依 `status` 值套用不同底色與文字。
2. THE **Dashboard_Page** SHALL 確保狀態標籤同時包含文字內容（例如「進行中」），不得僅以顏色作為唯一辨識依據。
3. WHEN 任務為逾期任務，THE **Dashboard_Page** SHALL 在該任務列額外標示「逾期」提示（文字或圖示），與狀態標籤並存。

---

### 需求 2：未完成任務篩選

**使用者故事：** 身為戰情室使用者，我希望畫面預設就聚焦在未完成與逾期的任務，而不是要我自己再手動篩選，以便一打開頁面就掌握需要處理的工作。

#### 驗收標準

1. THE **Dashboard_Page** SHALL 提供一個「只顯示未完成」的切換控制項（checkbox 或 toggle）。
2. WHEN 使用者開啟「只顯示未完成」，THE **Dashboard_Page** SHALL 僅顯示 `status` 為 `in_progress` 或 `pending` 的任務列，隱藏 `completed` 任務列。
3. WHEN 使用者關閉「只顯示未完成」，THE **Dashboard_Page** SHALL 顯示所有任務列，不受篩選影響。
4. WHEN 篩選後某專案區塊內無任何符合條件的任務，THE **Dashboard_Page** SHALL 在該專案區塊顯示「目前無符合條件的任務」，不隱藏整個專案區塊標題。
5. WHEN 使用者切換專案下拉選單，THE **Dashboard_Page** SHALL 保留目前「只顯示未完成」的開關狀態。
6. THE **Dashboard_Page** SHALL 在頁面載入完成時，將「只顯示未完成」預設為開啟狀態，僅顯示未完成任務。
7. WHEN 任務列表（未完成任務範圍內）包含逾期任務，THE **Dashboard_Page** SHALL 將逾期任務排列於該專案區塊任務清單的最前面，其餘任務維持原始資料順序排列於其後。
8. THE **Dashboard_Page** SHALL 在頁面載入完成時，將專案篩選預設為「全部專案」，不預先收斂至單一專案。

---

### 需求 3：本週到期與逾期快速篩選

**使用者故事：** 身為戰情室使用者，我希望畫面預設就顯示本週到期（含所有已逾期）的任務，而不是要我自己再篩選，以便一打開頁面就聚焦最需要處理的項目。

#### 驗收標準

1. THE **Dashboard_Page** SHALL 提供範圍篩選選項，至少包含「全部」「本週到期」「已逾期」三種（單選）。
2. WHEN 使用者選擇「本週到期」，THE **Dashboard_Page** SHALL 僅顯示符合「本週到期任務」定義的任務列（即：不晚於本週週日、含所有已逾期任務，不限逾期發生於本週內）。
3. WHEN 使用者選擇「已逾期」，THE **Dashboard_Page** SHALL 僅顯示符合「逾期任務」定義的任務列。
4. WHEN 使用者選擇「全部」，THE **Dashboard_Page** SHALL 顯示所有任務列（仍受需求 2 的「只顯示未完成」開關影響）。
5. THE **Dashboard_Page** SHALL 以「今天」（瀏覽器當下日期）作為逾期與本週到期的判斷基準，不使用寫死的日期字串。
6. IF 任務的 `planned_completion_date` 為 `null`，THEN THE **Dashboard_Page** SHALL 將該任務排除於「本週到期」與「已逾期」篩選結果之外。
7. THE **Dashboard_Page** SHALL 在頁面載入完成時，將範圍篩選預設值設為「本週到期」。

---

### 需求 4：整體進度摘要

**使用者故事：** 身為戰情室使用者，我希望在畫面最上方看到整體進度統計，以便不需逐筆檢視即可掌握專案健康度。

#### 驗收標準

1. WHEN **Dashboard_Page** 載入完成，THE **Dashboard_Page** SHALL 在任務列表上方顯示摘要列，內容包含：任務總數、已完成數、進行中數、待開始數、逾期數。
2. WHEN 使用者切換專案下拉選單至特定專案，THE **Dashboard_Page** SHALL 將摘要列數字更新為僅反映該專案的統計。
3. WHEN 使用者切換專案下拉選單至「全部專案」，THE **Dashboard_Page** SHALL 將摘要列數字更新為反映所有專案加總的統計。
4. THE **Dashboard_Page** SHALL 確保摘要列的統計數字不受需求 2、需求 3 篩選狀態影響，恆為所選專案範圍內的完整統計。

---

### 需求 5：專案下拉選單顯示任務數

**使用者故事：** 身為戰情室使用者，我希望下拉選單能顯示各專案的任務數，以便選擇前先大致判斷專案規模。

#### 驗收標準

1. THE **Dashboard_Page** SHALL 在下拉選單每個專案選項文字後方附加該專案的任務總數，格式為「<專案名稱>（<任務數>）」。
2. THE **Dashboard_Page** SHALL 在「全部專案」選項文字後方附加所有任務的總數。

---

### 需求 6：任務類型篩選（多選）

**使用者故事：** 身為戰情室使用者，我希望能同時勾選多個任務類型篩選，並預設聚焦「功能」與「PR」，以便優先檢視最重要的兩類工作，同時保留彈性加選其他類型。

#### 驗收標準

1. THE **模擬資料** 每筆任務紀錄 SHALL 新增 `task_type` 欄位，值為「功能」「PR」「調整」「遺漏」「臭蟲」其中之一（對齊 `warroom-data-api-real-source` 的 5 個類型分頁），且每個專案至少包含一筆「功能」與一筆「PR」類型任務。
2. THE **Dashboard_Page** SHALL 在任務表格新增「類型」欄位，顯示每筆任務的 `task_type`。
3. THE **Dashboard_Page** SHALL 提供任務類型篩選控制項，為**多選**（checkbox 群組），選項為模擬資料中實際出現的各個 `task_type` 值；「功能」「PR」須排列於其他類型選項之前。
4. THE **Dashboard_Page** SHALL 在頁面載入完成時，將任務類型篩選預設勾選「功能」與「PR」兩者。
5. WHEN 使用者勾選一或多個任務類型，THE **Dashboard_Page** SHALL 僅顯示 `task_type` 屬於目前勾選集合中任一值的任務列；此篩選須與需求 2（未完成篩選）、需求 3（本週到期／逾期篩選）以 AND 邏輯同時套用。
6. WHEN 使用者取消勾選全部任務類型（勾選集合為空），THE **Dashboard_Page** SHALL 視為不套用類型篩選，顯示所有任務類型的任務列（仍受需求 2、需求 3 篩選影響）。
7. WHEN 任務類型篩選套用後摘要列（需求 4）已在畫面上，THE **Dashboard_Page** SHALL 將摘要列統計數字更新為僅反映目前勾選類型範圍內的任務。

---

### 需求 7：模擬資料具時效性

**使用者故事：** 身為開發者，我希望模擬資料的日期會相對於「今天」動態產生，以便逾期／本週到期篩選在任何檢視時間點都能展示效果。

#### 驗收標準

1. THE **模擬資料** SHALL 包含至少一筆 `planned_completion_date` 早於「今天」且 `status` 非 `completed` 的任務（逾期情境）。
2. THE **模擬資料** SHALL 包含至少一筆 `planned_completion_date` 落在本週區間內且 `status` 非 `completed` 的任務（本週到期情境）。
3. THE **模擬資料** SHALL 包含至少一筆 `planned_completion_date` 晚於本週且 `status` 非 `completed` 的任務（未來到期情境，作為對照組）。
4. THE **模擬資料** 中前述三類任務的 `planned_completion_date` SHALL 以「今天」為基準以相對天數運算產生（例如今天－3 天、今天＋2 天），不使用寫死的絕對日期字串。
