import SwiftUI

@main
struct SaySomethingApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var history = HistoryStore()
    @StateObject private var session = SessionService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(history)
                .environmentObject(session)
                .onOpenURL { url in
                    // Entry point for the keyboard extension's session
                    // launch (saysomething://session) — see SessionService.
                    session.handleSessionURL(url)
                }
        }
    }
}
