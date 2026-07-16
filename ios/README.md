# Say Something — iOS 版

公務機(iPhone X、iOS 16.7.16,永遠無法升 iOS 17)用的原生 App:按麥克風講話(中文為主夾英文)→ Gemini 聽原始音檔轉錄+潤飾 → 顯示文字一鍵複製。另含 **SaySomethingKeyboard** 鍵盤延伸,可把潤飾結果直接插入任何 App 的輸入框(Session 式架構,見下方「鍵盤延伸」一節)。

不上架 App Store,內部側載使用(免費 Apple ID,7 天重簽)。

## 專案結構

```
ios/
  SaySomething.xcodeproj/       Xcode 專案(兩個 target:App + 鍵盤延伸)
  SaySomething/                 主 App(bundle id com.saysomething.app)
    SaySomethingApp.swift       App 進入點,含 saysomething://session URL 進入點
    ContentView.swift           主畫面:模式選擇 + 麥克風鈕 + 結果區 + 複製鈕
    SettingsView.swift          設定頁:API key / 模型 / 輸出語言
    HistoryView.swift           歷史紀錄(近 30 筆)
    Recorder.swift              AVAudioSession + AVAudioRecorder,錄 .m4a AAC(App 內按鈕手動錄音路徑)
    SessionService.swift        鍵盤延伸的背景保活服務:AVAudioEngine 常駐 + Darwin notification 驅動的擷取/轉錄/潤飾
    GeminiClient.swift          URLSession 呼叫 Gemini v1beta generateContent(inline audio base64)
    Prompts.swift                七種模式 prompt(與 android/.../Prompts.kt 等義移植;App 與鍵盤延伸兩個 target 共用同一份原始檔)
    Settings.swift               模型/語言/模式設定(UserDefaults)+ API key 存取(轉呼叫 Keychain)
    KeychainStore.swift          API key 存取,走 SecItem API,不落 UserDefaults
    HistoryStore.swift           歷史紀錄存取(UserDefaults JSON,上限 30 筆)
    Info.plist                   含 NSMicrophoneUsageDescription、UIBackgroundModes(audio)、saysomething:// URL scheme
    SaySomething.entitlements    App Group(group.com.saysomething.app)
    Assets.xcassets              App 圖示 / 主題色(僅骨架,尚未放實際圖示)
  SaySomethingKeyboard/         鍵盤延伸 target(bundle id com.saysomething.app.keyboard)
    KeyboardViewController.swift 鍵盤 UI:🎤/停止、七模式切換、插入最新結果、退格/空白/換行/切換鍵盤(globe)、啟動 session 鈕
    Info.plist                   NSExtension(com.apple.keyboard-service)、RequestsOpenAccess=YES、PrimaryLanguage zh-Hant
    SaySomethingKeyboard.entitlements  App Group(同上,與主 App 共用)
  Shared/
    KeyboardBridge.swift        兩 target 共用的跨進程橋接:Darwin notification 信號 + App Group(降級走 named UIPasteboard)資料通道
```

Deployment target:iOS 16.0(兩個 target 皆同)。SwiftUI lifecycle,Swift 5,只用 iOS 16 可用 API。

## 鍵盤延伸(Session 式架構,同 Wispr Flow)

iOS 系統禁止鍵盤延伸自己錄音(即使開 Full Access 也一樣),所以採業界做法:**主 App 在背景常駐錄音保活,鍵盤只是遙控器**。

### 啟用鍵盤

1. 用上方「安裝步驟」把主 App(SaySomething)側載進 iPhone X。
2. 設定 → 一般 → 鍵盤 → 鍵盤 → 新增新鍵盤 → 選「SaySomething」。
3. 回到鍵盤列表點「SaySomething」→ 開啟「允許完整取用」(Full Access)。沒開這個鍵盤無法讀寫 App Group 共享容器 / 呼叫網路,功能會整個不能用。

### Session 啟動流程

1. 在任何 App 的輸入框切到 SaySomething 鍵盤,按「啟動 Say Something」(或直接按🎤,鍵盤偵測到 session 未啟動時會自動導去啟動)。
2. 鍵盤透過 responder chain 呼叫 `openURL:` 開啟 `saysomething://session`,跳轉到主 App。
3. 主 App 收到這個 URL 後,啟動 AVAudioEngine 背景保活(裝好 tap,擷取關閉時樣本直接丟棄不寫檔),然後嘗試呼叫私有 API `-[UIApplication suspend]` 自動把你彈回原本輸入的那個 App。
4. 若自動彈回失敗(私有 API 在該 iOS 版本上不可用或無效),App 畫面會顯示「請切回原本輸入的 App」提示,需要自己手動切回去。
5. 切回輸入框後,再按鍵盤的🎤開始講話 → 按停止 → 稍候(最多 60 秒)→ 結果自動插入,或按「插入最新結果」手動插入。

### 跨進程通訊

- **信號**:CFNotificationCenter Darwin notification(鍵盤 → App:開始/停止錄音;App → 鍵盤:結果就緒/錯誤)。不需要 App Group 也能送。
- **資料**(模式、狀態、結果文字、心跳時間戳):優先走 App Group(`group.com.saysomething.app`)共享 UserDefaults;若執行期偵測到 App Group 容器讀寫不通(免費 Personal Team 簽名對 App Group 的支援未經驗證),自動降級改走 named `UIPasteboard`(JSON blob),行為對使用者透明。

## 安裝步驟(側載到 iPhone X)

1. **接上 Mac**:用 Lightning 線把 iPhone X 接到有裝 Xcode 的 Mac(本專案用 Xcode 26.6 開發)。
2. **iPhone 啟用開發者模式**(第一次側載才需要):
   - 設定 → 隱私權與安全性 → 捲到最下面找「開發者模式」→ 開啟 → 依提示重新開機 → 開機後再次確認「開啟」。
3. **開啟專案**:雙擊 `ios/SaySomething.xcodeproj`(或 `open SaySomething.xcodeproj`)用 Xcode 開啟。
4. **選 Personal Team 簽名(兩個 target 都要簽)**:
   - 左側點選專案 → TARGETS → SaySomething → Signing & Capabilities → Team 選你的 Apple ID(沒有的話點「Add an Account…」用免費 Apple ID 登入)
   - 再切到 TARGETS → SaySomethingKeyboard → Signing & Capabilities → Team 選同一個 Apple ID(鍵盤延伸是獨立 target,不簽名的話 App 會建置成功但裝不上機或鍵盤延伸裝不進去)
   - Bundle Identifier 若跟其他裝置上已裝的 App 衝突,可自行改成 `com.saysomething.app.你的名字`(鍵盤延伸則對應改成 `com.saysomething.app.你的名字.keyboard`,兩者要維持「延伸 id = App id + .keyboard」的巢狀關係,否則 Xcode 會拒絕 embed)
   - 免費 Personal Team 對 App Group(`group.com.saysomething.app`)entitlement 的支援未驗證;若 Xcode 簽名時對 App Group capability 報錯,可以兩個 target 都先移除 App Group capability 再簽 —— 程式碼在執行期偵測不到可用的 App Group 容器時會自動降級走 named UIPasteboard 傳資料,鍵盤仍可運作。
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

在 `ios/` 目錄下用 simulator SDK 驗證專案可編譯(不需要簽名、不需要實機)。這個指令會連同 SaySomethingKeyboard 鍵盤延伸 target 一起建置並 embed 進 App(鍵盤延伸是主 App target 的依賴,建置 SaySomething scheme 就會自動連帶建它):

```bash
xcodebuild -project SaySomething.xcodeproj -scheme SaySomething -sdk iphonesimulator build CODE_SIGNING_ALLOWED=NO
```

實機安裝仍需照上方「安裝步驟」在 Xcode 內選 Personal Team 簽名後 Run(兩個 target 都要簽)。

## 已知限制

- 未上架 App Store,僅供內部側載使用,語音內容會送至 Google Gemini API 處理(潤飾/轉錄),請避免處理高度機敏內容。
- 免費帳號同一 Apple ID 最多同時側載 3 個 App(App + 鍵盤延伸算同一個 App,不會多佔額度)。
- App 圖示(`Assets.xcassets/AppIcon.appiconset`)目前為空白骨架,尚未放入實際圖示圖檔,不影響功能運作。
- **鍵盤延伸不能自己錄音**(iOS 系統限制),每次要用語音輸入都得先透過鍵盤的「啟動 Say Something」跳轉主 App 一次,啟動背景保活 session 後才能開始講話。
- **Session 會被系統回收**:iOS 可能因記憶體壓力或閒置太久把主 App 的背景保活殺掉;鍵盤用共享容器裡的心跳時間戳判斷 session 是否還活著(超過約 20 秒沒更新心跳就視為失效),失效後鍵盤會提示重新啟動一次 session,體驗上等於「每個使用階段的第一次要多跳轉一次」。
- 私有 API `-suspend` 自動彈回若在某些 iOS 16.7 子版本上失效,會退化成手動切回原 App(App 內會顯示提示橫幅),此為刻意保留的降級路徑而非 bug。
- App Group 共享容器在免費 Personal Team 簽名下能否穩定運作未經實機驗證;程式碼已內建 runtime 偵測與 named UIPasteboard 降級,失敗時鍵盤仍可運作,只是資料通道換了介質。
