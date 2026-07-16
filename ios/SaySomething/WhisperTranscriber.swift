import Foundation
import AVFoundation

enum WhisperError: LocalizedError {
    case modelNotDownloaded
    case audioConversionFailed(String)
    case transcriptionFailed(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded:
            return "轉錄模型尚未下載,請到設定頁下載模型。"
        case .audioConversionFailed(let msg):
            return "錄音轉檔失敗:\(msg)"
        case .transcriptionFailed(let msg):
            return "本地轉錄失敗:\(msg)"
        case .emptyResult:
            return "沒有辨識出文字,請再試一次。"
        }
    }
}

/// Local speech-to-text via whisper.cpp (ios/Vendor/whisper.cpp), used when
/// AppSettings.transcriptionMode == "local" (PRD 階段 7): the recorded audio
/// never leaves the device, only the resulting plain text is later sent to
/// Gemini for polishing (see GeminiClient.polishText).
///
/// Memory strategy (C6): every call loads the whisper_context, runs
/// whisper_full once, and frees the context before returning — nothing is
/// kept resident between transcriptions. On an A11/3GB device that's the
/// difference between "briefly spikes during a capture" and "holds a
/// few-hundred-MB model in the background the whole session," which is what
/// the PRD explicitly calls out as the jetsam risk to avoid.
enum WhisperTranscriber {
    /// - Parameters:
    ///   - audioData: the recorded .m4a (AAC) bytes.
    ///   - modelPath: absolute path to a downloaded ggml model file (see ModelManager).
    ///   - language: "auto", or a whisper language code ("zh", "en", "ja", "ko", ...).
    static func transcribe(audioData: Data, modelPath: String, language: String) async throws -> String {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw WhisperError.modelNotDownloaded
        }
        let samples = try decodeToPCM16kMono(audioData: audioData)
        guard !samples.isEmpty else {
            throw WhisperError.audioConversionFailed("錄音內容是空的")
        }
        return try await Task.detached(priority: .userInitiated) {
            try runWhisper(samples: samples, modelPath: modelPath, language: language)
        }.value
    }

    // MARK: - AVAudioConverter: recorded .m4a → 16kHz mono Float32 (what whisper_full expects)

    private static func decodeToPCM16kMono(audioData: Data) throws -> [Float] {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-input-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        do {
            try audioData.write(to: tempURL)
        } catch {
            throw WhisperError.audioConversionFailed(error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let inputFile: AVAudioFile
        do {
            inputFile = try AVAudioFile(forReading: tempURL)
        } catch {
            throw WhisperError.audioConversionFailed(error.localizedDescription)
        }
        guard inputFile.length > 0 else {
            throw WhisperError.audioConversionFailed("錄音檔是空的")
        }

        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
        ) else {
            throw WhisperError.audioConversionFailed("無法建立目標音訊格式")
        }
        guard let converter = AVAudioConverter(from: inputFile.processingFormat, to: outFormat) else {
            throw WhisperError.audioConversionFailed("無法建立音訊轉換器")
        }

        let inFrameCount = AVAudioFrameCount(inputFile.length)
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inputFile.processingFormat, frameCapacity: inFrameCount) else {
            throw WhisperError.audioConversionFailed("無法配置錄音緩衝區")
        }
        do {
            try inputFile.read(into: inBuffer)
        } catch {
            throw WhisperError.audioConversionFailed(error.localizedDescription)
        }

        let ratio = outFormat.sampleRate / max(inputFile.processingFormat.sampleRate, 1)
        let outCapacity = AVAudioFrameCount(Double(inFrameCount) * ratio) + 4_096
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity) else {
            throw WhisperError.audioConversionFailed("無法配置轉換緩衝區")
        }

        var conversionError: NSError?
        var consumed = false
        let status = converter.convert(to: outBuffer, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inBuffer
        }
        guard status != .error else {
            throw WhisperError.audioConversionFailed(conversionError?.localizedDescription ?? "未知錯誤")
        }
        guard let channelData = outBuffer.floatChannelData else {
            throw WhisperError.audioConversionFailed("轉換結果是空的")
        }
        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(outBuffer.frameLength)))
    }

    // MARK: - whisper.cpp (runs on a background thread; blocking, CPU-only/NEON)

    /// Not `@Sendable`-checked strictly, but only ever invoked from inside
    /// `Task.detached` above with a value type (`[Float]`) capture — no
    /// shared mutable state crosses threads here.
    private static func runWhisper(samples: [Float], modelPath: String, language: String) throws -> String {
        var cparams = whisper_context_default_params()
        cparams.use_gpu = false // CPU-only build: no ggml-metal.m vendored (see ios/README.md).

        guard let ctx = modelPath.withCString({ whisper_init_from_file_with_params($0, cparams) }) else {
            throw WhisperError.transcriptionFailed("模型載入失敗,檔案可能已損毀,請到設定頁重新下載。")
        }
        // Load-per-use (C6): always freed before this function returns, on
        // every exit path including thrown errors.
        defer { whisper_free(ctx) }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.print_timestamps = false
        params.no_timestamps = true
        params.translate = false
        params.n_threads = Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount)))

        let langCode = (language.isEmpty || language == "auto") ? nil : language
        return try withOptionalCString(langCode) { langPtr in
            params.language = langPtr
            params.detect_language = (langPtr == nil)

            let result = samples.withUnsafeBufferPointer { buffer in
                whisper_full(ctx, params, buffer.baseAddress, Int32(buffer.count))
            }
            guard result == 0 else {
                throw WhisperError.transcriptionFailed("whisper 轉錄回傳錯誤碼 \(result)")
            }

            let segmentCount = whisper_full_n_segments(ctx)
            guard segmentCount > 0 else { throw WhisperError.emptyResult }

            var text = ""
            for i in 0..<segmentCount {
                if let cText = whisper_full_get_segment_text(ctx, i) {
                    text += String(cString: cText)
                }
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw WhisperError.emptyResult }
            return trimmed
        }
    }

    /// Keeps the C string backing `s` alive for the duration of `body`,
    /// passing `nil` straight through when there's no override — whisper.cpp
    /// treats a NULL `language` (with `detect_language = true`) as auto-detect.
    private static func withOptionalCString<T>(
        _ s: String?, _ body: (UnsafePointer<CChar>?) throws -> T
    ) rethrows -> T {
        guard let s else { return try body(nil) }
        return try s.withCString(body)
    }
}
