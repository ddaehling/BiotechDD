import SwiftUI
import os.log

@main
struct SECFilingsDownloaderApp: App {
    init() {
        // Suppress non-critical console warnings
        UserDefaults.standard.set(false, forKey: "_UIConstraintBasedLayoutLogUnsatisfiable")
        UserDefaults.standard.set(false, forKey: "__NSConstraintBasedLayoutLogUnsatisfiable")
        
        // Configure network logging
        UserDefaults.standard.set(false, forKey: "com.apple.network.http-debug")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 700, idealWidth: 800, minHeight: 750, idealHeight: 850)
                .onAppear {
                    NSApplication.configureApp()
                }
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

// MARK: - Custom Logger for Debugging

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier!
    
    static let network = Logger(subsystem: subsystem, category: "network")
    static let merge = Logger(subsystem: subsystem, category: "merge")
    static let pdf = Logger(subsystem: subsystem, category: "pdf")
}
