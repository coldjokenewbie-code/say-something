import Foundation

/// Cross-process bridge between the main App (which owns the background
/// recording session) and the SaySomethingKeyboard extension (which is the
/// remote control + insertion point). This file is a member of BOTH
/// targets — do not duplicate it, edit here only.
///
/// Signal channel: Darwin notifications (CFNotificationCenter), which work
/// across processes even without App Group entitlements.
/// Data channel: App Group shared UserDefaults when available; falls back
/// to a named UIPasteboard (JSON blob) when the App Group container is not
/// usable (e.g. free Personal Team signing without a verified App Group
/// entitlement).
enum KeyboardBridge {
    /// App Group identifier shared by both targets' entitlements.
    static let appGroupID = "group.com.saysomething.app"

    /// URL scheme the keyboard uses to jump into the main App to start a session.
    static let sessionURLScheme = "saysomething"
    static let sessionURL = URL(string: "saysomething://session")!

    // MARK: - Darwin notification names (signal channel, no payload)

    enum Signal: String {
        /// Keyboard → App: start capturing audio into a file.
        case recordStart = "com.saysomething.record.start"
        /// Keyboard → App: stop capturing, transcribe + polish, publish result.
        case recordStop = "com.saysomething.record.stop"
        /// App → Keyboard: result is ready in the shared store.
        case resultReady = "com.saysomething.result.ready"
        /// App → Keyboard: something went wrong; error message is in the shared store.
        case resultError = "com.saysomething.result.error"
        /// App → Keyboard: background keep-alive session is up (heartbeat also updated).
        case sessionStarted = "com.saysomething.session.started"

        var cfString: CFString { rawValue as CFString }
    }

    /// Posts a Darwin notification other processes can observe regardless of
    /// App Group availability.
    static func post(_ signal: Signal) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(signal.cfString),
            nil, nil, true
        )
    }

    /// Registers `handler` to run whenever `signal` fires. Returns an opaque
    /// observer token; callers should keep it alive and call `removeObserver`
    /// in deinit. Uses a C callback trampoline via a static registry because
    /// CFNotificationCenter callbacks are plain C function pointers.
    static func addObserver(_ signal: Signal, handler: @escaping () -> Void) {
        DarwinObserverRegistry.shared.add(signal: signal, handler: handler)
    }

    static func removeObserver(_ signal: Signal) {
        DarwinObserverRegistry.shared.remove(signal: signal)
    }

    // MARK: - Data channel

    /// Keys used in both the App Group UserDefaults suite and the pasteboard
    /// JSON fallback blob.
    enum Key: String {
        case mode
        case status
        case result
        case error
        case heartbeat
    }

    /// Session is considered alive if the App updated the heartbeat within
    /// this many seconds. The keyboard uses this to decide whether it needs
    /// to prompt the user to (re)launch the main App.
    static let heartbeatFreshWindow: TimeInterval = 20

    static func setString(_ value: String, for key: Key) {
        SharedStore.shared.setString(value, for: key)
    }

    static func string(for key: Key) -> String? {
        SharedStore.shared.string(for: key)
    }

    static func markHeartbeat() {
        SharedStore.shared.setString(String(Date().timeIntervalSince1970), for: .heartbeat)
    }

    static func isSessionAlive() -> Bool {
        guard let raw = string(for: .heartbeat), let ts = TimeInterval(raw) else { return false }
        return Date().timeIntervalSince1970 - ts < heartbeatFreshWindow
    }
}

/// Reads/writes the shared data channel. Tries the App Group container
/// first; if it's not usable (returns nil, which happens when the App
/// Group entitlement isn't actually provisioned — e.g. an unverified free
/// Personal Team signing), falls back to a named UIPasteboard holding a
/// small JSON dictionary. Detection happens once per process and is
/// cached.
final class SharedStore {
    static let shared = SharedStore()

    private let pasteboardName = "com.saysomething.app.pasteboard"
    private var useAppGroupCache: Bool?

    private init() {}

    private var appGroupDefaults: UserDefaults? {
        UserDefaults(suiteName: KeyboardBridge.appGroupID)
    }

    /// Runtime probe: write+read a sentinel value. If it round-trips, the
    /// App Group container is usable.
    private func appGroupWorks() -> Bool {
        if let cached = useAppGroupCache { return cached }
        let works: Bool
        if let defaults = appGroupDefaults {
            let probeKey = "__saysomething_probe__"
            let probeValue = UUID().uuidString
            defaults.set(probeValue, forKey: probeKey)
            works = defaults.string(forKey: probeKey) == probeValue
            defaults.removeObject(forKey: probeKey)
        } else {
            works = false
        }
        useAppGroupCache = works
        return works
    }

    func setString(_ value: String, for key: KeyboardBridge.Key) {
        if appGroupWorks() {
            appGroupDefaults?.set(value, forKey: key.rawValue)
        } else {
            var blob = readPasteboardBlob()
            blob[key.rawValue] = value
            writePasteboardBlob(blob)
        }
    }

    func string(for key: KeyboardBridge.Key) -> String? {
        if appGroupWorks() {
            return appGroupDefaults?.string(forKey: key.rawValue)
        } else {
            return readPasteboardBlob()[key.rawValue]
        }
    }

    // MARK: - Named UIPasteboard fallback (JSON blob of all keys)

    private func readPasteboardBlob() -> [String: String] {
        #if canImport(UIKit)
        guard let pb = UIPasteboardCompat.named(pasteboardName),
              let data = pb.data(),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return dict
        #else
        return [:]
        #endif
    }

    private func writePasteboardBlob(_ blob: [String: String]) {
        #if canImport(UIKit)
        guard let data = try? JSONSerialization.data(withJSONObject: blob) else { return }
        UIPasteboardCompat.named(pasteboardName)?.setData(data)
        #endif
    }
}

#if canImport(UIKit)
import UIKit

/// Thin wrapper so SharedStore doesn't need to sprinkle `UIPasteboard`
/// specifics inline; also keeps the fallback path in one obvious place.
enum UIPasteboardCompat {
    static func named(_ name: String) -> UIPasteboard? {
        UIPasteboard(name: UIPasteboard.Name(name), create: true)
    }
}

extension UIPasteboard {
    func data() -> Data? {
        self.data(forPasteboardType: "public.json")
    }

    func setData(_ data: Data) {
        self.setData(data, forPasteboardType: "public.json")
    }
}
#endif

/// Bridges CFNotificationCenter's C-function-pointer callback API to Swift
/// closures. CFNotificationCenter callbacks can't capture context directly,
/// so we keep a process-wide registry keyed by notification name and
/// dispatch from one static C-compatible trampoline.
private final class DarwinObserverRegistry {
    static let shared = DarwinObserverRegistry()

    private var handlers: [String: [() -> Void]] = [:]
    private let lock = NSLock()

    private init() {}

    func add(signal: KeyboardBridge.Signal, handler: @escaping () -> Void) {
        lock.lock()
        let alreadyObserving = handlers[signal.rawValue]?.isEmpty == false
        handlers[signal.rawValue, default: []].append(handler)
        lock.unlock()

        guard !alreadyObserving else { return }

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, _, name, _, _ in
                guard let name = name?.rawValue as String? else { return }
                DarwinObserverRegistry.shared.dispatch(name: name)
            },
            signal.cfString,
            nil,
            .deliverImmediately
        )
    }

    func remove(signal: KeyboardBridge.Signal) {
        lock.lock()
        handlers[signal.rawValue] = nil
        lock.unlock()
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveObserver(center, observer, CFNotificationName(signal.cfString), nil)
    }

    private func dispatch(name: String) {
        lock.lock()
        let callbacks = handlers[name] ?? []
        lock.unlock()
        DispatchQueue.main.async {
            for callback in callbacks { callback() }
        }
    }
}
