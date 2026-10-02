# Timi

Timi is a deliberately small, native macOS desktop mascot. It displays an animated transparent floating panel, supports eight screen anchors, can be dragged and snapped to any screen edge, and remembers its placement and visibility between launches.

## Requirements

- macOS 14 or later
- Xcode with the macOS SDK installed

## Run the app

1. Open `Timi.xcodeproj` in Xcode.
2. Select the `Timi` scheme and the `My Mac` destination.
3. Press **Run** (`⌘R`).
4. Open **Timi > Settings…** (`⌘,`) to move the mascot.

You can also drag Timi directly, including onto the menu bar or Dock area. Releasing it near a screen edge snaps it flush to that edge. Selecting a new anchor resets the manual offset; Settings includes a dedicated reset button and a visibility toggle as well. Decorative movement follows the macOS **Reduce motion** accessibility setting.

The app intentionally keeps a normal Dock icon in V0 so Settings and Quit remain easy to find.

## Tests

Run the `TimiTests` test target in Xcode (`⌘U`).

## Code map

- Mascot appearance: `Timi/Mascot/MascotView.swift`
- Pure anchor geometry: `Timi/Mascot/PositionCalculator.swift`
- Floating AppKit panel: `Timi/Mascot/MascotWindowController.swift`
- Persistent state: `Timi/App/AppState.swift`
- Native Settings UI: `Timi/Settings/SettingsView.swift`
- Native decisions and Apple references: `docs/architecture.md`

There are no third-party dependencies.
