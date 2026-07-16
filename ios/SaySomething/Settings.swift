import Foundation
import Combine

/// App settings — ported from android Settings.kt. The API key lives in the
/// Keychain (KeychainStore); model / output language / mode live in
/// UserDefaults, matching the Android SharedPreferences split.
final class AppSettings: ObservableObject {
    static let models = ["gemini-2.5-flash", "gemini-2.5-pro"]

    /// Pairs of (stored value, display label) — same as Settings.kt LANGS.
    static let langs: [(value: String, label: String)] = [
        ("same", "跟隨原文(中英夾雜保留)"),
        ("繁體中文", "繁體中文"),
        ("English", "English"),
        ("日本語", "日本語"),
    ]

    /// Whisper transcription language codes — passed straight into
    /// whisper_full_params.language ("auto" maps to nil + detect_language).
    static let whisperLanguages: [(value: String, label: String)] = [
        ("auto", "自動偵測"),
        ("zh", "中文"),
        ("en", "English"),
        ("ja", "日本語"),
        ("ko", "한국어"),
    ]

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let model = "model"
        static let outputLang = "output_lang"
        static let modeId = "mode"
        static let transcriptionMode = "transcription_mode"
        static let whisperLanguage = "whisper_language"
        static let whisperModelId = "whisper_model_id"
    }

    @Published var geminiKey: String {
        didSet { KeychainStore.save(geminiKey) }
    }

    @Published var model: String {
        didSet { defaults.set(model, forKey: Keys.model) }
    }

    @Published var outputLang: String {
        didSet { defaults.set(outputLang, forKey: Keys.outputLang) }
    }

    @Published var modeId: String {
        didSet { defaults.set(modeId, forKey: Keys.modeId) }
    }

    /// "local" (預設,聲音不出手機,whisper.cpp) or "cloud" (送音檔給 Gemini,品質最好).
    @Published var transcriptionMode: String {
        didSet { defaults.set(transcriptionMode, forKey: Keys.transcriptionMode) }
    }

    @Published var whisperLanguage: String {
        didSet { defaults.set(whisperLanguage, forKey: Keys.whisperLanguage) }
    }

    @Published var whisperModelId: String {
        didSet { defaults.set(whisperModelId, forKey: Keys.whisperModelId) }
    }

    init() {
        geminiKey = KeychainStore.load()
        model = defaults.string(forKey: Keys.model) ?? "gemini-2.5-flash"
        outputLang = defaults.string(forKey: Keys.outputLang) ?? "same"
        modeId = defaults.string(forKey: Keys.modeId) ?? "polish"
        transcriptionMode = defaults.string(forKey: Keys.transcriptionMode) ?? "local"
        whisperLanguage = defaults.string(forKey: Keys.whisperLanguage) ?? "auto"
        whisperModelId = defaults.string(forKey: Keys.whisperModelId) ?? "small-q5_1"
    }

    var currentMode: Mode {
        Prompts.mode(byId: modeId)
    }
}
