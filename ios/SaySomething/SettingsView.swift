import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var modelManager = ModelManager.shared
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

                Section(
                    header: Text("轉錄方式"),
                    footer: Text(settings.transcriptionMode == "local"
                        ? "錄音在手機本地轉文字,只有整理過的文字會送到 Gemini。聲音檔不會離開這台裝置,但速度較慢、中英夾雜辨識較弱。"
                        : "錄音檔直接送到 Gemini 聽寫並整理,品質最好、速度最快,但聲音內容會離開裝置。")
                ) {
                    Picker("轉錄方式", selection: $settings.transcriptionMode) {
                        Text("本地 whisper(預設,聲音不出手機)").tag("local")
                        Text("雲端 Gemini(送音檔,品質最好)").tag("cloud")
                    }
                    .pickerStyle(.inline)
                }

                if settings.transcriptionMode == "local" {
                    Section(header: Text("本地轉錄語言")) {
                        Picker("辨識語言", selection: $settings.whisperLanguage) {
                            ForEach(AppSettings.whisperLanguages, id: \.value) { lang in
                                Text(lang.label).tag(lang.value)
                            }
                        }
                        .pickerStyle(.inline)
                    }

                    Section(
                        header: Text("轉錄模型"),
                        footer: Text("模型不會隨 App 打包,第一次使用前需連網下載一次,之後都在裝置本機轉錄。")
                    ) {
                        ForEach(ModelManager.models) { model in
                            modelRow(model)
                        }
                    }
                }

                Section(header: Text("Gemini 模型")) {
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
            .alert("模型下載發生問題", isPresented: Binding(
                get: { modelManager.lastError != nil },
                set: { if !$0 { modelManager.lastError = nil } }
            )) {
                Button("好", role: .cancel) { modelManager.lastError = nil }
            } message: {
                Text(modelManager.lastError ?? "")
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private func modelRow(_ model: WhisperModelInfo) -> some View {
        // Reading storageRevision here (unused otherwise) is what makes this
        // row re-render after ModelManager.delete/download-completion, since
        // isDownloaded/fileSizeBytes are plain FileManager calls rather than
        // their own @Published properties.
        let _ = modelManager.storageRevision
        let downloaded = modelManager.isDownloaded(model)
        let progress = modelManager.downloadProgress[model.id]

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    settings.whisperModelId = model.id
                } label: {
                    HStack {
                        Image(systemName: settings.whisperModelId == model.id ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(settings.whisperModelId == model.id ? .accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.displayName).font(.body)
                            Text(modelSubtitle(model, downloaded: downloaded)).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if let progress {
                    ProgressView(value: progress)
                        .frame(width: 60)
                    Button("取消") { modelManager.cancelDownload(model) }
                        .font(.caption)
                } else if downloaded {
                    Button(role: .destructive) { modelManager.delete(model) } label: {
                        Image(systemName: "trash")
                    }
                } else {
                    Button("下載") { modelManager.startDownload(model) }
                        .font(.callout)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func modelSubtitle(_ model: WhisperModelInfo, downloaded: Bool) -> String {
        if downloaded, let bytes = modelManager.fileSizeBytes(for: model) {
            let mb = Double(bytes) / 1_048_576
            return "\(model.note) · 已下載,佔用 \(String(format: "%.0f", mb)) MB"
        }
        return "\(model.note) · 尚未下載"
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView().environmentObject(AppSettings())
    }
}
