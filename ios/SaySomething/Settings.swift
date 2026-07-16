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

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let model = "model"
        static let outputLang = "output_lang"
        static let modeId = "mode"
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

    init() {
        geminiKey = KeychainStore.load()
        model = defaults.string(forKey: Keys.model) ?? "gemini-2.5-flash"
        outputLang = defaults.string(forKey: Keys.outputLang) ?? "same"
        modeId = defaults.string(forKey: Keys.modeId) ?? "polish"
    }

    var currentMode: Mode {
        Prompts.mode(byId: modeId)
    }
}
