import Carbon
import Foundation
import UserNotifications

// Global signature used by the Carbon hot key handler to avoid touching @MainActor types
private let HOT_KEY_SIGNATURE: FourCharCode = {
    let c: UInt32 = UInt32(UnicodeScalar("C").value) << 24
        | UInt32(UnicodeScalar("L").value) << 16
        | UInt32(UnicodeScalar("I").value) << 8
        | UInt32(UnicodeScalar("P").value)
    return FourCharCode(c)
}()

/// Error types for shortcut registration failures.
enum ShortcutError: Error, LocalizedError {
    case registrationFailed(KeyboardShortcut)
    case invalidShortcut(KeyboardShortcut)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let shortcut):
            return "Failed to register global hotkey (keyCode: \(shortcut.keyCode), modifiers: \(shortcut.modifiers)). The shortcut may be in use by another application."
        case .invalidShortcut(let shortcut):
            return "Invalid shortcut (keyCode: \(shortcut.keyCode), modifiers: \(shortcut.modifiers)). Must have at least one modifier key plus a non-modifier key."
        }
    }
}

/// Manages global keyboard shortcut registration using the Carbon `RegisterEventHotKey` API.
///
/// This class registers a system-wide hotkey that triggers a callback when pressed,
/// regardless of which application is focused. It uses the Carbon event model because
/// it is the only public macOS API that intercepts global shortcuts without requiring
/// Accessibility permission for registration.
///
/// Must be used on the main thread since Carbon event APIs are main-thread bound.
@MainActor
class ShortcutListener {
    // MARK: - Static Reference

    /// Static reference so the C callback function can reach this instance.
    /// Carbon hot key event handlers use C function pointers that cannot capture context.
    static var shared: ShortcutListener?

    // MARK: - Properties

    /// Reference to the currently registered Carbon hot key. `nil` when no hotkey is active.
    private var hotKeyRef: EventHotKeyRef?

    /// The currently active keyboard shortcut.
    private(set) var currentShortcut: KeyboardShortcut

    /// Callback closure invoked when the registered hotkey is pressed.
    var onTrigger: (() -> Void)?

    /// Reference to the installed Carbon event handler.
    private var eventHandlerRef: EventHandlerRef?

    /// Signature used to identify this application's hot keys (FourCharCode 'CLIP').
    static let hotKeySignature: FourCharCode = HOT_KEY_SIGNATURE

    /// Hot key ID counter for unique identification.
    private static let hotKeyID: UInt32 = 1

    // MARK: - Initialization

    /// Creates a new ShortcutListener with the specified shortcut.
    /// - Parameter shortcut: The keyboard shortcut to register. Defaults to Cmd+Shift+V.
    init(shortcut: KeyboardShortcut = .default) {
        self.currentShortcut = shortcut
        Self.shared = self
        installEventHandler()
    }

    deinit {
        // deinit is nonisolated; dispatch cleanup to the main actor to satisfy isolation
        Task { @MainActor in
            self.unregister()
            self.removeEventHandler()
            if Self.shared === self {
                Self.shared = nil
            }
        }
    }

    // MARK: - Public Methods

    /// Registers the global hotkey with the Carbon event system.
    ///
    /// Calls `RegisterEventHotKey` with the shortcut's key code and modifiers.
    /// On success, stores the `EventHotKeyRef` for later unregistration.
    /// On failure (e.g., another app owns the shortcut), throws `ShortcutError.registrationFailed`.
    ///
    /// - Parameter shortcut: The keyboard shortcut to register.
    /// - Throws: `ShortcutError.registrationFailed` if `RegisterEventHotKey` returns an error.
    func register(shortcut: KeyboardShortcut) throws {
        // Unregister any existing hotkey first
        unregister()

        let hotKeyID = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: Self.hotKeyID
        )

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, ref != nil else {
            throw ShortcutError.registrationFailed(shortcut)
        }

        hotKeyRef = ref
        currentShortcut = shortcut
    }

    /// Unregisters the currently registered global hotkey.
    ///
    /// Calls `UnregisterEventHotKey` with the stored `EventHotKeyRef`.
    /// Safe to call even if no hotkey is currently registered.
    func unregister() {
        guard let ref = hotKeyRef else { return }
        UnregisterEventHotKey(ref)
        hotKeyRef = nil
    }

    /// Updates the global shortcut to a new key combination.
    ///
    /// Validates the new shortcut, unregisters the old one, and attempts to register
    /// the new one. If registration fails, reverts to the previous shortcut and
    /// displays a conflict notification.
    ///
    /// - Parameter newShortcut: The new keyboard shortcut to use.
    /// - Throws: `ShortcutError.invalidShortcut` if validation fails,
    ///           `ShortcutError.registrationFailed` if the new shortcut conflicts.
    func updateShortcut(_ newShortcut: KeyboardShortcut) throws {
        // Validate the new shortcut
        guard validate(newShortcut) else {
            throw ShortcutError.invalidShortcut(newShortcut)
        }

        // Store previous shortcut for revert on failure
        let previousShortcut = currentShortcut

        // Unregister old shortcut
        unregister()

        // Attempt to register new shortcut
        do {
            try register(shortcut: newShortcut)
        } catch {
            // Registration failed — revert to previous shortcut (Req 3.6)
            displayConflictNotification(for: newShortcut)

            // Re-register the previous shortcut
            do {
                try register(shortcut: previousShortcut)
            } catch {
                // If even the previous shortcut fails, we're in a bad state.
                // Display another notification but don't throw — best effort recovery.
                displayConflictNotification(for: previousShortcut)
            }

            throw ShortcutError.registrationFailed(newShortcut)
        }
    }

    /// Validates that a shortcut meets the requirements for a global hotkey.
    ///
    /// A valid shortcut must have:
    /// - At least one modifier key (Cmd, Option, Control, or Shift)
    /// - A non-modifier key (keyCode != 0)
    ///
    /// - Parameter shortcut: The keyboard shortcut to validate.
    /// - Returns: `true` if the shortcut is valid, `false` otherwise.
    func validate(_ shortcut: KeyboardShortcut) -> Bool {
        return shortcut.isValid
    }

    // MARK: - Private Methods

    /// Installs the Carbon event handler for hot key pressed events.
    ///
    /// Sets up a C function pointer callback that routes `kEventHotKeyPressed` events
    /// to the static `shared` instance's `onTrigger` closure.
    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        if status != noErr {
            // Event handler installation failed — log but don't crash.
            // The shortcut simply won't work until reinstalled.
            eventHandlerRef = nil
        }
    }

    /// Removes the installed Carbon event handler.
    private func removeEventHandler() {
        guard let handler = eventHandlerRef else { return }
        RemoveEventHandler(handler)
        eventHandlerRef = nil
    }

    /// Displays a user notification informing that a shortcut could not be registered
    /// due to a conflict with another application.
    ///
    /// Uses `UNUserNotificationCenter` to deliver the notification (Req 3.4, 3.6).
    ///
    /// - Parameter shortcut: The shortcut that failed to register.
    private func displayConflictNotification(for shortcut: KeyboardShortcut) {
        let content = UNMutableNotificationContent()
        content.title = "Shortcut Conflict"
        content.body = "The keyboard shortcut could not be registered. It may be in use by another application. Please choose a different shortcut."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "shortcut-conflict-\(UUID().uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                // Notification delivery failed — not critical, log and continue
                print("Failed to deliver shortcut conflict notification: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Carbon Event Handler (C Function Pointer)

/// Global C function that handles Carbon hot key events.
///
/// This function is called by the Carbon event system when a registered hot key is pressed.
/// It routes the event to `ShortcutListener.shared?.onTrigger()`.
///
/// - Parameters:
///   - nextHandler: The next event handler in the chain.
///   - event: The Carbon event reference.
///   - userData: User data pointer (unused, we use the static `shared` reference instead).
/// - Returns: `noErr` if the event was handled, or the result of calling the next handler.
private func hotKeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event = event else {
        return OSStatus(eventNotHandledErr)
    }

    // Verify this is a hot key pressed event
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        UInt32(kEventParamDirectObject),
        UInt32(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr else {
        return status
    }

    // Verify the hot key belongs to us
    guard hotKeyID.signature == HOT_KEY_SIGNATURE else {
        return OSStatus(eventNotHandledErr)
    }

    // Invoke the trigger callback on the main thread
    DispatchQueue.main.async {
        ShortcutListener.shared?.onTrigger?()
    }

    return noErr
}
