import SwiftUI

@main
struct QRFileTransferApp: App {
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .tint(settings.accent)
        }
    }
}