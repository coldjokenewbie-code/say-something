# 本專案 Drive↔mirror 複製白名單(覆蓋全域規則)

全域白名單(html/css/js/json/md/ts/tsx/jsx/mjs/py/txt/yaml/yml/sh)之外,本專案含原生子專案,**加收**:

- Android(`android/`,既有實務):`.kt` `.xml` `.gradle` `.properties` `.pro`
- iOS(`ios/`):`.swift` `.pbxproj` `.plist` `.entitlements` `.xcconfig` `.xcscheme` `.xcassets` 內容(json/png)、`.storyboard`

排除不變:建置產物(`build/`、`DerivedData/`、`*.ipa`、`*.apk`)一律不入版控(靠 `.gitignore`)。
