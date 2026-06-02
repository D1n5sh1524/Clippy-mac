# Implementation Plan

## Overview

This implementation plan covers the macOS clipboard history manager built with Swift and SwiftUI. Tasks are ordered for incremental implementation: data models first, then core services (HistoryStore, ClipboardMonitor, ShortcutListener, PasteEngine), followed by the UI layer and application lifecycle. Property-based tests are interleaved with implementation to validate correctness properties as each component is built.

## Tasks

- [x] 1. Project Setup and Configuration
  - [x] 1.1 Create the Xcode project structure for a macOS menu bar app (SwiftUI lifecycle, LSUIElement=true in Info.plist)
  - [x] 1.2 Configure Swift Package Manager dependencies (SwiftCheck for property-based testing, swift-testing framework)
  - [x] 1.3 Set minimum deployment target to macOS 13.0 (Ventura)
  - [x] 1.4 Create the main app entry point (`ClipboardHistoryApp.swift`) with AppDelegate adapter for AppKit integration

- [ ] 2. Data Models Implementation
  - [ ] 2.1 Implement `ClipboardContent` enum with `.text(String)` and `.image(Data)` cases, `Codable` and `Equatable` conformance, `textPreview` computed property, and `exceedsSizeLimit` check
  - [ ] 2.2 Implement `ClipboardEntry` struct with `id: UUID`, `content: ClipboardContent`, `timestamp: Date`, `contentType: ContentType` enum, and `Codable`/`Equatable`/`Identifiable` conformance
  - [ ] 2.3 Implement `KeyboardShortcut` struct with `keyCode`, `modifiers`, `isValid` computed property, and `static let default` for Cmd+Shift+V
  - [ ] 2.4 Implement `RelativeTimestampFormatter` that formats dates using the largest applicable unit (days >= 86400s, hours >= 3600s, minutes >= 60s, seconds otherwise)
  - [ ] 2.5 Implement image thumbnail scaling utility function that fits dimensions within 64x64 while preserving aspect ratio

- [ ] 3. Property Tests for Data Models
  - [ ] 3.1 Write property test for serialization round-trip (Property 1): generate random ClipboardEntry values, encode to JSON, decode back, assert equality **Validates: Requirements 1.1, 1.2**
  - [ ] 3.2 Write property test for size limit enforcement (Property 3): generate strings/data of varying sizes, verify boundary at 1,000,000 chars and 10 MB **Validates: Requirements 1.8**
  - [ ] 3.3 Write property test for text preview formatting (Property 9): generate random strings with newlines and varying lengths, verify truncation and newline replacement rules **Validates: Requirements 4.2**
  - [ ] 3.4 Write property test for image thumbnail scaling (Property 10): generate random dimensions, verify output fits 64x64 with correct aspect ratio within +-1px tolerance **Validates: Requirements 4.3**
  - [ ] 3.5 Write property test for relative timestamp formatting (Property 11): generate random time intervals, verify largest applicable unit selection **Validates: Requirements 4.4**
  - [ ] 3.6 Write property test for shortcut validation (Property 8): generate random key+modifier combinations, verify validation logic **Validates: Requirements 3.5**

- [ ] 4. HistoryStore Implementation
  - [ ] 4.1 Implement `HistoryStore` actor with in-memory `entries` array and `maxEntries = 50`
  - [ ] 4.2 Implement `addEntry(_:)` with FIFO eviction when at capacity (remove oldest before adding new)
  - [ ] 4.3 Implement `deleteEntry(id:)` to remove a single entry by UUID
  - [ ] 4.4 Implement `clearAll()` to remove all entries
  - [ ] 4.5 Implement `moveToTop(id:)` to move a selected entry to the most recent position
  - [ ] 4.6 Implement `getAllEntries()` returning entries ordered most recent first
  - [ ] 4.7 Implement `search(query:)` with case-insensitive substring matching on text entries, excluding image entries
  - [ ] 4.8 Implement JSON persistence: `load()`, `schedulePersist()` (debounced within 1s), and `persistImmediately()`
  - [ ] 4.9 Implement storage URL resolution to `~/Library/Application Support/ClipboardHistory/clipboard_history.json`
  - [ ] 4.10 Implement corrupted file recovery: rename to `.corrupt`, start empty, post user notification

- [ ] 5. Property Tests for HistoryStore
  - [ ] 5.1 Write property test for duplicate detection correctness (Property 2): generate random content, verify detection for identical/different content against most recent entry **Validates: Requirements 1.5**
  - [ ] 5.2 Write property test for capacity invariant with FIFO eviction (Property 4): generate sequences of >50 entries, verify store never exceeds 50 and oldest is evicted **Validates: Requirements 2.2, 2.3**
  - [ ] 5.3 Write property test for ordering invariant (Property 5): generate random operation sequences, verify entries always ordered most recent first **Validates: Requirements 2.6, 1.3**
  - [ ] 5.4 Write property test for deletion removes exactly one entry (Property 6): generate stores of random sizes, delete random entries, verify correct removal and order preservation **Validates: Requirements 2.4**
  - [ ] 5.5 Write property test for move-to-top preserves relative order (Property 7): generate stores, move random entries, verify moved entry is first and others maintain order **Validates: Requirements 5.3**
  - [ ] 5.6 Write property test for search filtering correctness (Property 13): generate random entry sets and queries, verify only matching text entries returned **Validates: Requirements 7.3, 7.4**
  - [ ] 5.7 Write property test for search clear restores full list (Property 14): generate entries, filter, clear, verify full list restored **Validates: Requirements 7.6**

- [ ] 6. ClipboardMonitor Implementation
  - [ ] 6.1 Implement `ClipboardMonitor` actor with reference to `NSPasteboard.general` and `lastChangeCount` tracking
  - [ ] 6.2 Implement `startMonitoring()` with a Timer firing every 500ms calling `checkForChanges()`
  - [ ] 6.3 Implement `checkForChanges()` comparing `pasteboard.changeCount` to `lastChangeCount` and processing new content
  - [ ] 6.4 Implement `extractText()` to read plain text or rich text from the pasteboard
  - [ ] 6.5 Implement `extractImage()` to read image data (PNG/TIFF) from the pasteboard
  - [ ] 6.6 Implement `isDuplicate(_:)` to compare new content against the most recent entry (byte-identical check)
  - [ ] 6.7 Implement size limit enforcement: discard text > 1,000,000 chars or image > 10 MB
  - [ ] 6.8 Implement error handling: skip cycle on pasteboard access failure without interrupting monitoring
  - [ ] 6.9 Implement `stopMonitoring()` to invalidate the timer

- [ ] 7. ShortcutListener Implementation
  - [ ] 7.1 Implement `ShortcutListener` class with Carbon `RegisterEventHotKey` integration
  - [ ] 7.2 Implement `register(shortcut:)` that registers the global hotkey and stores the `EventHotKeyRef`
  - [ ] 7.3 Implement `unregister()` to call `UnregisterEventHotKey`
  - [ ] 7.4 Implement `updateShortcut(_:)` that unregisters old, validates new, and registers new shortcut
  - [ ] 7.5 Implement `validate(_:)` to check at least one modifier plus non-modifier key requirement
  - [ ] 7.6 Implement conflict handling: display notification on registration failure, revert to previous shortcut

- [ ] 8. PasteEngine Implementation
  - [ ] 8.1 Implement `PasteEngine` class with `placeOnPasteboard(_:)` to write content to `NSPasteboard.general`
  - [ ] 8.2 Implement `simulatePaste()` using `CGEvent` API to synthesize Cmd+V keystroke
  - [ ] 8.3 Implement `paste(entry:targetApp:)` orchestration: place on pasteboard then simulate paste
  - [ ] 8.4 Implement `isAppAvailable(_:)` check to skip Cmd+V simulation if target app is terminated

- [ ] 9. PopupPanel and UI Layer
  - [ ] 9.1 Implement `PopupPanel` as `NSPanel` subclass with floating non-activating panel behavior
  - [ ] 9.2 Implement `showNearCursor()` positioning logic: near cursor if within screen bounds, centered otherwise
  - [ ] 9.3 Implement `dismiss()` with focus return to `previousApp`
  - [ ] 9.4 Implement focus-loss detection to auto-dismiss the panel
  - [ ] 9.5 Implement `PopupView` (SwiftUI) as the root view hosted in the panel
  - [ ] 9.6 Implement `SearchView` with text field that receives focus on panel activation
  - [ ] 9.7 Implement `EntryRowView` showing text preview, image thumbnail, content type icon, and relative timestamp
  - [ ] 9.8 Implement keyboard navigation: Up/Down arrow keys to move highlight, stopping at bounds
  - [ ] 9.9 Implement Enter key to paste highlighted entry, no-op if nothing highlighted
  - [ ] 9.10 Implement Escape key behavior: clear search if text present, dismiss panel if search is empty
  - [ ] 9.11 Implement empty-state message when no entries exist
  - [ ] 9.12 Implement no-results message when search query matches nothing

- [ ] 10. Property Tests for UI Logic
  - [ ] 10.1 Write property test for panel positioning (Property 12): generate random cursor positions and screen bounds, verify placement rules **Validates: Requirements 4.5**
  - [ ] 10.2 Write property test for arrow key navigation bounds (Property 15): generate random list sizes and positions, verify bounds enforcement **Validates: Requirements 5.4**

- [ ] 11. MenuBarController and Application Lifecycle
  - [ ] 11.1 Implement `MenuBarController` with `NSStatusItem` setup (icon, menu with Settings, Launch at Login toggle, Quit)
  - [ ] 11.2 Implement `AppDelegate` wiring: initialize ClipboardMonitor, HistoryStore, ShortcutListener, MenuBarController on app launch
  - [ ] 11.3 Implement `applicationWillTerminate` handler: call `persistImmediately()` with 2-second timeout
  - [ ] 11.4 Implement Launch at Login registration/deregistration using `SMAppService` (macOS 13+)
  - [ ] 11.5 Implement ShortcutListener toggle behavior: show panel if hidden, hide if visible

- [ ] 12. Unit Tests for Core Behavior
  - [ ] 12.1 Write unit tests for pasteboard text/image extraction with known content types
  - [ ] 12.2 Write unit tests for non-text/non-image content being ignored (Requirement 1.6)
  - [ ] 12.3 Write unit tests for pasteboard failure recovery verifying polling continues after simulated access failure (Requirement 1.7)
  - [ ] 12.4 Write unit tests for clear all with confirmation flow (Requirement 2.5)
  - [ ] 12.5 Write unit tests for corrupted storage loading with graceful recovery and notification (Requirement 2.7)
  - [ ] 12.6 Write unit tests for shortcut toggle behavior showing and hiding panel (Requirement 3.3)
  - [ ] 12.7 Write unit tests for shortcut conflict handling with notification and fallback (Requirements 3.4, 3.6)
  - [ ] 12.8 Write unit tests for empty state display (Requirement 4.9)
  - [ ] 12.9 Write unit tests for Enter with no highlight producing no-op (Requirement 5.6)
  - [ ] 12.10 Write unit tests for target app unavailable skipping Cmd+V simulation (Requirement 5.7)
  - [ ] 12.11 Write unit tests for Escape key clearing search vs dismissing panel (Requirements 7.7, 4.7)
  - [ ] 12.12 Write unit tests for no search results message display (Requirement 7.5)
  - [ ] 12.13 Write unit tests for search field focus on activation (Requirement 7.2)

- [ ] 13. Integration and Smoke Tests
  - [ ] 13.1 Write integration test verifying pasteboard polling occurs at 500ms intervals or less (Requirement 1.4)
  - [ ] 13.2 Write integration test verifying persistence happens within 1 second of changes (Requirement 2.1)
  - [ ] 13.3 Write integration test verifying panel appears within 200ms of shortcut press (Requirement 3.2)
  - [ ] 13.4 Write integration test verifying dismiss plus focus return within 200ms (Requirement 5.2)
  - [ ] 13.5 Write integration test verifying login item registration and deregistration (Requirement 6.3)
  - [ ] 13.6 Write integration test verifying all entries persisted within 2 seconds on quit (Requirement 6.4)
  - [ ] 13.7 Write smoke test verifying LSUIElement configuration produces no Dock icon (Requirement 6.1)
  - [ ] 13.8 Write smoke test verifying NSStatusItem creation with correct menu items (Requirement 6.2)

## Task Dependency Graph

```json
{
  "waves": [
    {"tasks": ["1"]},
    {"tasks": ["2"]},
    {"tasks": ["3", "4", "7"]},
    {"tasks": ["5", "6", "8"]},
    {"tasks": ["9"]},
    {"tasks": ["10", "11"]},
    {"tasks": ["12"]},
    {"tasks": ["13"]}
  ]
}
```

## Notes

- Property-based tests use SwiftCheck integrated with the Swift Testing framework as specified in the design document.
- Each property test runs a minimum of 100 iterations with generated inputs.
- Carbon APIs (`RegisterEventHotKey`) require linking the Carbon framework in the project.
- `CGEvent` paste simulation requires Accessibility permission at runtime; tests for PasteEngine should mock this interaction.
- The application uses Swift actors (`ClipboardMonitor`, `HistoryStore`) for thread safety — tests must use `async/await`.
