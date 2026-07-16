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
    private var heartbeatTimer: Timer?
    private var observersRegistered = false
    private var interruptionObserverRegistered = false

    /// `isCapturing`/`file` are written from Darwin-notification callbacks
    /// (main thread, via DarwinObserverRegistry) and read+written from the
    /// audio tap callback (an internal CoreAudio render thread) on every
    /// buffer. `captureLock` makes both fields move together atomically and
    /// — critically — is held for the full duration of each `file.write`,
    /// so `finishCaptureAndProcess` blocks until any in-flight write
    /// completes before it clears the file reference and reads the file
    /// back off disk. That's what guarantees the last buffer is flushed
    /// before the file is considered "done".
    private struct CaptureState {
        var isCapturing = false
        var file: AVAudioFile?
    }
    private let captureLock = NSLock()
    private var captureState = CaptureState()

    private override init() {
        super.init()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
        registerInterruptionObserverOnce()
        // engine.isRunning 必須連動檢查:中斷後 shouldResume 未給時 engine 已停但
        // isKeepAliveActive 仍 true,若只看 flag 會提早 return,session 永遠救不回來。
        guard !(isKeepAliveActive && engine.isRunning) else {
            markHeartbeatIfEngineRunning()
            return
        }
        isKeepAliveActive = false
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
            armHeartbeatTimer()
        } catch {
            lastError = "無法啟動錄音保活引擎:\(error.localizedDescription)"
        }
    }

    /// Heartbeat is tied directly to `engine.isRunning` rather than to our
    /// own `isKeepAliveActive` flag: the engine can stop out from under us
    /// (audio session interruption, route change, background suspension)
    /// without us necessarily hearing about it in time. If the engine isn't
    /// actually running, we must not keep telling the keyboard the session
    /// is alive.
    private func armHeartbeatTimer() {
        markHeartbeatIfEngineRunning()
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.markHeartbeatIfEngineRunning()
        }
    }

    private func markHeartbeatIfEngineRunning() {
        guard engine.isRunning else { return }
        KeyboardBridge.markHeartbeat()
    }

    // MARK: - Audio session interruptions (phone call, Siri, another app
    // grabbing the mic, etc.)

    private func registerInterruptionObserverOnce() {
        guard !interruptionObserverRegistered else { return }
        interruptionObserverRegistered = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            // The system has already yanked the engine out from under us.
            // Pausing on our side keeps our state consistent; letting the
            // heartbeat lapse (armHeartbeatTimer checks engine.isRunning)
            // is what lets the keyboard notice the session is down instead
            // of us having to push a signal we might not get a chance to send.
            engine.pause()
        case .ended:
            var shouldResume = false
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume)
            }
            guard shouldResume, isKeepAliveActive else { return }
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                try engine.start()
                armHeartbeatTimer()
            } catch {
                lastError = "背景保活中斷後恢復失敗:\(error.localizedDescription)"
            }
        @unknown default:
            break
        }
    }

    /// Runs on the audio render thread. Holds `captureLock` for the whole
    /// write so a concurrent `finishCaptureAndProcess` call on the main
    /// thread can't clear the file reference out from under an in-flight
    /// write (see `CaptureState` doc above).
    private func writeBufferIfCapturing(_ buffer: AVAudioPCMBuffer) {
        captureLock.lock()
        defer { captureLock.unlock() }
        guard captureState.isCapturing, let file = captureState.file else { return }
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
            let file = try AVAudioFile(forWriting: url, settings: settings)
            captureLock.lock()
            captureState = CaptureState(isCapturing: true, file: file)
            captureLock.unlock()
            KeyboardBridge.setString("recording", for: .status)
        } catch {
            captureLock.lock()
            captureState = CaptureState()
            captureLock.unlock()
            publishError("無法建立錄音檔:\(error.localizedDescription)")
        }
    }

    private func finishCaptureAndProcess() {
        // Flip `isCapturing` off and take the file reference under the same
        // lock the tap callback uses around `file.write` — this blocks
        // until any write already in flight on the audio thread finishes,
        // so the file on disk reflects every buffer up to this point
        // before we read it back below.
        captureLock.lock()
        let wasCapturing = captureState.isCapturing
        let file = captureState.file
        captureState = CaptureState()
        captureLock.unlock()

        guard wasCapturing, let file else {
            publishError("沒有進行中的錄音,請重新按麥克風開始。")
            return
        }
        let url = file.url
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
        let transcriptionMode = settings.transcriptionMode
        let whisperLanguage = settings.whisperLanguage
        let whisperModelId = settings.whisperModelId

        Task {
            do {
                let text = try await Self.transcribeAndPolish(
                    audioData: data,
                    transcriptionMode: transcriptionMode,
                    whisperLanguage: whisperLanguage,
                    whisperModelId: whisperModelId,
                    apiKey: apiKey,
                    model: model,
                    system: system,
                    onStatus: { status in KeyboardBridge.setString(status, for: .status) }
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

    /// Shared by the keyboard-driven Session flow above and ContentView's
    /// in-app mic button: dispatches on AppSettings.transcriptionMode.
    /// - local (預設): whisper.cpp transcribes on-device (audio never
    ///   leaves the phone), then only the resulting text goes to Gemini for
    ///   polishing via GeminiClient.polishText.
    /// - cloud: unchanged original path — raw audio goes to Gemini, which
    ///   transcribes and polishes in one call (C4: kept fully working).
    static func transcribeAndPolish(
        audioData: Data,
        transcriptionMode: String,
        whisperLanguage: String,
        whisperModelId: String,
        apiKey: String,
        model: String,
        system: String,
        onStatus: (String) -> Void
    ) async throws -> String {
        guard transcriptionMode == "local" else {
            return try await GeminiClient.transcribeAndPolish(
                apiKey: apiKey, model: model, system: system, audioData: audioData, mime: "audio/mp4"
            )
        }

        onStatus("transcribing")
        let whisperModel = ModelManager.model(byId: whisperModelId) ?? ModelManager.models[0]
        let modelPath = ModelManager.shared.localURL(for: whisperModel).path
        let transcript = try await WhisperTranscriber.transcribe(
            audioData: audioData, modelPath: modelPath, language: whisperLanguage
        )

        onStatus("polishing")
        return try await GeminiClient.polishText(apiKey: apiKey, model: model, system: system, text: transcript)
    }

    private func publishError(_ message: String) {
        KeyboardBridge.setString(message, for: .error)
        KeyboardBridge.setString("idle", for: .status)
        KeyboardBridge.post(.resultError)
        lastError = message
    }
}
