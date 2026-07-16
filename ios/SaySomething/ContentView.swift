import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var session: SessionService
    @StateObject private var recorder = Recorder()

    @State private var resultText = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var showHistory = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                if session.showManualReturnHint {
                    manualReturnBanner
                }

                modePicker

                Spacer()

                statusLabel

                micButton

                Spacer()

                resultArea
            }
            .padding()
            .navigationTitle("Say Something")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("歷史紀錄")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("設定")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(settings)
            }
            .sheet(isPresented: $showHistory) {
                HistoryView { entry in
                    resultText = entry.text
                    showHistory = false
                }
                .environmentObject(history)
            }
            .alert("發生錯誤", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .navigationViewStyle(.stack)
    }

    /// Shown when the private `-suspend` API auto-return (kicked off from
    /// SessionService after handling `saysomething://session`) couldn't be
    /// confirmed — tells the user to switch back to the app they were
    /// typing in themselves.
    private var manualReturnBanner: some View {
        HStack {
            Image(systemName: "arrow.uturn.backward.circle")
            Text("背景錄音已啟動,請切回原本輸入的 App")
                .font(.footnote)
            Spacer()
            Button("好") { session.showManualReturnHint = false }
                .font(.footnote)
        }
        .padding(10)
        .background(Color.yellow.opacity(0.25))
        .cornerRadius(8)
    }

    private var modePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Prompts.modes) { mode in
                    Button {
                        settings.modeId = mode.id
                    } label: {
                        Text(mode.label)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(settings.modeId == mode.id ? Color.accentColor : Color(.secondarySystemBackground))
                            .foregroundColor(settings.modeId == mode.id ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var statusLabel: some View {
        Group {
            if isProcessing {
                Label("處理中…", systemImage: "waveform")
                    .foregroundColor(.secondary)
            } else if recorder.isRecording {
                Label("錄音中,再按一次停止", systemImage: "mic.fill")
                    .foregroundColor(.red)
            } else {
                Text("按下麥克風開始講話")
                    .foregroundColor(.secondary)
            }
        }
        .font(.callout)
    }

    private var micButton: some View {
        Button(action: handleMicTap) {
            ZStack {
                Circle()
                    .fill(recorder.isRecording ? Color.red : Color.accentColor)
                    .frame(width: 96, height: 96)
                if isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white)
                }
            }
        }
        .disabled(isProcessing)
        .accessibilityLabel(recorder.isRecording ? "停止錄音" : "開始錄音")
    }

    private var resultArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !resultText.isEmpty {
                ScrollView {
                    Text(resultText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 240)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                Button {
                    UIPasteboard.general.string = resultText
                } label: {
                    Label("複製結果", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func handleMicTap() {
        if recorder.isRecording {
            stopAndProcess()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        resultText = ""
        recorder.start { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                errorMessage = error.errorDescription
            }
        }
    }

    private func stopAndProcess() {
        guard let audio = recorder.stop() else {
            errorMessage = "錄音失敗:找不到錄音檔。"
            return
        }
        isProcessing = true
        let mode = settings.currentMode
        let system = Prompts.buildSystem(mode: mode, outputLang: settings.outputLang)
        let apiKey = settings.geminiKey
        let model = settings.model
        let transcriptionMode = settings.transcriptionMode
        let whisperLanguage = settings.whisperLanguage
        let whisperModelId = settings.whisperModelId

        Task {
            do {
                // Main-screen mic button honors the same 轉錄方式 setting as
                // the keyboard Session flow (SessionService.transcribeAndPolish) —
                // local whisper.cpp or cloud Gemini, picked in SettingsView.
                let text = try await SessionService.transcribeAndPolish(
                    audioData: audio.data,
                    transcriptionMode: transcriptionMode,
                    whisperLanguage: whisperLanguage,
                    whisperModelId: whisperModelId,
                    apiKey: apiKey,
                    model: model,
                    system: system,
                    onStatus: { _ in }
                )
                await MainActor.run {
                    resultText = text
                    history.add(text: text, modeLabel: mode.label)
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    if let localized = error as? LocalizedError {
                        errorMessage = localized.errorDescription ?? "發生未知錯誤。"
                    } else {
                        errorMessage = "發生未知錯誤:\(error.localizedDescription)"
                    }
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppSettings())
            .environmentObject(HistoryStore())
            .environmentObject(SessionService.shared)
    }
}
