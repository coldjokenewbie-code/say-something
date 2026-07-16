import Foundation
import AVFoundation

enum RecorderError: LocalizedError {
    case permissionDenied
    case sessionSetupFailed(String)
    case recordingFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "沒有麥克風權限,請到「設定 > 隱私權與安全性 > 麥克風」開啟 Say Something 的權限。"
        case .sessionSetupFailed(let msg):
            return "無法啟用麥克風:\(msg)"
        case .recordingFailed(let msg):
            return "錄音失敗:\(msg)"
        }
    }
}

/// Wraps AVAudioSession + AVAudioRecorder, recording AAC in an .m4a container
/// (mirrors the Android MediaRecorder AAC output that Gemini accepts as
/// audio/mp4 inline data).
final class Recorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false

    private var recorder: AVAudioRecorder?
    private var currentURL: URL?

    func requestPermission(completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    private func permissionGranted() -> Bool {
        if #available(iOS 17.0, *) {
            return AVAudioApplication.shared.recordPermission == .granted
        } else {
            return AVAudioSession.sharedInstance().recordPermission == .granted
        }
    }

    func start(completion: @escaping (Result<Void, RecorderError>) -> Void) {
        guard !isRecording else { return }

        func begin() {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try session.setActive(true)
            } catch {
                completion(.failure(.sessionSetupFailed(error.localizedDescription)))
                return
            }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("say-something-\(UUID().uuidString)")
                .appendingPathExtension("m4a")

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]

            do {
                let recorder = try AVAudioRecorder(url: url, settings: settings)
                recorder.delegate = self
                recorder.isMeteringEnabled = false
                guard recorder.record() else {
                    completion(.failure(.recordingFailed("無法開始錄音")))
                    return
                }
                self.recorder = recorder
                self.currentURL = url
                self.isRecording = true
                completion(.success(()))
            } catch {
                completion(.failure(.recordingFailed(error.localizedDescription)))
            }
        }

        if permissionGranted() {
            begin()
        } else {
            requestPermission { granted in
                if granted {
                    begin()
                } else {
                    completion(.failure(.permissionDenied))
                }
            }
        }
    }

    /// Stops recording and returns the recorded file's contents plus MIME type.
    func stop() -> (data: Data, mime: String)? {
        guard isRecording, let recorder = recorder, let url = currentURL else { return nil }
        recorder.stop()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        self.recorder = nil
        self.currentURL = nil

        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return (data, "audio/mp4")
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        isRecording = false
        recorder = nil
        if let url = currentURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
