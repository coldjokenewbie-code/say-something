# Say Something 🎙️

用說的,讓 AI 幫你寫好文字 — 一個類似 [Typeless](https://typeless.com) 的語音輸入 Web App。

對著手機、平板或電腦說話,瀏覽器即時轉成文字,再由你選擇的 AI 模型(Claude 或 Gemini)自動去掉贅字、整理成通順的文字、訊息、Email 或筆記。

## 功能

- 🎤 **語音輸入** — 使用瀏覽器內建語音辨識(Web Speech API),支援中文(台灣/普通話/廣東話)、英文、日文、韓文
- ✨ **AI 潤飾** — 六種模式:潤飾、正式、訊息、Email、筆記、翻譯
- 🤖 **多模型** — Claude Opus 4.8 / Sonnet 4.6 / Haiku 4.5、Gemini 2.5 Pro / Flash,隨時切換
- 📱 **跨裝置 PWA** — Android、iPad、桌機瀏覽器都能用,可「加到主畫面」當 App 使用
- 🔒 **隱私** — API key 只存在你裝置的瀏覽器(localStorage),直接呼叫 Anthropic / Google API,沒有中間伺服器
- 🕘 **歷史紀錄** — 最近 30 筆結果存在本機,可隨時叫回

## 使用方式

1. 打開網頁,點右上角 ⚙️ 設定
2. 填入 [Anthropic API key](https://platform.claude.com/) 和/或 [Gemini API key](https://aistudio.google.com/apikey)
3. 按麥克風開始說話,再按一下結束 → AI 自動整理
4. 按「複製」貼到任何地方

> 語音辨識支援:Chrome(Android/桌機)、Edge、Safari(iPhone/iPad/Mac)。Firefox 不支援語音辨識,但仍可打字輸入後用 AI 潤飾。

## 本機開發

```bash
npm install
npm run dev        # http://localhost:3000
npm run build      # 輸出到 dist/
```

## 部署

推到 `main` 分支會自動透過 GitHub Actions 部署到 GitHub Pages(需在 repo Settings → Pages 將 Source 設為「GitHub Actions」)。

⚠️ 語音辨識和剪貼簿功能需要 **HTTPS**(GitHub Pages 預設就是)或 `localhost`。

## 技術

- Vite + TypeScript(無框架)
- [`@anthropic-ai/sdk`](https://github.com/anthropics/anthropic-sdk-typescript)(瀏覽器直連,串流輸出)
- [`@google/genai`](https://github.com/googleapis/js-genai)(串流輸出)
- Web Speech API、PWA(manifest + service worker)

## Android 鍵盤(原生輸入法)

網頁版受瀏覽器沙盒限制,無法把文字直接送進「其他 App」的輸入框。若要「在任何 App 點輸入框 → 講話 → 文字直接出現在框裡」,需要系統層的輸入法。

`android/` 目錄是一個 Android 自訂鍵盤(IME):切到這個鍵盤、按麥克風講話,Gemini 轉錄+潤飾後的文字直接 `commitText` 進當前輸入框,不用複製貼上。建置與安裝說明見 [`android/README.md`](android/README.md)。
