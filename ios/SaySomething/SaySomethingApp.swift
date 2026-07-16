import SwiftUI

@main
struct SaySomethingApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var history = HistoryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(history)
        }
    }
}
