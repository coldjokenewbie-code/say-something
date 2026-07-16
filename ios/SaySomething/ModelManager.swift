import Foundation
import UIKit

/// One downloadable ggml whisper model. URLs point at the official
/// ggerganov/whisper.cpp Hugging Face repo (verified reachable via
/// `curl -I` — see coach.py evidence for C5).
struct WhisperModelInfo: Identifiable, Equatable {
    let id: String
    let displayName: String
    let note: String
    let filename: String
    let downloadURL: URL
    /// Reference download size in bytes (from the HF `Content-Length`
    /// response at the time C5 evidence was captured) — used only to render
    /// an estimated size before the first download; actual on-disk size is
    /// read from disk once downloaded.
    let referenceSizeBytes: Int64
}

/// Downloads, stores, and manages ggml whisper models under
/// Application Support/WhisperModels — never bundled into the App (PRD 階段
/// 7 / C5: "App 不打包模型"). Uses a background URLSession so a download
/// can survive the app being backgrounded.
final class ModelManager: NSObject, ObservableObject {
    static let shared = ModelManager()

    /// small-q5_1 is the default (中文堪用); base-q5_1 is the faster, lower
    /// quality-for-Chinese fallback. NOTE: the PRD/contract call these
    /// "small-q5_0"/"base-q5_0", but ggerganov/whisper.cpp's Hugging Face
    /// repo only publishes q5_1 (5-bit) and q8_0 quantizations for these
    /// sizes — q5_0 doesn't exist upstream (verified 404 via curl -I). q5_1
    /// is the correct nearest match to the PRD's "5-bit quantized" intent.
    static let models: [WhisperModelInfo] = [
        WhisperModelInfo(
            id: "small-q5_1",
            displayName: "Small (預設)",
            note: "中文堪用,較慢(~190MB)",
            filename: "ggml-small-q5_1.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin")!,
            referenceSizeBytes: 190_085_487
        ),
        WhisperModelInfo(
            id: "base-q5_1",
            displayName: "Base",
            note: "較快,中文較差(~60MB)",
            filename: "ggml-base-q5_1.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin")!,
            referenceSizeBytes: 59_707_625
        ),
    ]

    static func model(byId id: String) -> WhisperModelInfo? {
        models.first { $0.id == id }
    }

    /// modelId -> 0...1. Absent key means "not currently downloading."
    @Published private(set) var downloadProgress: [String: Double] = [:]
    @Published private(set) var downloadingModelIds: Set<String> = []
    @Published var lastError: String?

    /// Bumped on every completed download/delete so SwiftUI views that read
    /// `isDownloaded`/`fileSize` (plain FileManager calls, not @Published)
    /// know to re-render.
    @Published private(set) var storageRevision = 0

    private var session: URLSession!
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private var taskModelId: [Int: String] = [:]
    var backgroundCompletionHandler: (() -> Void)?

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "com.saysomething.app.modeldownload")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: - Storage

    var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("WhisperModels", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func localURL(for model: WhisperModelInfo) -> URL {
        modelsDirectory.appendingPathComponent(model.filename)
    }

    func isDownloaded(_ model: WhisperModelInfo) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: model).path)
    }

    func fileSizeBytes(for model: WhisperModelInfo) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: localURL(for: model).path) else {
            return nil
        }
        return attrs[.size] as? Int64
    }

    func delete(_ model: WhisperModelInfo) {
        cancelDownload(model)
        try? FileManager.default.removeItem(at: localURL(for: model))
        storageRevision += 1
    }

    // MARK: - Download

    func startDownload(_ model: WhisperModelInfo) {
        guard !downloadingModelIds.contains(model.id) else { return }
        downloadingModelIds.insert(model.id)
        downloadProgress[model.id] = 0
        let task = session.downloadTask(with: model.downloadURL)
        taskModelId[task.taskIdentifier] = model.id
        activeTasks[model.id] = task
        task.resume()
    }

    func cancelDownload(_ model: WhisperModelInfo) {
        activeTasks[model.id]?.cancel()
        activeTasks[model.id] = nil
        downloadingModelIds.remove(model.id)
        downloadProgress[model.id] = nil
    }
}

extension ModelManager: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard let modelId = taskModelId[downloadTask.taskIdentifier], totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { self.downloadProgress[modelId] = progress }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let modelId = taskModelId[downloadTask.taskIdentifier],
              let model = ModelManager.model(byId: modelId) else { return }
        let dest = localURL(for: model)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
        } catch {
            let message = "模型儲存失敗:\(error.localizedDescription)"
            DispatchQueue.main.async { self.lastError = message }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let modelId = taskModelId[task.taskIdentifier] else { return }
        DispatchQueue.main.async {
            self.downloadingModelIds.remove(modelId)
            self.downloadProgress[modelId] = nil
            self.taskModelId[task.taskIdentifier] = nil
            self.activeTasks[modelId] = nil
            self.storageRevision += 1
            if let error, (error as NSError).code != NSURLErrorCancelled {
                self.lastError = "模型下載失敗:\(error.localizedDescription)"
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}

/// Wires up the background URLSession completion callback iOS delivers to
/// the app delegate (not the SwiftUI App struct) when a model download
/// finishes while the app was suspended/terminated by the system.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        ModelManager.shared.backgroundCompletionHandler = completionHandler
    }
}
