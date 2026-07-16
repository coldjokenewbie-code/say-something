import Foundation
import AVFoundation
import UIKit
import Combine

/// Owns the main App's side of the Session-style keyboard extension
/// (Wispr Flow architecture): a background-kept-alive AVAudioEngine that
/// only actually records to a file while the keyboard tells it to, driven
/// entirely by Darwin notifications from SaySomethingKeyboard.
///
/// Lifecycle: the keyboard opens `saysomething://session`, which the App
/// handles in `handleSessionURL`. That starts the keep-alive engine (tap
/// installed, samples discarded until a capture is requested) and then
/// tries to bounce the user straight back to whatever App they were typing
/// in via the private `-[UIApplication suspend]` API (side-loaded, no App
/// Review to satisfy). If that private selector isn't available/doesn't
/// take effect, `showManualReturnHint` flips on so the UI can tell the
/// user to switch back manually.
final class SessionService: NSObject, ObservableObject {
    static let shared = SessionService()

    @Published private(set) var isKeepAliveActive = false
    @Published var showManualReturnHint = false
    @Published var lastError: String?

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var isCapturingToFile = false
    private var heartbeatTimer: Timer?
    private var observersRegistered = false

    private override init() {
        super.init()
    }

    // MARK: - Entry point: saysomething://session

    func handleSessionURL(_ url: URL) {
        guard url.scheme == KeyboardBridge.sessionURLScheme else { return }
        startKeepAlive()
        KeyboardBridge.post(.sessionStarted)
        attemptAutoReturn()
    }

    /// Private-API auto-return. Wrapped defensively: check `responds(to:)`
    /// before calling, and if we're still in the foreground half a second
    /// after attempting it, assume it silently failed and show the manual
    /// fallback hint instead of leaving the user stuck looking confused.
    private func attemptAutoReturn() {
        showManualReturnHint = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let suspendSelector = Selector(("suspend"))
            guard UIApplication.shared.responds(to: suspendSelector) else {
                self.showManualReturnHint = true
                return
            }
            UIApplication.shared.perform(suspendSelector)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                // If suspend() worked, the app is backgrounded and this
                // closure won't meaningfully run until foregrounded again
                // (at which point showing the hint briefly is harmless).
                self?.showManualReturnHint = true
            }
        }
    }

    // MARK: - Background keep-alive engine

    func startKeepAlive() {
        registerSignalObserversOnce()
        guard !isKeepAliveActive else {
            markHeartbeatAndArmTimer()
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            lastError = "無法啟用背景錄音保活:\(error.localizedDescription)"
            return
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            // Keep-alive tap: while no capture is in progress, samples are
            // simply dropped on the floor — this is what lets the engine
            // stay running in the background without writing anything.
            self?.writeBufferIfCapturing(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
            isKeepAliveActive = true
            markHeartbeatAndArmTimer()
        } catch {
            lastError = "無法啟動錄音保活引擎:\(error.localizedDescription)"
        }
    }

    private func markHeartbeatAndArmTimer() {
        KeyboardBridge.markHeartbeat()
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            KeyboardBridge.markHeartbeat()
        }
    }

    private func writeBufferIfCapturing(_ buffer: AVAudioPCMBuffer) {
        guard isCapturingToFile, let file = audioFile else { return }
        try? file.write(from: buffer)
    }

    // MARK: - Darwin notifications: keyboard → app

    private func registerSignalObserversOnce() {
        guard !observersRegistered else { return }
        observersRegistered = true
        KeyboardBridge.addObserver(.recordStart) { [weak self] in self?.beginCapture() }
        KeyboardBridge.addObserver(.recordStop) { [weak self] in self?.finishCaptureAndProcess() }
    }

    private func beginCapture() {
        guard isKeepAliveActive else {
            publishError("背景保活尚未啟動,請重新開啟 App。")
            return
        }
        let format = engine.inputNode.outputFormat(forBus: 0)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("saysomething-session-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        do {
            audioFile = try AVAudioFile(forWriting: url, settings: settings)
            isCapturingToFile = true
            KeyboardBridge.setString("recording", for: .status)
        } catch {
            audioFile = nil
            isCapturingToFile = false
            publishError("無法建立錄音檔:\(error.localizedDescription)")
        }
    }

    private func finishCaptureAndProcess() {
        guard isCapturingToFile, let file = audioFile else {
            publishError("沒有進行中的錄音,請重新按麥克風開始。")
            return
        }
        isCapturingToFile = false
        let url = file.url
        audioFile = nil
        KeyboardBridge.setString("processing", for: .status)

        guard let data = try? Data(contentsOf: url) else {
            publishError("錄音檔讀取失敗,請再試一次。")
            return
        }
        try? FileManager.default.removeItem(at: url)

        let modeId = KeyboardBridge.string(for: .mode) ?? "polish"
        let mode = Prompts.mode(byId: modeId)
        let settings = AppSettings()
        let system = Prompts.buildSystem(mode: mode, outputLang: settings.outputLang)
        let apiKey = settings.geminiKey
        let model = settings.model

        Task {
            do {
                let text = try await GeminiClient.transcribeAndPolish(
                    apiKey: apiKey,
                    model: model,
                    system: system,
                    audioData: data,
                    mime: "audio/mp4"
                )
                await MainActor.run {
                    KeyboardBridge.setString(text, for: .result)
                    KeyboardBridge.setString("idle", for: .status)
                    KeyboardBridge.post(.resultReady)
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run { self.publishError(message) }
            }
        }
    }

    private func publishError(_ message: String) {
        KeyboardBridge.setString(message, for: .error)
        KeyboardBridge.setString("idle", for: .status)
        KeyboardBridge.post(.resultError)
        lastError = message
    }
}
