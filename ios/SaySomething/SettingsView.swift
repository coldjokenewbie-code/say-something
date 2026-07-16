import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.presentationMode) private var presentationMode
    @State private var keyDraft = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Gemini API Key"), footer: Text("金鑰只會存在裝置的 Keychain,不會離開這台裝置(離開輸入框時自動存檔)。")) {
                    SecureField("貼上 API key", text: $keyDraft)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: keyDraft) { newValue in
                            settings.geminiKey = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                }

                Section(header: Text("模型")) {
                    Picker("模型", selection: $settings.model) {
                        ForEach(AppSettings.models, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section(header: Text("輸出語言")) {
                    Picker("輸出語言", selection: $settings.outputLang) {
                        ForEach(AppSettings.langs, id: \.value) { lang in
                            Text(lang.label).tag(lang.value)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .onAppear {
                keyDraft = settings.geminiKey
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView().environmentObject(AppSettings())
    }
}
