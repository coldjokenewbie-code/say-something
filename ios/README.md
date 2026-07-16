# Say Something — iOS 版

公務機(iPhone X、iOS 16.7.16,永遠無法升 iOS 17)用的原生 App:按麥克風講話(中文為主夾英文)→ 轉錄+潤飾 → 顯示文字一鍵複製。另含 **SaySomethingKeyboard** 鍵盤延伸,可把潤飾結果直接插入任何 App 的輸入框(Session 式架構,見下方「鍵盤延伸」一節)。

轉錄方式在設定頁可切換(見下方「本地 vs 雲端轉錄」一節):**本地 whisper.cpp**(預設,聲音不出手機,只送文字給 Gemini 潤飾)或 **雲端 Gemini**(送原始音檔給 Gemini 聽寫+潤飾,品質最好)。

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
    WhisperTranscriber.swift     本地轉錄:AVAudioConverter 轉 16kHz mono Float32 → whisper.cpp whisper_full() → 純文字;load-per-use(用完即 whisper_free,不常駐記憶體)
    ModelManager.swift           whisper ggml 模型下載管理(背景 URLSession + 進度)、存放/刪除,含 AppDelegate(接背景下載完成回呼)
    SaySomething-Bridging-Header.h   把 Vendor/whisper.cpp/whisper.h 的 C API 橋接給 Swift(僅主 App target)
    Info.plist                   含 NSMicrophoneUsageDescription、UIBackgroundModes(audio)、saysomething:// URL scheme
    SaySomething.entitlements    App Group(group.com.saysomething.app)
    Assets.xcassets              App 圖示 / 主題色(僅骨架,尚未放實際圖示)
  SaySomethingKeyboard/         鍵盤延伸 target(bundle id com.saysomething.app.keyboard)
    KeyboardViewController.swift 鍵盤 UI:🎤/停止、七模式切換、插入最新結果、退格/空白/換行/切換鍵盤(globe)、啟動 session 鈕
    Info.plist                   NSExtension(com.apple.keyboard-service)、RequestsOpenAccess=YES、PrimaryLanguage zh-Hant
    SaySomethingKeyboard.entitlements  App Group(同上,與主 App 共用)
  Shared/
    KeyboardBridge.swift        兩 target 共用的跨進程橋接:Darwin notification 信號 + App Group(降級走 named UIPasteboard)資料通道
  Vendor/whisper.cpp/           whisper.cpp 原始碼(vendored,只掛主 App target,見下方「本地轉錄引擎」)
```

Deployment target:iOS 16.0(兩個 target 皆同)。SwiftUI lifecycle,Swift 5,只用 iOS 16 可用 API。

## 本地 vs 雲端轉錄

設定頁「轉錄方式」可切換,重啟後保留選擇:

| | 本地 whisper(預設) | 雲端 Gemini |
|---|---|---|
| 聲音檔案 | **不離開手機**,只在裝置本地轉文字 | 送到 Google Gemini API |
| 送到 Gemini 的內容 | 只有轉錄出的**純文字**(供潤飾) | 原始錄音檔(Gemini 直接聽寫+潤飾) |
| 速度 | 較慢(見下方效能預期) | 較快(單次 API 呼叫) |
| 中英夾雜辨識品質 | 較弱(local whisper 對code-switch較不擅長) | 較好 |
| 需要網路 | 僅潤飾那一步需要(轉錄本身離線) | 全程需要 |
| 適用情境 | 內容較機敏、不想錄音離開裝置 | 追求最佳品質、不在意錄音上雲 |

兩個模式共用同一份 `Prompts.swift` 七模式 prompt(潤飾/原樣/正式/訊息/Email/筆記/翻譯),只是「潤飾」這一步的輸入是文字還是連音檔一起送,語意保持一致。

## 本地轉錄引擎(whisper.cpp)

- **來源**:vendor 進 `ios/Vendor/whisper.cpp/`,取自 [ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp) **v1.6.2** 的必要原始檔(`ggml.c/.h`、`ggml-alloc.c/.h`、`ggml-backend.c/.h/-impl.h`、`ggml-common.h`、`ggml-impl.h`、`ggml-quants.c/.h`、`whisper.cpp/.h`)。
  - **版本選擇說明**:whisper.cpp 從 v1.7.0 起把 ggml 拆成多後端(CUDA/Metal/Vulkan/SYCL/…)的目錄結構,CPU 後端也拆成十幾個檔案並依賴 CMake 做特徵偵測,手寫 pbxproj 整合成本極高、容易漏檔。v1.6.2 是拆分前最後一個扁平結構版本(單一 `ggml.c` 含 CPU/NEON 實作),whisper.cpp 官方 iOS 範例(`examples/whisper.objc`)當年也是用這個結構手動加進 Xcode 專案。功能上 v1.6.2 已支援 q5_1/q8_0 量化模型與繁中/多語辨識,滿足本專案需求。
  - **CPU-only(NEON),沒有 Metal 後端**:`whisper_context_params.use_gpu` 固定為 `false`;沒有 vendor `ggml-metal.m/.h/.metal`。原因:(1) whisper.h/whisper.cpp/ggml.c 對 Metal/CUDA/OpenCL 的 `#include` 都包在 `#ifdef GGML_USE_METAL` 等巨集後面,不定義巨集就完全不會編譯到那些路徑,手寫 pbxproj 不需要額外處理 `.metal` shader 編譯規則;(2) 目標機種 iPhone X(A11)的 Metal 加速在 whisper.cpp 上收益本就有限,純 CPU/NEON 路線更省事也更可預期。
  - C/C++ 混編:`.c`(C11/gnu17,專案既有設定)與 `.cpp`(C++17,專案 `CLANG_CXX_LANGUAGE_STANDARD = gnu++20` 已滿足)透過 `SaySomething-Bridging-Header.h` 匯入 `whisper.h`(純 C ABI,`extern "C"` 包住,Swift 端直接呼叫 `whisper_init_from_file_with_params`/`whisper_full`/`whisper_free` 等函式,無需額外 Objective-C++ wrapper)。
  - **只掛主 App target**:`project.pbxproj` 裡這些檔案的 `PBXBuildFile` 只出現在 `SaySomething` target 的 Sources build phase,`SaySomethingKeyboard` target 的 Sources build phase(以及任何其他 build phase)完全沒有引用——鍵盤延伸的記憶體上限(60-70MB)碰不到 whisper/ggml 的一行程式碼或一個位元組。
  - 不打包 bitcode 相關設定(Xcode 14 起已移除 bitcode,本專案 objectVersion 56 / Xcode 26.6 原生無此概念,不需額外處理)。
- **記憶體策略(load-per-use)**:`WhisperTranscriber.runWhisper` 每次轉錄都呼叫 `whisper_init_from_file_with_params` 載入模型、跑完 `whisper_full`、`defer { whisper_free(ctx) }` 立刻釋放,包含錯誤路徑;沒有任何常駐的 whisper context 或全域快取。A11/3GB 裝置在背景 session 期間不會一直佔著模型的記憶體。

## 模型下載(ModelManager)

- 模型**不隨 App 打包**,執行期才下載,存在 `Application Support/WhisperModels/`。
- 內建兩個模型(URL 皆來自 [huggingface.co/ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp),下載前已用 `curl -I` 驗證可達):

  | 模型 | 檔名 | 大小 | 特性 |
  |---|---|---|---|
  | Small(預設) | `ggml-small-q5_1.bin` | ~190 MB | 中文堪用,較慢 |
  | Base | `ggml-base-q5_1.bin` | ~60 MB | 較快,中文辨識較差 |

  > PRD/契約原先寫「q5_0」,但 ggerganov/whisper.cpp 官方 Hugging Face 倉庫的 small/base 尺寸只發佈 `q5_1`(5-bit)與 `q8_0`(8-bit)量化,沒有 `q5_0`(`curl -I` 對 `ggml-small-q5_0.bin` 回 404,對 `ggml-small-q5_1.bin` 回 200/302 導頁至可下載的 CDN)。改用 `q5_1` 是對「5-bit 量化」原意最接近的正確替代。

- 設定頁「轉錄模型」區可選擇要用哪個模型、看下載進度(百分比)、刪除已下載的模型、重新下載。下載用背景 `URLSession`(`background(withIdentifier:)`),App 被系統背景化時下載仍會繼續。
- 若選擇本地轉錄但模型還沒下載,轉錄會回報「轉錄模型尚未下載,請到設定頁下載模型。」而不是閃退。

## iPhone X 效能預期(未實測,基於 PRD 階段 7 已知取捨)

- **首次使用**:App 需連網下載一次模型(Small ~190MB 或 Base ~60MB),依網路狀況數十秒到數分鐘不等;下載完成後即可離線轉錄。
- **每次轉錄**:iPhone X 是純 CPU(A11,無 Metal 加速路徑),10 秒錄音預估 **10-30 秒**轉錄時間,另外每次轉錄開始都要重新載入模型(load-per-use 策略換取記憶體安全,犧牲一點速度)——Small 模型載入本身可能再加數秒。轉錄完成後才送純文字給 Gemini 潤飾(通常 1-3 秒)。
- 相較雲端 Gemini 模式(直接送音檔,單次 API 呼叫,通常數秒內有結果),本地模式明顯較慢,這是為了聲紋不出手機而接受的已知取捨(PRD 階段 7 已向使用者揭示)。
- 若本地轉錄速度在實機測試中無法接受,可在設定頁隨時切回「雲端 Gemini」模式,兩條路徑都保持可用。

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

- 未上架 App Store,僅供內部側載使用。**雲端 Gemini 模式**下語音內容會送至 Google Gemini API 處理(聽寫+潤飾);**本地 whisper 模式**(預設)聲音不出手機,只有轉錄後的文字會送 Gemini 潤飾。無論哪個模式,請避免處理高度機敏內容。
- 本地轉錄模型需要執行期下載(見上方「模型下載」),App 安裝完第一次使用前需連一次網路;下載完成後轉錄本身可離線進行,只有潤飾那一步需要網路。
- 免費帳號同一 Apple ID 最多同時側載 3 個 App(App + 鍵盤延伸算同一個 App,不會多佔額度)。
- App 圖示(`Assets.xcassets/AppIcon.appiconset`)目前為空白骨架,尚未放入實際圖示圖檔,不影響功能運作。
- **鍵盤延伸不能自己錄音**(iOS 系統限制),每次要用語音輸入都得先透過鍵盤的「啟動 Say Something」跳轉主 App 一次,啟動背景保活 session 後才能開始講話。
- **Session 會被系統回收**:iOS 可能因記憶體壓力或閒置太久把主 App 的背景保活殺掉;鍵盤用共享容器裡的心跳時間戳判斷 session 是否還活著(超過約 20 秒沒更新心跳就視為失效),失效後鍵盤會提示重新啟動一次 session,體驗上等於「每個使用階段的第一次要多跳轉一次」。
- 私有 API `-suspend` 自動彈回若在某些 iOS 16.7 子版本上失效,會退化成手動切回原 App(App 內會顯示提示橫幅),此為刻意保留的降級路徑而非 bug。
- App Group 共享容器在免費 Personal Team 簽名下能否穩定運作未經實機驗證;程式碼已內建 runtime 偵測與 named UIPasteboard 降級,失敗時鍵盤仍可運作,只是資料通道換了介質。
