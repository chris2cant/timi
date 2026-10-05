# Timi

Timi is a deliberately small, native macOS desktop mascot. It displays an animated transparent floating panel, supports eight screen anchors, can be dragged and snapped to any screen edge, remembers its placement and visibility between launches, and offers an optional local Apple Intelligence conversation.

## Requirements

- macOS 26 or later
- Xcode 26 or later
- A Mac compatible with Apple Intelligence, with Apple Intelligence enabled

## Run the app

1. Open `Timi.xcodeproj` in Xcode.
2. Select the `Timi` scheme and the `My Mac` destination.
3. Press **Run** (`⌘R`).
4. Open **Timi > Settings…** (`⌘,`) to move the mascot.

You can also drag Timi directly, including onto the menu bar or Dock area. Releasing it near a screen edge snaps it flush to that edge. Selecting a new anchor resets the manual offset; Settings includes a dedicated reset button and a visibility toggle as well. Decorative movement follows the macOS **Reduce motion** accessibility setting.

Timi's eyes follow the pointer anywhere on screen (read with `NSEvent.mouseLocation`, so no extra permission) and rest when Reduce Motion is on.

Click Timi to open the conversation bubble. Responses come from Apple's on-device Foundation Model and are streamed into the bubble; no account, API key, or network service is added by Timi. Press Escape or click elsewhere to close the bubble. On unsupported systems, the bubble explains why conversation is unavailable while the rest of Timi continues to work.

The microphone button uses Apple's on-device `SpeechTranscriber` for live dictation and falls back to the system dictation model when the newer model does not support the current locale. Click once to start, speak, then click the stop button to finalize the text before sending it. Timi requests microphone access only when dictation is first used and stops recording when the conversation bubble closes.

Timi also provides global local dictation. Press `Control-Space` from another app (the shortcut can be changed in Settings): a short press toggles dictation, while holding records until release. The mascot temporarily replaces its eyes with the elapsed time and a microphone-driven level meter. After final transcription, a separate Apple Intelligence session performs faithful cleanup and Timi pastes into the focused non-secure text field. If Accessibility is unavailable or the field cannot accept text, the result is left on the clipboard without interrupting recording with a permission prompt. Accessibility can be requested explicitly from Settings. Timi never stores audio or the text surrounding the cursor.

Vocabulary, confirmed heard-to-wanted corrections, and up to 100 dictations for 30 days are stored as one versioned JSON file in Application Support. Settings can search, edit, disable, or clear that local data. Input Monitoring is required for the global shortcut and Accessibility is required for compatible keyboard paste; App Sandbox remains disabled while these desktop-wide primitives are evaluated for distribution.

When a response finishes, Timi reads it aloud with `AVSpeechSynthesizer`. It detects the response language and selects the highest-quality matching system voice installed on the Mac, preferring the user's regional variant and excluding novelty and personal voices. Settings can override the automatic choice with any compatible voice that is actually available to the app and preview it; responses in other languages still use automatic selection. Starting another response or closing the conversation stops the current speech.

The app intentionally keeps a normal Dock icon in V0 so Settings and Quit remain easy to find.

## Tests

Run the `TimiTests` test target in Xcode (`⌘U`).

## Code map

- Mascot appearance: `Timi/Mascot/MascotView.swift`
- Pure anchor geometry: `Timi/Mascot/PositionCalculator.swift`
- Floating AppKit panel: `Timi/Mascot/MascotWindowController.swift`
- Conversation state and Apple Intelligence integration: `Timi/Chat/ChatState.swift`
- On-device speech transcription and microphone capture: `Timi/Chat/SpeechInputController.swift`
- Global dictation coordination, shortcut, insertion, and local catalog: `Timi/Dictation/`
- Native speech synthesis and voice selection: `Timi/Chat/SpeechOutputController.swift`
- Conversation UI and AppKit panel: `Timi/Chat/ChatView.swift`, `Timi/Chat/ChatWindowController.swift`
- Pure conversation-bubble geometry: `Timi/Chat/ChatPositionCalculator.swift`
- Persistent state: `Timi/App/AppState.swift`
- Native Settings UI: `Timi/Settings/SettingsView.swift`
- Native decisions and Apple references: `docs/architecture.md`

The only third-party dependency is [Sparkle](https://sparkle-project.org) 2 (Swift Package Manager), used for in-app updates: it is the de-facto standard macOS updater, verifies EdDSA signatures, and avoids writing a security-critical installer ourselves. Timi checks `appcast.xml` in this repository over HTTPS (your IP is visible to GitHub; no other data is sent) and always asks before installing. See [RELEASING.md](RELEASING.md).
