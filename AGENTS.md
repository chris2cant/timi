# AGENTS.md

## Product

- Timi is a small native macOS desktop mascot.
- Support macOS only for now. Optimize for native behavior, simplicity, low resource usage, and maintainability.
- Do not anticipate hypothetical requirements or expand V0 into AI, networking, accounts, analytics, or cloud features.

## Technology

- Use Swift and SwiftUI first. Use AppKit only when it is the correct primitive for macOS window behavior.
- Use Observation when the selected Xcode/SDK toolchain supports it consistently; `ObservableObject` is acceptable for this small shared SwiftUI/AppKit state boundary.
- Prefer Apple frameworks. Every third-party dependency needs a concrete, documented reason.
- Do not introduce web technology into the desktop shell.

## Architecture

- Keep state ownership obvious and prefer simple composition over frameworks.
- Isolate macOS window side effects in the window controller.
- Keep screen-position calculations pure and independently testable.
- Do not add an abstraction before two real implementations or a concrete testing need exists.

## Quality

- Build after meaningful changes and fix compiler warnings.
- Use modern, non-deprecated APIs supported by the deployment target.
- Keep changes focused and do not silently change unrelated project settings.

## Agent behavior

- Briefly explain important macOS-specific decisions and surprising platform behavior.
- Mention why AppKit is necessary when it is used; do not over-explain generic programming concepts.
- Flag choices that could complicate signing, sandboxing, notarization, or distribution.
- Keep `TODO.md` current after every meaningful product change: mark completed work, preserve pending manual validations, and add only concrete next steps.
