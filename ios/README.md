# Say Something — iOS 版

公務機(iPhone X、iOS 16.7.16,永遠無法升 iOS 17)用的原生 App:按麥克風講話(中文為主夾英文)→ Gemini 聽原始音檔轉錄+潤飾 → 顯示文字一鍵複製。

不上架 App Store,內部側載使用(免費 Apple ID,7 天重簽)。

## 專案結構

```
ios/
  SaySomething.xcodeproj/       Xcode 專案(單一 App target,bundle id com.saysomething.app)
  SaySomething/
    SaySomethingApp.swift       App 進入點
    ContentView.swift           主畫面:模式選擇 + 麥克風鈕 + 結果區 + 複製鈕
    SettingsView.swift          設定頁:API key / 模型 / 輸出語言
    HistoryView.swift           歷史紀錄(近 30 筆)
    Recorder.swift              AVAudioSession + AVAudioRecorder,錄 .m4a AAC
    GeminiClient.swift          URLSession 呼叫 Gemini v1beta generateContent(inline audio base64)
    Prompts.swift                七種模式 prompt(與 android/.../Prompts.kt 等義移植)
    Settings.swift               模型/語言/模式設定(UserDefaults)+ API key 存取(轉呼叫 Keychain)
    KeychainStore.swift          API key 存取,走 SecItem API,不落 UserDefaults
    HistoryStore.swift           歷史紀錄存取(UserDefaults JSON,上限 30 筆)
    Info.plist                   含 NSMicrophoneUsageDescription(繁中)
    Assets.xcassets              App 圖示 / 主題色(僅骨架,尚未放實際圖示)
```

Deployment target:iOS 16.0。SwiftUI lifecycle,Swift 5,只用 iOS 16 可用 API。

## 安裝步驟(側載到 iPhone X)

1. **接上 Mac**:用 Lightning 線把 iPhone X 接到有裝 Xcode 的 Mac(本專案用 Xcode 26.6 開發)。
2. **iPhone 啟用開發者模式**(第一次側載才需要):
   - 設定 → 隱私權與安全性 → 捲到最下面找「開發者模式」→ 開啟 → 依提示重新開機 → 開機後再次確認「開啟」。
3. **開啟專案**:雙擊 `ios/SaySomething.xcodeproj`(或 `open SaySomething.xcodeproj`)用 Xcode 開啟。
4. **選 Personal Team 簽名**:
   - 左側點選專案 → TARGETS → SaySomething → Signing & Capabilities
   - Team 下拉選你的 Apple ID(沒有的話點「Add an Account…」用免費 Apple ID 登入)
   - Bundle Identifier 若跟其他裝置上已裝的 App 衝突,可自行改成 `com.saysomething.app.你的名字` 之類的唯一值
5. **選裝置並 Run**:
   - 上方裝置選單選你接上的 iPhone X
   - 按左上角 ▶️(Run)。第一次會要求信任開發者憑證:iPhone 上「設定 → 一般 → VPN 與裝置管理」→ 找到你的 Apple ID → 信任
   - 再次 Run,App 會安裝並自動開啟
6. **開啟麥克風權限**:第一次錄音會跳出系統權限對話框,按「允許」。
7. **設定 Gemini API key**:App 內右上角齒輪 → 貼上 key(存在裝置 Keychain,不會離開裝置)→ 完成。

## 7 天重簽 SOP(免費 Apple ID 限制)

免費 Apple ID 簽名的 App,系統會在 **7 天後讓它失效**:圖示變成灰色、點下去打不開。

**恢復方式**(資料全部保留,不用重新設定):

1. 把 iPhone 接回同一台 Mac
2. 用 Xcode 開啟 `ios/SaySomething.xcodeproj`(專案不用改任何東西)
3. 上方裝置選單確認選到該台 iPhone X
4. 按 ▶️(Run)——Xcode 會重新簽名並覆蓋安裝同一個 App
5. 圖示恢復正常顏色,App 內設定(API key、模型、輸出語言、歷史紀錄)全部維持原狀

建議每週固定接一次 Mac(例如週一早上)重新 Run,避免忘記導致當天要用時打不開。

若想減少這個麻煩,之後可以考慮:
- **AltStore**:裝在 Mac 上,同一個 Wi-Fi 下會自動幫 iPhone 重簽,不用每次手動接 Xcode
- **付費 Apple Developer Program(US\$99/年)**:改用 Ad Hoc 簽名,一年才需重簽一次,體驗最接近 Android 的 APK 側載

## 驗證建置(開發用,非簽名安裝)

在 `ios/` 目錄下用 simulator SDK 驗證專案可編譯(不需要簽名、不需要實機):

```bash
xcodebuild -project SaySomething.xcodeproj -scheme SaySomething -sdk iphonesimulator build CODE_SIGNING_ALLOWED=NO
```

實機安裝仍需照上方「安裝步驟」在 Xcode 內選 Personal Team 簽名後 Run。

## 已知限制

- 未上架 App Store,僅供內部側載使用,語音內容會送至 Google Gemini API 處理(潤飾/轉錄),請避免處理高度機敏內容。
- 免費帳號同一 Apple ID 最多同時側載 3 個 App。
- App 圖示(`Assets.xcassets/AppIcon.appiconset`)目前為空白骨架,尚未放入實際圖示圖檔,不影響功能運作。
