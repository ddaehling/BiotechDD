import SwiftUI

@main
struct SECFilingsDownloaderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 600, idealWidth: 700, minHeight: 700, idealHeight: 800)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            // Remove unwanted menu items
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .undoRedo) { }
            
            // Add custom menu items if needed
            CommandMenu("Actions") {
                Button("Reset Form") {
                    NotificationCenter.default.post(name: .resetForm, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])
                
                Divider()
                
                Button("Download") {
                    NotificationCenter.default.post(name: .startDownload, object: nil)
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
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
