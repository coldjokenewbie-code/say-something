import Foundation
import Combine

struct HistoryEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let text: String
    let modeLabel: String
    let date: Date
}

/// Stores recent transcription results in UserDefaults as JSON, capped at
/// 30 entries (oldest trimmed first) — mirrors the PRD "近 30 筆" requirement.
final class HistoryStore: ObservableObject {
    static let limit = 30
    private static let key = "history_entries"

    @Published private(set) var entries: [HistoryEntry] = []

    private let defaults = UserDefaults.standard

    init() {
        load()
    }

    func add(text: String, modeLabel: String) {
        var next = entries
        next.insert(HistoryEntry(text: text, modeLabel: modeLabel, date: Date()), at: 0)
        if next.count > Self.limit {
            next = Array(next.prefix(Self.limit))
        }
        entries = next
        persist()
    }

    func clear() {
        entries = []
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.key) else { return }
        if let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
