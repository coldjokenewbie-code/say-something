# 資料夾分工總則（2026-07-08：workingfiles 併入 outputs）

多數協作專案迭代週期長（以月／年計），「定案交付版」是稀有事件；為此常態維護
`workingfiles/`（過程稿）與 `outputs/`（定案）兩棵樹，日常每次找檔都要多判斷一次
「這算過程還是定案」，成本大於效益。改用單一 `outputs/` 樹。

## 標準子夾

| 子夾 | 用途 |
|---|---|
| `_context/` | 知識與紀錄（INDEX、PRD、TaskLog、Handover、lessons、archive）|
| `rules/` | 專案規則 |
| `outputs/` | 唯一工作與產出樹（見下） |
| `tools/` | 本專案處理腳本 |

## outputs/ 內部規則

- **最外層＝目前最新版本**（不管是不是最終定案，就是現在這個當下最好的版本），agent／使用者直接找這裡，不必先判斷「這是不是最終版」。
- **`archive/`＝已被取代的內容**：舊版文件、逐版驗證截圖、廢棄腳本、多版本 docx 全部丟這裡，不再細分「這是草稿還是舊定案」。子夾內建議照 `outputs/<子專案>/archive/<原始資料夾名>/` 保留原結構，方便追溯。
- **`outputs/_shared/`**：跨子專案共用的過程檔／參考清單／驗證截圖（不屬於單一子專案時放這裡，取代舊 `workingfiles/_screenshots/`、`workingfiles/_scripts/`）。
- 舊版本一律進 `archive/`，禁止在最外層多版本平鋪並存。

## 多子專案專案的資料夾命名（有 `reference/`／`infomation/` 或多個子專案時適用）

若專案含多個子專案（例如 A/B/C 展區、多產品線），且另有 `reference/`（視覺參考）、
`infomation/`（業主／官方原始資料）等資料夾，子專案子夾一律用**半形字元＋
`_ref`／`_info` 後綴**（例：`A_ref`、`A_info`），並與 `outputs/` 內對應子專案資料夾
名稱互相呼應，讓「講一個子專案代號」時 agent 能直接對應到三層裡的正確資料夾，
不必每次現場核對命名。若同一子專案內有多條獨立工作線（例如同時有網頁版與
App 版），依工作線分別命名（如 `B_kiosk_ref`／`B_apk_ref`），不要合併成一個籠統的
資料夾。

實際子專案對照表屬專案層知識，寫在該專案的 `rules/folder-conventions.md`
（覆蓋本檔）或 `_context/INDEX.md`，不寫在此全域範本。

## 原則
- 內容為暫時性過程稿放 `archive/` 或 `_shared/`，驗收或任務完成後可清除。
- 腳本由 AI 產生，用途明確後可移至 `tools/`（長期重跑）或留在 `archive/`（一次性）。
- 舊 `workingfiles/` 命名規則（`_screenshots/`、`_scripts/` 兩子夾）已失效，等效內容現為 `outputs/_shared/_screenshots/`、`outputs/_shared/_scripts/`。
