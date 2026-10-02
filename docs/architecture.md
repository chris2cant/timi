# V0 architecture decisions

## Environment inspected on 2026-10-02

- Xcode 26.6 (`17F113`)
- Apple Swift 6.3.3 (`swiftlang-6.3.3.1.3`)
- macOS SDK 26.5
- No Apple/Swift-specific Codex skill or MCP server was available
- No XcodeGen, Tuist, SwiftLint, or third-party project tool was introduced

The app targets macOS 14, retaining a conservative deployment baseline while using current SwiftUI and AppKit APIs.

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

The controller normally resolves the panel's display from its persisted UUID. Immediately after `performDrag(with:)` returns, however, AppKit can still report the previous value from `NSWindow.screen` during the same mouse event. The drag path therefore uses the screen containing `NSEvent.mouseLocation` at release, with the largest geometric intersection between the panel frame and `NSScreen.screens` as a fallback. These pure selection calculations are unit tested. Snapping and clamping use the destination display's full `frame`; the persisted offset stays relative to the selected anchor in `visibleFrame`, which excludes the menu bar and Dock. Screen geometry is not cached; the panel moves again after display parameters change.

The current implementation records a ColorSync display UUID in addition to the anchor-relative offset. Manual validation shows that a normal Xcode `⌘R` launch still returns Timi to the wrong display, so cross-display persistence remains a known issue rather than a completed V0 behavior. Main-display positioning remains the supported baseline.

- [NSScreen visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe)
- [NSWindow screen](https://developer.apple.com/documentation/appkit/nswindow/screen)

## State and persistence

`AppDelegate` owns the single `AppState` and window controller. `AppState` uses SwiftUI's established `ObservableObject`/`Published` bridge and persists the anchor, its manual X/Y offset, destination display UUID, and mascot visibility to `UserDefaults`. SwiftUI Settings observes that state directly; changing an anchor, completing a drag, or toggling visibility updates the panel immediately. This narrow Combine use is the concrete native state-observation boundary and avoids a compiler/SDK macro mismatch found in the bootstrap Command Line Tools.

- [SwiftUI persistent storage](https://developer.apple.com/documentation/swiftui/persistent-storage)
- [AppStorage](https://developer.apple.com/documentation/swiftui/appstorage)

`AppStorage` is Apple's natural view-local option. This V0 uses the same underlying `UserDefaults` directly in `AppState` so both the Settings view and AppKit controller share one explicit source of truth.

## Interaction and accessibility

The AppKit hosting view distinguishes a click from a drag using the panel's movement distance after `performDrag(with:)`. It forwards only a small click event into SwiftUI; SwiftUI remains responsible for rendering the reaction. This keeps native macOS window movement in AppKit without moving visual state into the window controller.

The mascot reads SwiftUI's `accessibilityReduceMotion` environment value. When the macOS **Reduce motion** setting is active, decorative breathing, hover scaling, and click scaling are suppressed; blinking and the static face remain available.

The mascot is exposed as an accessibility button with an explicit activation action for its reaction. Moving it remains available through the native Settings anchor controls, so VoiceOver users do not have to reproduce a pointer drag.

The generated bundle declares `AppIcon` and contains the compiled `.icns`; `AppDelegate` also assigns it to `NSApplication.applicationIconImage`. Manual validation still shows an empty icon during a normal Xcode `⌘R` launch, so the issue is tracked as unresolved.

## Revisit before public release

- Install the release Xcode, build/archive with warnings treated seriously, and reconfirm the deployment target.
- Choose an application identifier, signing team, sandbox entitlements, hardened runtime settings, and notarization flow.
- Decide whether the mascot should appear on every Space and above full-screen apps; those behaviors can surprise users.
- Review accessibility labels, keyboard access, reduced-motion behavior, and transparent-window hit testing.
- Review the app icon at every macOS display size, then prepare versioning, a privacy statement, and release metadata.
- Decide whether a Dock app, menu bar extra, or agent-style app is appropriate only after V0 behavior is proven.
