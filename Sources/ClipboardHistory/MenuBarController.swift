import AppKit
import ServiceManagement

/// Manages the NSStatusItem (menu bar icon) and its dropdown menu.
///
/// Provides the user-facing menu bar interface with:
/// - Status bar icon (clipboard icon)
/// - Dropdown menu with Settings, Launch at Login toggle, and Quit
///
/// Satisfies Requirements 6.1 and 6.2.
@MainActor
class MenuBarController {
    // MARK: - Properties

    /// The menu bar status item.
    private var statusItem: NSStatusItem?

    /// The menu displayed when the status item is clicked.
    private var menu: NSMenu?

    /// Menu item for the Launch at Login toggle (kept for checkmark updates).
    private var launchAtLoginMenuItem: NSMenuItem?

    // MARK: - Setup

    /// Sets up the menu bar status item with an icon and dropdown menu.
    /// Creates the NSStatusItem, configures the icon, and builds the menu
    /// with Settings, Launch at Login toggle, and Quit items.
    func setup() {
        // Create the status item in the system status bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        // Configure the status bar icon
        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: "Clippy"
            )
        }

        // Build and attach the dropdown menu
        let menu = buildMenu()
        statusItem?.menu = menu
        self.menu = menu
    }

    // MARK: - Menu Construction

    /// Builds the dropdown menu with all required items.
    /// - Returns: A configured NSMenu with Settings, Launch at Login toggle, and Quit.
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Settings item
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(settingsAction(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at Login toggle item
        let launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLoginAction(_:)),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchAtLoginItem)
        self.launchAtLoginMenuItem = launchAtLoginItem

        menu.addItem(NSMenuItem.separator())

        // Quit item
        let quitItem = NSMenuItem(
            title: "Quit Clippy",
            action: #selector(quitAction(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Menu Actions

    /// Opens the application's Settings window.
    @objc private func settingsAction(_ sender: NSMenuItem) {
        openSettings()
    }

    /// Toggles the Launch at Login preference.
    @objc private func toggleLaunchAtLoginAction(_ sender: NSMenuItem) {
        toggleLaunchAtLogin()
    }

    /// Quits the application.
    @objc private func quitAction(_ sender: NSMenuItem) {
        quit()
    }

    // MARK: - Public Actions

    /// Opens the application Settings window.
    /// Uses NSApp to show the settings/preferences window.
    func openSettings() {
        // Show the SwiftUI Settings scene
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        // Open the Settings window (SwiftUI Settings scene)
        if #available(macOS 13.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    /// Toggles the Launch at Login setting using SMAppService (macOS 13+).
    /// Updates the menu item checkmark to reflect the current state.
    func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if service.status == .enabled {
                    // Currently enabled — unregister
                    try service.unregister()
                } else {
                    // Currently disabled or requires approval — register
                    try service.register()
                }
            } catch {
                // Registration/unregistration failed — log but don't crash
                print("Failed to toggle Launch at Login: \(error.localizedDescription)")
            }

            // Update checkmark state
            launchAtLoginMenuItem?.state = isLaunchAtLoginEnabled() ? .on : .off
        }
    }

    /// Quits the application.
    func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Launch at Login State

    /// Checks whether the app is currently registered as a login item.
    /// - Returns: `true` if the app is registered to launch at login, `false` otherwise.
    private func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
}
