import AppKit

/// AppDelegate provides AppKit integration for the SwiftUI app lifecycle.
/// Handles application lifecycle events and coordinates core services.
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Core services will be initialized here in subsequent tasks
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Persistence will be triggered here in subsequent tasks
    }
}
