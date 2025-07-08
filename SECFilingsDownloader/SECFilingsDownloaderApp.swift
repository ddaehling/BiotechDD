import SwiftUI

@main
struct SECFilingsDownloaderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 700, idealWidth: 800, minHeight: 750, idealHeight: 850)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .commands {
            // Remove unwanted menu items
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .undoRedo) { }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let resetForm = Notification.Name("resetForm")
    static let startDownload = Notification.Name("startDownload")
}

// MARK: - App Configuration

extension NSApplication {
    static func configureApp() {
        // Set activation policy
        NSApp.setActivationPolicy(.regular)
        
        // Bring app to front
        NSApp.activate(ignoringOtherApps: true)
    }
}
