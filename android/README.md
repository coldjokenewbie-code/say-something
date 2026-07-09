# Say Something 鍵盤 (Android)

一個語音輸入法(IME):在**任何 App** 點輸入框,切到這個鍵盤,按麥克風講話,Gemini 會把錄音轉錄並潤飾,**直接把整理好的文字打進該輸入框** — 不需要複製貼上。

中文為主、夾雜英文的講話沒問題:Gemini 直接聽原始音檔,英文詞會保留成英文。

## 它怎麼運作

- 是一個系統輸入法(`InputMethodService`),不是一般 App 畫面
- 按麥克風 → `MediaRecorder` 錄成 AAC → 傳給 Gemini `generateContent`(轉錄+潤飾)→ 用 `InputConnection.commitText()` 寫進目前聚焦的輸入框
- API key 只存在手機本機(`SharedPreferences`),直接連 Google,沒有中間伺服器
- 鍵盤上可切換模式(潤飾 / 原樣 / 正式 / 訊息 / Email / 筆記 / 翻譯)、空白、退格、Enter、切換回其他鍵盤

## 建置(需要 Android Studio)

1. 用 Android Studio 開啟這個 `android/` 資料夾(不是整個 repo 根目錄)
2. 等 Gradle 同步完成(會自動下載 Gradle 8.7 與相依套件)
3. 接上手機(開啟 USB 偵錯)或用模擬器,按 ▶ Run;或 `Build → Build APK` 產生 APK 再傳到手機安裝

命令列(需先安裝 Android SDK 並設定 `local.properties` 的 `sdk.dir`):

```bash
cd android
gradle wrapper          # 第一次:產生 gradlew
./gradlew assembleDebug  # 輸出 app/build/outputs/apk/debug/app-debug.apk
```

## 安裝後設定(只需一次)

打開「Say Something 鍵盤」App:

1. 填入 Gemini API key([免費取得](https://aistudio.google.com/apikey)),選模型與輸出語言,按「儲存設定」
2. 按「授予麥克風權限」
3. 按「在系統設定啟用此鍵盤」→ 打開開關
4. 按「選擇此鍵盤為輸入法」

之後在任何 App 點輸入框,從右下角鍵盤圖示切到「Say Something 鍵盤」,按麥克風講話即可。

## 需求

- minSdk 24(Android 7.0)以上
- 網路連線(呼叫 Gemini)
- 麥克風權限
