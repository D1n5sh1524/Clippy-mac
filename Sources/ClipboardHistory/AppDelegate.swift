import AppKit

/// AppDelegate provides AppKit integration for the SwiftUI app lifecycle.
/// Handles application lifecycle events and coordinates core services.
///
/// On launch, initializes all core services:
/// - HistoryStore (persistence layer)
/// - ClipboardMonitor (pasteboard polling)
/// - ShortcutListener (global hotkey)
/// - MenuBarController (status bar UI)
/// - PopupPanel (clipboard history overlay)
///
/// Wires the ShortcutListener trigger to toggle the PopupPanel visibility.
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Core Services

    /// The history store managing clipboard entries and persistence.
    private var historyStore: HistoryStore?

    /// The clipboard monitor polling NSPasteboard for changes.
    private var clipboardMonitor: ClipboardMonitor?

    /// The global shortcut listener (Cmd+Shift+V by default).
    private var shortcutListener: ShortcutListener?

    /// The menu bar controller managing the NSStatusItem.
    private var menuBarController: MenuBarController?

    /// The popup panel displaying clipboard history.
    private var popupPanel: PopupPanel?

    /// The paste engine for placing content and simulating Cmd+V.
    private var pasteEngine: PasteEngine?

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Initialize HistoryStore and load persisted entries
        let historyStore = HistoryStore()
        self.historyStore = historyStore

        Task {
            await historyStore.loadWithRecovery()
        }

        // 2. Initialize ClipboardMonitor and start polling
        let clipboardMonitor = ClipboardMonitor(historyStore: historyStore)
        self.clipboardMonitor = clipboardMonitor

        Task {
            await clipboardMonitor.startMonitoring()
        }

        // 3. Initialize ShortcutListener and register the default shortcut
        let shortcutListener = ShortcutListener(shortcut: .default)
        self.shortcutListener = shortcutListener

        do {
            try shortcutListener.register(shortcut: .default)
        } catch {
            // Registration failure is handled by ShortcutListener's conflict notification
            print("Initial shortcut registration failed: \(error.localizedDescription)")
        }

        // 4. Initialize MenuBarController
        let menuBarController = MenuBarController()
        self.menuBarController = menuBarController
        menuBarController.setup()

        // 5. Initialize PopupPanel
        let popupPanel = PopupPanel()
        self.popupPanel = popupPanel

        // Configure the popup's view model with the history store
        popupPanel.viewModel.configure(historyStore: historyStore)

        // 6. Initialize PasteEngine
        let pasteEngine = PasteEngine()
        self.pasteEngine = pasteEngine

        // 7. Wire PopupPanel's onPaste callback
        popupPanel.onPaste = { [weak self] entry in
            guard let self = self else { return }
            let targetApp = popupPanel.previousApp
            popupPanel.dismiss()
            self.pasteEngine?.paste(entry: entry, targetApp: targetApp)

            // Move pasted entry to top
            Task {
                await historyStore.moveToTop(id: entry.id)
            }
        }

        // 8. Wire ShortcutListener toggle behavior (Req 3.3):
        //    If panel is visible, dismiss it; if hidden, show it near cursor.
        shortcutListener.onTrigger = { [weak self] in
            guard let self = self, let panel = self.popupPanel else { return }

            if panel.isVisible {
                panel.dismiss()
            } else {
                panel.showNearCursor()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stop clipboard monitoring
        if let monitor = clipboardMonitor {
            Task {
                await monitor.stopMonitoring()
            }
        }

        // Unregister global shortcut
        shortcutListener?.unregister()

        // Persist all entries immediately with a 2-second timeout (Req 6.4).
        // Uses a semaphore to block the termination handler until persistence completes
        // or the timeout elapses, ensuring we don't hang the quit process.
        guard let store = historyStore else { return }

        let semaphore = DispatchSemaphore(value: 0)

        Task {
            await store.persistImmediately()
            semaphore.signal()
        }

        // Wait up to 2 seconds for persistence to complete.
        // If it times out, the previously persisted state remains intact (Req 6.5).
        _ = semaphore.wait(timeout: .now() + 2.0)
    }
}
