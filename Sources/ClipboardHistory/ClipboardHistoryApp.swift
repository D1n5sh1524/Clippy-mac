import SwiftUI

/// The main entry point for the Clipboard History menu bar application.
/// Uses SwiftUI app lifecycle with an AppDelegate adapter for AppKit integration.
@main
struct ClipboardHistoryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
