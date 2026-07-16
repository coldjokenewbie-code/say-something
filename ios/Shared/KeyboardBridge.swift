import Foundation

/// Cross-process bridge between the main App (which owns the background
/// recording session) and the SaySomethingKeyboard extension (which is the
/// remote control + insertion point). This file is a member of BOTH
/// targets — do not duplicate it, edit here only.
///
/// Signal channel: Darwin notifications (CFNotificationCenter), which work
/// across processes even without App Group entitlements.
/// Data channel: dual-written to BOTH App Group shared UserDefaults and a
/// named UIPasteboard, each value timestamped; reads take whichever side is
/// newer. See `SharedStore` for why a single-channel "probe and pick one"
/// approach isn't reliable under free Personal Team signing.
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

/// Reads/writes the shared data channel.
///
/// Originally this gated on a same-process "write a sentinel value into the
/// App Group UserDefaults, read it back" probe and used the App Group
/// exclusively if that round-tripped. That probe can **false-positive**
/// under free Personal Team signing: `UserDefaults(suiteName:)` silently
/// falls back to a private, per-process defaults domain when the App Group
/// entitlement isn't actually provisioned, so each process's own
/// write-then-read-back of its own value always succeeds even though the
/// two processes are never actually sharing a container. A same-process
/// self-test cannot detect a cross-process failure.
///
/// Fix: dual-write every value to BOTH the App Group UserDefaults and a
/// named `UIPasteboard` (which is genuinely cross-process even without any
/// entitlement) tagged with a timestamp, and on read take whichever channel
/// has the newer value. Whichever channel is actually broken (writes to it
/// simply never show up on the other side) loses every comparison, so it's
/// self-correcting at read time instead of relying on a probe that can lie.
final class SharedStore {
    static let shared = SharedStore()

    private let pasteboardName = "com.saysomething.app.pasteboard"

    private init() {}

    private var appGroupDefaults: UserDefaults? {
        UserDefaults(suiteName: KeyboardBridge.appGroupID)
    }

    func setString(_ value: String, for key: KeyboardBridge.Key) {
        let ts = Date().timeIntervalSince1970
        writeAppGroup(value: value, ts: ts, key: key)
        writePasteboard(value: value, ts: ts, key: key)
    }

    func string(for key: KeyboardBridge.Key) -> String? {
        let fromAppGroup = readAppGroup(key: key)
        let fromPasteboard = readPasteboard(key: key)
        switch (fromAppGroup, fromPasteboard) {
        case let (a?, b?):
            return a.ts >= b.ts ? a.value : b.value
        case let (a?, nil):
            return a.value
        case let (nil, b?):
            return b.value
        case (nil, nil):
            return nil
        }
    }

    // MARK: - App Group channel

    private func writeAppGroup(value: String, ts: TimeInterval, key: KeyboardBridge.Key) {
        guard let defaults = appGroupDefaults else { return }
        defaults.set(value, forKey: key.rawValue)
        defaults.set(ts, forKey: key.rawValue + ".ts")
    }

    private func readAppGroup(key: KeyboardBridge.Key) -> (value: String, ts: TimeInterval)? {
        guard let defaults = appGroupDefaults,
              let value = defaults.string(forKey: key.rawValue) else { return nil }
        let ts = defaults.double(forKey: key.rawValue + ".ts")
        return (value, ts)
    }

    // MARK: - Named UIPasteboard channel (JSON blob: key -> {value, ts})

    private func readPasteboard(key: KeyboardBridge.Key) -> (value: String, ts: TimeInterval)? {
        #if canImport(UIKit)
        guard let pb = UIPasteboardCompat.named(pasteboardName),
              let data = pb.data(),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]],
              let entry = root[key.rawValue],
              let value = entry["value"] as? String
        else { return nil }
        let ts = entry["ts"] as? TimeInterval ?? 0
        return (value, ts)
        #else
        return nil
        #endif
    }

    private func writePasteboard(value: String, ts: TimeInterval, key: KeyboardBridge.Key) {
        #if canImport(UIKit)
        guard let pb = UIPasteboardCompat.named(pasteboardName) else { return }
        var root: [String: [String: Any]] = [:]
        if let data = pb.data(),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            root = existing
        }
        root[key.rawValue] = ["value": value, "ts": ts]
        guard let newData = try? JSONSerialization.data(withJSONObject: root) else { return }
        pb.setData(newData)
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
