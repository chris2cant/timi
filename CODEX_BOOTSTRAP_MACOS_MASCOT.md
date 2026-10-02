# Codex Bootstrap — macOS Mascot App

## Context

I am an experienced software engineer, mainly in frontend/web development, but I have **never built a native macOS or iOS application before**.

I want to build this project almost entirely with coding agents / vibe coding. Because of that, I want the project to start from **clean, idiomatic, boring macOS foundations** rather than generating an over-engineered architecture or importing random libraries.

The product inspiration is a lightweight desktop mascot such as Taby, but **this first version must stay extremely small**.

Do not add AI, Claude Code hooks, MCP integrations, chat, networking, databases, accounts, analytics, or cloud infrastructure in this first version.

The goal of V0 is simply to prove that the native macOS shell and positioning behavior feel good.

---

# Product goal — V0

Create a **native macOS application** displaying a small floating mascot window on the desktop.

For now, the mascot can simply be a pleasant placeholder:
- a rounded shape,
- a simple SwiftUI illustration,
- an emoji,
- or another tiny local placeholder asset.

Do not spend time on final visual design yet.

The important part is the **window behavior**.

I want to be able to:

1. Launch the app.
2. See a small floating mascot/window on the screen.
3. Open a small settings UI.
4. Choose where the mascot should live around the screen.
5. Immediately see the mascot move to the chosen position.
6. Quit and reopen the app and have the chosen position remembered.

---

# Supported positions

Start with a small explicit set of screen anchors:

- Top Left
- Top Center
- Top Right
- Center Left
- Center Right
- Bottom Left
- Bottom Center
- Bottom Right

Keep a reasonable margin from the screen edges.

If it stays simple, also allow me to drag the mascot manually and remember an X/Y offset relative to the selected anchor.

Do **not** create a complex geometry/layout engine.

The implementation must correctly account for the macOS usable screen area, including the menu bar and Dock.

For V0, supporting the main display is enough.

Keep the model extensible enough that multiple displays could be added later, but do not implement multi-screen management unless it is essentially free.

---

# Window behavior

The mascot should feel like a small native macOS desktop companion.

Investigate the correct native macOS primitive before implementing it.

The likely direction is:

- SwiftUI for the UI.
- A small amount of AppKit where macOS window behavior requires it.
- Potentially `NSPanel` or another appropriate native window type for the floating mascot.

But **do not blindly implement this suggestion**. Verify the current Apple-recommended approach first.

Desired behavior:

- Small floating window.
- Borderless or visually borderless.
- Transparent background around the mascot.
- No normal title bar.
- No resize controls.
- The mascot should remain above normal windows where appropriate.
- It should not constantly steal keyboard focus.
- Settings must still be easy to open.
- It should behave like a good macOS citizen.

During the first iteration, prioritize debuggability over cleverness.

For example, do not hide the Dock icon or make the app a background-only agent until the basic experience works reliably.

---

# Settings

Create a very small native Settings UI.

At minimum:

## Mascot Position

A picker or visual grid for the 8 positions:

```text
┌─────────┬─────────┬─────────┐
│ topLeft │ top     │ topRight│
├─────────┼─────────┼─────────┤
│ left    │         │ right   │
├─────────┼─────────┼─────────┤
│ botLeft │ bottom  │ botRight│
└─────────┴─────────┴─────────┘
```

The center cell is intentionally unused.

Changing this value should reposition the mascot immediately.

Persist the choice using the simplest native mechanism appropriate for small user preferences.

Prefer `AppStorage` / `UserDefaults` unless there is a strong reason not to.

## Optional V0 controls

Only add these if they remain trivial:

- Show / Hide mascot.
- Reset position.
- Margin from screen edge.

Do not add a settings framework.

---

# Technical direction

Default to:

- Swift
- SwiftUI
- AppKit only where macOS-specific behavior requires it
- Swift Concurrency when async work eventually appears
- Observation / modern SwiftUI state management
- Apple's native frameworks
- Swift Package Manager only if a dependency becomes genuinely necessary

For this first version, the desired third-party dependency count is:

**0**

Do not add:

- Electron
- Tauri
- React Native
- Flutter
- Redux-style state management
- The Composable Architecture
- Combine unless a concrete native API requires it
- dependency injection frameworks
- networking libraries
- persistence libraries
- custom architecture frameworks

This is a tiny native desktop utility, not an enterprise application.

---

# Architecture principles

Keep the project very small.

Prefer a structure roughly like:

```text
Mascot/
├── App/
│   ├── MascotApp.swift
│   └── AppState.swift
│
├── Mascot/
│   ├── MascotView.swift
│   ├── MascotWindowController.swift
│   └── MascotPosition.swift
│
├── Settings/
│   └── SettingsView.swift
│
└── Support/
```

This is a guideline, not a requirement.

Do not create layers merely because an architecture article says they should exist.

Avoid structures like:

```text
View
→ ViewModel
→ UseCase
→ Repository
→ DataSource
→ Adapter
→ Manager
→ Coordinator
→ Factory
```

unless a real requirement emerges.

Prefer:

- small types,
- explicit names,
- value types where appropriate,
- one obvious source of truth,
- testable pure positioning logic,
- side effects isolated around AppKit/system boundaries.

---

# Before writing application code

Do this first.

## 1. Inspect the environment

Determine:

- installed Xcode version,
- Swift version,
- macOS SDK version,
- project tooling available,
- current deployment target options.

Do not assume old versions from memory.

## 2. Discover useful agent capabilities

Inspect the current Codex environment for:

- available skills,
- MCP servers,
- Apple-related development tooling,
- Swift/Xcode-specific integrations,
- documentation tools.

If an official or high-quality Apple/Swift skill exists, inspect it before coding.

If there is an MCP server that provides reliable Apple Developer documentation or Xcode project context, evaluate whether it is useful.

**Do not invent tools that do not exist.**

Do not install random community MCP servers or enormous skill packs just because they are available.

Only add tooling when it clearly improves this project.

## 3. Research current authoritative guidance

Before deciding how the floating window should be implemented, consult current authoritative sources.

Prioritize:

1. Apple Developer Documentation
2. Apple WWDC sessions
3. Swift.org
4. Official Xcode documentation

Use community sources only when the Apple documentation does not sufficiently explain a macOS-specific behavior.

Research specifically:

- modern SwiftUI macOS app lifecycle,
- Settings scenes,
- `NSPanel` / floating panels,
- transparent and borderless windows,
- non-activating windows,
- screen visible frame / safe positioning,
- persistence of small preferences,
- SwiftUI + AppKit interoperability.

Record any important architectural decisions in the repository.

---

# Create `AGENTS.md` before implementing the feature

Create an `AGENTS.md` at the repository root.

It should be concise and useful to future coding agents.

At minimum include the following principles:

## Product

- This is a small native macOS desktop mascot.
- macOS only for now.
- Optimize for native behavior, simplicity, low resource usage, and maintainability.
- Do not anticipate hypothetical product requirements.

## Technology

- Swift + SwiftUI first.
- Use AppKit only for capabilities where it is the correct macOS primitive.
- Prefer Apple frameworks over third-party packages.
- A new dependency requires a concrete justification.
- Do not introduce web technology into the desktop shell.

## Architecture

- Avoid over-engineering.
- Keep state ownership obvious.
- Prefer simple composition over frameworks.
- Keep macOS/window side effects isolated.
- Make screen-position calculations testable separately from window manipulation.
- Do not create abstractions before there are at least two real implementations or a concrete testing need.

## Quality

- Build after meaningful changes.
- Fix compiler warnings instead of ignoring them.
- Use modern Swift APIs appropriate to the current deployment target.
- Do not use deprecated APIs without a documented reason.
- Keep changes focused.
- Do not silently change unrelated project settings.

## Agent behavior

Because the owner is an experienced developer but new to native Apple development:

- explain important macOS-specific decisions briefly,
- call out surprising Apple platform behavior,
- do not over-explain generic programming concepts,
- mention when AppKit is necessary and why,
- flag any decision that may make future distribution/notarization harder.

---

# Implementation sequence

Follow this order.

## Step 1 — Project skeleton

Create the smallest valid native macOS application.

Confirm it builds and launches.

Do not start feature work until the project builds cleanly.

## Step 2 — Static mascot

Display a small mascot view in a dedicated floating window.

Use a simple placeholder visual.

Confirm:

- correct size,
- transparency,
- no unwanted title bar,
- reasonable floating behavior.

## Step 3 — Position model

Create a small model such as:

```swift
enum MascotPosition: String, CaseIterable, Codable {
    case topLeft
    case top
    case topRight
    case left
    case right
    case bottomLeft
    case bottom
    case bottomRight
}
```

Names may differ if a more idiomatic Swift solution is preferable.

Put screen coordinate calculation in a small pure/testable component.

## Step 4 — Settings

Create native macOS Settings.

Allow selecting the mascot position.

Changing the setting must move the mascot immediately.

## Step 5 — Persistence

Persist the selected position.

Quit the app.

Relaunch it.

The mascot must appear in the previously selected position.

## Step 6 — Polish only what is necessary

Fix:

- focus issues,
- unexpected window activation,
- incorrect screen-edge placement,
- weird animations,
- resizing problems,
- menu bar / Dock overlap.

Do not expand the product scope.

---

# Acceptance criteria

V0 is complete when all of these are true:

- [ ] The project is a native macOS Swift application.
- [ ] The project builds cleanly in Xcode.
- [ ] A small mascot window appears.
- [ ] The window has no normal document-window chrome.
- [ ] The surrounding background can be transparent.
- [ ] The mascot can be positioned in all 8 supported screen locations.
- [ ] Changing the setting updates the window immediately.
- [ ] Position survives application restart.
- [ ] The mascot does not unnecessarily steal focus.
- [ ] Screen positioning respects the usable main-display frame.
- [ ] Settings are implemented with native macOS UI.
- [ ] No third-party dependency was added without a documented need.
- [ ] `AGENTS.md` exists and describes the project rules.
- [ ] README contains basic build/run instructions.
- [ ] Important native macOS architectural decisions are briefly documented.

---

# Tests

Do not create a giant test suite.

Add focused unit tests for the parts that benefit from them, especially screen-position calculations.

For example, given:

- a fake visible screen frame,
- a mascot size,
- an edge margin,
- a `MascotPosition`,

the positioning function should return the expected origin.

Avoid UI testing unless it solves a real problem in V0.

---

# Definition of simplicity

Before adding any abstraction, package, helper layer, service, manager, protocol, or framework, ask:

> Does the current V0 need this, or am I anticipating a future problem?

If it is for a hypothetical future requirement, do not add it.

A good V0 should contain surprisingly little code.

---

# What NOT to build yet

Explicitly out of scope:

- LLM APIs
- Claude Code integration
- Codex integration
- hooks
- MCP product features
- chat
- voice
- screen capture
- accessibility permissions
- filesystem browsing
- local databases
- cloud sync
- accounts
- analytics
- auto-update system
- launch at login
- Mac App Store distribution work
- final mascot animations
- multiple mascots
- multiple agent providers
- Windows support
- iOS support

These may come later.

---

# Final task

Start by researching and documenting the native macOS choices, create `AGENTS.md`, initialize the smallest appropriate Xcode project, and then implement the V0 described above.

When you encounter a choice between:

- a clever/general solution,
- and a small native solution that solves the current requirement,

choose the small native solution.

At the end, provide me with:

1. a short summary of the architecture,
2. the important macOS concepts I should understand,
3. how to run the app,
4. where to change the mascot placeholder,
5. where the positioning logic lives,
6. any decisions that should be revisited before a public release.
