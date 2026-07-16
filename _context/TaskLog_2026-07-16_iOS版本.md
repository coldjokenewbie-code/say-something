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
- [ ] 階段 4 實機:iPhone X 開發者模式、Xcode Run 安裝、逐條驗收(PRD 驗收條件)——**需使用者接機**
- [ ] push 到 GitHub(待使用者確認)
- [ ] (選配)AppIcon 實際圖示;三端模式同步(web 已有第 8 模式「簡潔」,Android/iOS 停在 7 模式)

## 複驗紀錄(2026-07-16,[Claude@Mac])

- coach check PASS(9 條驗收);ody-verifier 首輪 FAIL(mirror 未 commit、_context 未更新)→ 修正後複驗通過。
- 遺留風險(verifier 列,不阻擋):API key 走 URL query(與 Android 同構)、長錄音整檔進記憶體無上限、web/Android/iOS 模式清單已漂移。
