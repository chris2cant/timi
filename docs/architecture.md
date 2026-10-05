# V0 architecture decisions

## Environment inspected on 2026-10-02

- Xcode 26.6 (`17F113`)
- Apple Swift 6.3.3 (`swiftlang-6.3.3.1.3`)
- macOS SDK 26.5
- No Apple/Swift-specific Codex skill or MCP server was available
- No XcodeGen, Tuist, SwiftLint, or third-party project tool was introduced

The app targets macOS 26 because Apple Intelligence conversation and the modern on-device speech APIs are core product capabilities. Supporting an older shell without those capabilities would add availability branches without serving Timi's current product direction.

## Window ownership

SwiftUI owns app lifecycle, Settings, state observation, and mascot rendering. AppKit owns one behavior SwiftUI scenes do not express precisely: a small non-activating floating panel.

`MascotWindowController` creates an `NSPanel` with borderless and non-activating style masks, hosts `MascotView` in an `NSHostingView`, and positions the panel. The panel uses AppKit's screen-saver window level so it can intentionally cover the menu bar and Dock, does not become key merely when clicked, and remains visible when another app activates. This high level is deliberately isolated in the window controller because SwiftUI does not expose this macOS window behavior. Keeping `hidesOnDeactivate` off is an intentional product choice: Apple's default panel behavior is to hide, but a desktop companion needs to remain present.

Apple references:

- [SwiftUI Settings](https://developer.apple.com/documentation/swiftui/settings)
- [Adding a settings interface](https://developer.apple.com/documentation/foundation/adding-a-settings-interface-to-your-app)
- [SwiftUI and AppKit integration](https://developer.apple.com/documentation/swiftui/appkit-integration)
- [NSPanel](https://developer.apple.com/documentation/appkit/nspanel)
- [NSPanel floating guidance](https://developer.apple.com/documentation/appkit/nspanel/isfloatingpanel)
- [Non-activating panel style](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)
- [Borderless window style](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/borderless)

## Positioning

`PositionCalculator` is pure: it receives a screen rectangle, panel size, margin, anchor, and optional manual offset and returns an AppKit window origin. AppKit coordinates start at the lower-left, so top anchors derive their Y coordinate from `visibleFrame.maxY`. Settings anchors continue to use the comfortable visible area, while manual movement is clamped to the complete `screen.frame`. A release within 36 points of one or two screen edges snaps the panel flush to those edges, including the area occupied by the menu bar or Dock.

The same pure geometry reports which screen edges are touching the mascot. `MascotWindowController` publishes that small piece of AppKit state to `MascotView`, which draws the notch-style concave connections outside the 148 × 104 pt head. The transparent AppKit panel includes a 22 pt drawing margin for those connections, while positioning, persistence, hit testing, and chat placement continue to use the visible head frame.

The controller normally resolves the panel's display from its persisted UUID. During a drag, it uses the screen containing `NSEvent.mouseLocation`, with the largest geometric intersection between the visible mascot frame and `NSScreen.screens` as a fallback. These pure selection calculations are unit tested. Snapping and continuous clamping use the destination display's full `frame`; the persisted offset stays relative to the selected anchor in `visibleFrame`, which excludes the menu bar and Dock. Screen geometry is not cached; the panel moves again after display parameters change.

The current implementation records a ColorSync display UUID in addition to the anchor-relative offset. Manual validation confirms that Timi restores its placement on the correct display after relaunch.

- [NSScreen visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe)
- [NSWindow screen](https://developer.apple.com/documentation/appkit/nswindow/screen)

## State and persistence

`AppDelegate` owns the single `AppState` and window controller. `AppState` uses SwiftUI's established `ObservableObject`/`Published` bridge and persists the anchor, its manual X/Y offset, destination display UUID, and mascot visibility to `UserDefaults`. SwiftUI Settings observes that state directly; changing an anchor, completing a drag, or toggling visibility updates the panel immediately. This narrow Combine use is the concrete native state-observation boundary and avoids a compiler/SDK macro mismatch found in the bootstrap Command Line Tools.

- [SwiftUI persistent storage](https://developer.apple.com/documentation/swiftui/persistent-storage)
- [AppStorage](https://developer.apple.com/documentation/swiftui/appstorage)

`AppStorage` is Apple's natural view-local option. This V0 uses the same underlying `UserDefaults` directly in `AppState` so both the Settings view and AppKit controller share one explicit source of truth.

## Local conversation

`ChatState` owns the in-memory transcript and one `LanguageModelSession`. Reusing that session lets Apple Intelligence retain conversational context until the app quits, while `streamResponse(to:)` updates the latest Timi message as generation progresses. The system model runs locally; Timi does not add networking, API keys, accounts, analytics, or cloud infrastructure.

At runtime, `SystemLanguageModel.default.availability` distinguishes an unsupported device, disabled Apple Intelligence, a model that is not ready, and temporary unavailability. These states are shown in the conversation UI instead of leaving a disabled input unexplained.

## Local dictation

`SpeechInputController` owns the UI-facing dictation state, while a dedicated `SpeechAudioPipeline` actor captures the microphone with `AVAudioEngine`, converts its buffers to the format selected by `SpeechAnalyzer`, and streams them into `SpeechTranscriber`. Core Audio can synchronously wait while opening an input device, so isolating that pipeline keeps the SwiftUI main actor responsive during microphone startup and shutdown. The new Apple speech model is preferred because it is designed for low-latency conversational transcription and operates entirely on device. `DictationTranscriber` provides a local fallback when the newer model does not support the current locale or hardware. Locale assets are requested through `AssetInventory` and remain system-managed rather than increasing Timi's bundle size.

The composer shows volatile text while the person speaks and replaces it with finalized text when more context improves the transcription. Stopping recording finalizes the analyzer before releasing the microphone. Closing the conversation also stops capture, and Timi never sends automatically after dictation so the person can review the recognized text first.

The dictation locale is selected explicitly in Settings and persisted in `AppState`. French is the default so recognition does not silently follow an English system locale; automatic system-language detection and English remain available choices.

After streaming completes, `SpeechOutputController` reads the final response through `AVSpeechSynthesizer`. It detects the response language, prefers the user's regional variant, and selects the highest-quality installed system voice while excluding novelty and personal voices. The user can persistently override that choice in Settings with a voice exposed to the app; the override applies only to matching-language responses, and an inline preview makes the effective voice audible. Waiting for the complete response avoids the broken prosody caused by speaking arbitrary streamed fragments. Voice assets remain managed by macOS, so this adds no bundled model, permission, or distribution requirement.

Microphone capture requires `NSMicrophoneUsageDescription` and the Hardened Runtime audio-input entitlement. The entitlement is included now; public distribution will still require the normal Developer ID or App Store signing, sandbox, and notarization review.

`DictationCoordinator` is the single state owner shared by the conversation composer and global dictation. The global path uses a Core Graphics event tap because an ordinary SwiftUI keyboard shortcut cannot receive and neutralize a chord while another application is active. A short press toggles and a 280 ms hold records until key-up; the pure state machine rejects autorepeat. Input Monitoring is therefore requested separately and the default `Control-Space` conflict with macOS input-source shortcuts is reported without changing System Settings.

The audio tap computes RMS from each transient `AVAudioPCMBuffer`, smooths attack/release, and publishes only a normalized level at no more than 20 Hz. It retains no samples. The last published buffer timestamp also feeds a 1.5-second watchdog; silence based on low RMS remains distinct and is reported after three seconds. `SpeechAnalyzer` receives up to 200 enabled catalog terms through `AnalysisContext`, and transcription explicitly requests alternatives and confidence attributes.

Global cleanup uses a fresh `LanguageModelSession` prepared while listening. Its prompt receives the raw transcript, at most 500 UTF-16 units around the live cursor, two recognition alternatives, exact correction rules, and preferred terms. The cursor context is never persisted. Empty, conversational, or disproportionate model output is rejected, and cancellation after eight seconds falls back to exact replacements plus conservative deterministic cleanup.

AppKit Accessibility APIs inspect the focused element only at insertion time, so an intentional focus change during cleanup is respected. Secure Input, secure fields, read-only fields, missing trust, and inaccessible content all fall back to the clipboard. For writable fields Timi posts a native Command-V event, which is more compatible with Slack, Gmail, and web `contenteditable` controls than assigning `AXValue`; the previous pasteboard items are restored only when the focused AX value confirms the paste. If confirmation is impossible, Timi conservatively leaves the transcript in the clipboard and reports « Copié ». These system-wide event and Accessibility primitives are the reason App Sandbox remains disabled, and they must be revisited before signing, notarization, or Mac App Store distribution.

The versioned JSON catalog is written atomically in Application Support. It contains only vocabulary, confirmed correction rules, and raw/refined/corrected text history. History is pruned to 100 records and 30 days; application context, pasteboard contents, alternatives, and audio are excluded.

- [Speech framework](https://developer.apple.com/documentation/speech)
- [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)
- [WWDC25: Bring advanced speech-to-text to your app with SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)

The conversation uses a second borderless, non-activating `NSPanel`. AppKit is necessary here because the bubble must become key for text entry without turning the mascot into a conventional application window. The panel closes when it loses key status or when the user presses Escape, and it follows the mascot's all-Spaces/full-screen behavior. `ChatPositionCalculator` independently chooses the right or left side of Timi and clamps the bubble to `NSScreen.visibleFrame`; its geometry is unit tested.

- [Foundation Models](https://developer.apple.com/documentation/foundationmodels)
- [SystemLanguageModel availability](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.property)
- [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession)

## Interaction and accessibility

The AppKit hosting view distinguishes a click from a drag using the pointer's movement distance. It tracks native mouse drag events and asks the controller to clamp the mascot panel on every movement; `NSWindow.performDrag(with:)` is intentionally not used because AppKit allows a borderless panel to travel partly beyond a display while that native drag is in progress. The controller applies the pure edge-snap calculation continuously, and releasing the pointer persists that previewed placement.

The mascot reads SwiftUI's `accessibilityReduceMotion` environment value. When the macOS **Reduce motion** setting is active, decorative breathing, hover scaling, and click scaling are suppressed; blinking and the static face remain available.

The mascot is exposed as an accessibility button with an explicit activation action for its reaction. Moving it remains available through the native Settings anchor controls, so VoiceOver users do not have to reproduce a pointer drag.

The generated bundle declares `AppIcon` and contains the compiled `.icns`; `AppDelegate` also assigns it to `NSApplication.applicationIconImage`. Manual validation confirms that the icon appears during a normal Xcode `⌘R` launch.

## Updates (Sparkle)

`UpdateManager` owns one `SPUStandardUpdaterController` for the app lifetime and exposes `checkForUpdates()` and `canCheckForUpdates` to the status-item menu, the app menu and Settings. Sparkle is the only third-party dependency; the documented reason is secure, signed, user-confirmed updates without writing our own installer. Trust rests on the Sparkle EdDSA key (feed and archives signed, verified before extraction), not on Apple signing. `com.apple.security.cs.disable-library-validation` is required because a self-signed or ad-hoc app has no Team ID; remove it when moving to Developer ID and notarization. See `RELEASING.md`.

## Revisit before public release

- Install the release Xcode, build/archive with warnings treated seriously, and reconfirm the deployment target.
- Choose an application identifier, signing team, sandbox entitlements, hardened runtime settings, and notarization flow.
- Decide whether the mascot should appear on every Space and above full-screen apps; those behaviors can surprise users.
- Review accessibility labels, keyboard access, reduced-motion behavior, and transparent-window hit testing.
- Revalidate Foundation Models prompts and availability handling when adopting a new macOS SDK because Apple can update the system model with OS releases.
- Review the app icon at every macOS display size, then prepare versioning, a privacy statement, and release metadata.
- Decide whether a Dock app, menu bar extra, or agent-style app is appropriate only after V0 behavior is proven.
