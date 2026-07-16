# TaskLog 2026-07-16:iOS 版本(公務機)

狀態:**階段 1-3+5 完成(ody 契約 say-something-ios-20260716 複驗通過),待階段 4 實機驗收與 push**

## 待辦

- [x] 技術查證:鍵盤延伸錄音限制、PWA 語音辨識限制、側載限制(2026-07-16,[Claude@Mac])
- [x] 提出企劃(方案 A/B/C 比較);使用者拍板:直接做 B、不上架內部側載、無 MDM
- [x] 實作計畫寫入 PRD;Xcode 26.6 環境確認;版控白名單擴充(`rules/git-sync-whitelist.md`)
- [x] 使用者確認實作計畫,分工 ody 小隊(2026-07-16)
- [x] 階段 1 骨架:`ios/SaySomething.xcodeproj`(SwiftUI、min iOS 16、手寫 pbxproj、shared scheme)+ .gitignore
- [x] 階段 2 核心:Recorder(AAC .m4a)、GeminiClient(v1beta inline_data)、Prompts 七模式、KeychainStore、HistoryStore(30 筆)
- [x] 階段 3 UI:ContentView(麥克風/模式/結果/複製)、SettingsView(key/模型/語言)、HistoryView、safe-area
- [x] 階段 5 文件:`ios/README.md`(安裝+7 天重簽 SOP);mirror commit
- [x] 階段 4 實機(部分):開發者模式、簽名(Personal Team WHCB3237U2)、App 已裝上 iPhone X 並啟動——踩點:CLI codesign 缺鑰匙圈權限(errSecInternalComponent,改 Xcode GUI Run)、Xcode 需完整磁碟取用權才能讀 Drive、需信任開發者憑證
- [ ] 階段 4 功能驗收:實機講話→潤飾→複製(待使用者回報)
- [x] 階段 6 鍵盤延伸實作(契約 say-something-ios-keyboard-20260716,Wispr Flow session 架構,PRD 階段 6 節):鍵盤 target+SessionService 背景保活+KeyboardBridge(Darwin+App Group,UIPasteboard 降級)+私有 API 彈回(含手動降級),兩處 simulator 建置 exit 0
- [ ] 階段 6 實機驗收:重新安裝、啟用鍵盤+Full Access、任意 App 輸入框講話→潤飾直入(App Group 免費帳號可用性、suspend 私有 API、背景 session 存活時長皆待實測)
- [x] 階段 7 本地轉錄實作(契約 say-something-ios-whisper-20260716):whisper.cpp v1.6.2 vendor 進主 App(純 CPU/NEON,鍵盤 target 零觸碰)、WhisperTranscriber(load-per-use)、ModelManager(HF 官方 ggml 模型下載,q5_1——q5_0 該尺寸不存在已驗證 404)、GeminiClient.polishText 純文字路徑、設定可切本地/雲端
- [ ] 階段 7 實機驗收:下載模型、實測 iPhone X 轉錄速度/記憶體(10-30 秒為估計值未實測)、背景下載完成度
- [ ] push 到 GitHub(待使用者確認)
- [ ] (選配)AppIcon 實際圖示;三端模式同步(web 已有第 8 模式「簡潔」,Android/iOS 停在 7 模式)

## 複驗紀錄(2026-07-16,[Claude@Mac])

- coach check PASS(9 條驗收);ody-verifier 首輪 FAIL(mirror 未 commit、_context 未更新)→ 修正後複驗通過。
- 遺留風險(verifier 列,不阻擋):API key 走 URL query(與 Android 同構)、長錄音整檔進記憶體無上限、web/Android/iOS 模式清單已漂移。
