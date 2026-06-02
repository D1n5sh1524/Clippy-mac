# Requirements Document

## Introduction

A macOS clipboard history manager application that monitors the system clipboard, maintains a history of copied items (text and images), and presents them in a popup overlay when a configurable keyboard shortcut is triggered. Users can browse their clipboard history and select any item to paste, similar to the Windows+V clipboard history feature on Windows.

## Glossary

- **Clipboard_Monitor**: The background service that observes the macOS system pasteboard for changes and records new clipboard entries.
- **History_Store**: The persistent storage layer that maintains an ordered list of clipboard entries.
- **Clipboard_Entry**: A single item in the clipboard history, containing the copied content (text or image), a timestamp, and metadata.
- **Popup_Panel**: The floating overlay window that displays the clipboard history when the keyboard shortcut is triggered.
- **Shortcut_Listener**: The component that registers and listens for the global keyboard shortcut to activate the Popup_Panel.
- **Paste_Engine**: The component responsible for inserting a selected Clipboard_Entry into the currently focused application.

## Requirements

### Requirement 1: Clipboard Monitoring

**User Story:** As a macOS user, I want the application to automatically detect when I copy text or images, so that my clipboard history is recorded without manual action.

#### Acceptance Criteria

1. WHEN new text content (plain text or rich text) is copied to the macOS system pasteboard, THE Clipboard_Monitor SHALL create a new Clipboard_Entry containing the text content and a timestamp recorded with at least one-second precision.
2. WHEN new image content is copied to the macOS system pasteboard, THE Clipboard_Monitor SHALL create a new Clipboard_Entry containing the image data and a timestamp recorded with at least one-second precision.
3. WHEN a new Clipboard_Entry is created, THE Clipboard_Monitor SHALL store it in the History_Store as the most recent entry.
4. THE Clipboard_Monitor SHALL poll the macOS system pasteboard at intervals no greater than 500 milliseconds to detect changes using the pasteboard change count.
5. WHEN the macOS system pasteboard content is byte-identical to the most recent Clipboard_Entry of the same content type, THE Clipboard_Monitor SHALL discard the duplicate and not create a new entry.
6. WHEN the macOS system pasteboard contains content that is neither text nor image (e.g., file references, proprietary types), THE Clipboard_Monitor SHALL ignore the content and not create a new Clipboard_Entry.
7. IF the Clipboard_Monitor fails to access the macOS system pasteboard during a poll cycle, THEN THE Clipboard_Monitor SHALL skip that cycle and retry on the next polling interval without interrupting monitoring.
8. THE Clipboard_Monitor SHALL limit stored text entries to a maximum of 1,000,000 characters and image entries to a maximum of 10 MB per entry, discarding content that exceeds these limits.

### Requirement 2: History Storage and Management

**User Story:** As a macOS user, I want my clipboard history to be persisted and manageable, so that I can access previously copied items across app restarts and keep the list clean.

#### Acceptance Criteria

1. THE History_Store SHALL persist clipboard entries to disk within 1 second of any addition or deletion, ensuring data survives application crashes or force-quit.
2. THE History_Store SHALL maintain a maximum of 50 clipboard entries.
3. WHEN the History_Store reaches the maximum capacity of 50 entries, THE History_Store SHALL remove the oldest entry before adding a new one.
4. WHEN a user requests deletion of a specific Clipboard_Entry, THE History_Store SHALL remove that entry permanently and update the persisted storage.
5. WHEN a user requests clearing all history, THE History_Store SHALL prompt the user for confirmation before removing all stored Clipboard_Entry items permanently.
6. THE History_Store SHALL order clipboard entries from most recent to oldest based on each entry's creation timestamp.
7. IF the persisted storage file is corrupted or unreadable at application launch, THEN THE History_Store SHALL start with an empty history and display a notification indicating that previous history could not be recovered.

### Requirement 3: Keyboard Shortcut Activation

**User Story:** As a macOS user, I want to press a keyboard shortcut to open my clipboard history, so that I can quickly access previously copied items without navigating menus.

#### Acceptance Criteria

1. THE Shortcut_Listener SHALL register a global keyboard shortcut (default: Cmd+Shift+V) that is active across all applications.
2. WHEN the registered keyboard shortcut is pressed, THE Shortcut_Listener SHALL activate the Popup_Panel within 200 milliseconds.
3. WHILE the Popup_Panel is visible, WHEN the registered keyboard shortcut is pressed, THE Shortcut_Listener SHALL dismiss the Popup_Panel.
4. IF the global keyboard shortcut cannot be registered due to a conflict, THEN THE Shortcut_Listener SHALL display a notification indicating the conflicting shortcut and present an input prompt for the user to assign an alternative shortcut.
5. WHERE the user configures a custom keyboard shortcut, THE Shortcut_Listener SHALL validate that the shortcut contains at least one modifier key (Cmd, Option, Control, or Shift) combined with a non-modifier key, and SHALL use the valid custom shortcut instead of the default.
6. IF the user-configured custom keyboard shortcut conflicts with another application, THEN THE Shortcut_Listener SHALL display a notification indicating the conflict and revert to the previously registered shortcut until the user provides a non-conflicting alternative.

### Requirement 4: Popup Panel Display

**User Story:** As a macOS user, I want a clean popup that shows my clipboard history with previews, so that I can quickly identify and select the item I want to paste.

#### Acceptance Criteria

1. WHEN activated, THE Popup_Panel SHALL display a vertically scrollable list of clipboard entries ordered from most recent to oldest.
2. THE Popup_Panel SHALL display text entries as a single-line preview with newline characters replaced by spaces, truncated to 80 characters with an ellipsis indicator if the text exceeds 80 characters.
3. THE Popup_Panel SHALL display image entries as thumbnail previews scaled to fit within 64x64 pixels while preserving the original aspect ratio.
4. THE Popup_Panel SHALL display the relative timestamp for each Clipboard_Entry using the largest applicable unit (e.g., "3 seconds ago", "2 minutes ago", "1 hour ago", "5 days ago").
5. IF the cursor position is within the bounds of a visible screen, THEN THE Popup_Panel SHALL appear near the current cursor position, otherwise THE Popup_Panel SHALL appear centered on the active screen.
6. WHEN the Popup_Panel loses focus due to another window or application receiving focus, THE Popup_Panel SHALL dismiss itself.
7. WHEN the Escape key is pressed while the Popup_Panel is visible, THE Popup_Panel SHALL dismiss itself.
8. THE Popup_Panel SHALL indicate the content type (text or image) for each Clipboard_Entry using a visual icon.
9. IF the History_Store contains no entries when the Popup_Panel is activated, THEN THE Popup_Panel SHALL display an empty-state message indicating that no clipboard history is available.

### Requirement 5: Item Selection and Pasting

**User Story:** As a macOS user, I want to select an item from my clipboard history and have it pasted into the active application, so that I can reuse previously copied content efficiently.

#### Acceptance Criteria

1. WHEN the user clicks on a Clipboard_Entry in the Popup_Panel, THE Paste_Engine SHALL place the selected entry's content onto the macOS system pasteboard and then simulate a Cmd+V keystroke in the application that held focus immediately before the Popup_Panel was activated.
2. WHEN a Clipboard_Entry is selected, THE Popup_Panel SHALL dismiss itself and return focus to the previously focused application within 200 milliseconds, before the Cmd+V keystroke is simulated.
3. WHEN a Clipboard_Entry is pasted, THE History_Store SHALL move that entry to the most recent position in the history.
4. WHILE the Popup_Panel is visible, THE Popup_Panel SHALL allow keyboard navigation using the Up and Down arrow keys to move the highlight between entries, stopping at the first and last entries without wrapping.
5. WHEN the Enter key is pressed while a Clipboard_Entry is highlighted, THE Paste_Engine SHALL paste that entry using the same mechanism as a click selection (criteria 1-3).
6. IF the Enter key is pressed while no Clipboard_Entry is highlighted, THEN THE Popup_Panel SHALL take no paste action and remain visible.
7. IF the previously focused application is no longer available when a paste is initiated, THEN THE Paste_Engine SHALL place the content onto the system pasteboard without simulating the Cmd+V keystroke.

### Requirement 6: Application Lifecycle

**User Story:** As a macOS user, I want the clipboard manager to run in the background and start automatically, so that it is always available without manual intervention.

#### Acceptance Criteria

1. THE Clipboard_Monitor SHALL run as a background process accessible from the macOS menu bar without displaying a Dock icon.
2. THE Clipboard_Monitor SHALL provide a menu bar icon for accessing application settings, toggling "Launch at Login", and quitting the app.
3. WHERE the user enables "Launch at Login", THE Clipboard_Monitor SHALL register itself as a login item to start automatically on macOS boot.
4. WHEN the application is quit, THE History_Store SHALL persist all current clipboard entries within 2 seconds before termination completes.
5. IF persistence fails during application quit, THEN THE History_Store SHALL retain the previously persisted state so that no earlier entries are lost.
6. THE Clipboard_Monitor SHALL consume no more than 1% CPU averaged over any 60-second window while no new clipboard events are being processed.
7. IF the application terminates unexpectedly, THEN THE History_Store SHALL recover all entries from the last successful persistence on next launch.

### Requirement 7: Search and Filtering

**User Story:** As a macOS user, I want to search through my clipboard history, so that I can quickly find a specific item when the list is long.

#### Acceptance Criteria

1. THE Popup_Panel SHALL display a search input field at the top of the clipboard history list.
2. WHEN the Popup_Panel is activated, THE Popup_Panel SHALL place keyboard focus in the search input field.
3. WHEN the user types at least 1 character in the search field, THE Popup_Panel SHALL filter text entries to show only those containing the typed substring (case-insensitive) within 200 milliseconds of the last keystroke.
4. WHILE the search query is non-empty, THE Popup_Panel SHALL hide image entries from the filtered results.
5. IF the search query matches zero clipboard entries, THEN THE Popup_Panel SHALL display a message indicating no matching entries were found.
6. WHEN the search field is cleared, THE Popup_Panel SHALL restore the full list of clipboard entries including image entries.
7. WHEN the Escape key is pressed while the search field contains text, THE Popup_Panel SHALL clear the search field and restore the full list instead of dismissing the panel.
