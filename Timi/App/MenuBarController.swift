import AppKit

/// Menu bar item. NSStatusItem is the only AppKit-free-of-SwiftUI primitive for this
/// that works with the existing NSApplicationDelegate setup and keeps the Dock icon.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
  private let appState: AppState
  private let statusItem: NSStatusItem
  private let toggleItem = NSMenuItem()

  init(appState: AppState) {
    self.appState = appState
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    super.init()

    statusItem.button?.image = Self.makeIcon()
    statusItem.button?.setAccessibilityLabel("Timi")

    let menu = NSMenu()
    menu.delegate = self

    toggleItem.action = #selector(toggleVisibility)
    toggleItem.target = self
    menu.addItem(toggleItem)

    let settingsItem = NSMenuItem(
      title: "Réglages…",
      action: #selector(openSettings),
      keyEquivalent: ","
    )
    settingsItem.target = self
    menu.addItem(settingsItem)

    menu.addItem(.separator())

    let quitItem = NSMenuItem(
      title: "Quitter Timi",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    menu.addItem(quitItem)

    statusItem.menu = menu
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    toggleItem.title = appState.isVisible ? "Masquer Timi" : "Afficher Timi"
  }

  @objc
  private func toggleVisibility() {
    appState.isVisible.toggle()
  }

  @objc
  private func openSettings() {
    NSApp.activate()
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
  }

  /// Template image (the system tints it) of Timi's face seen from the front:
  /// two vertical capsules, same proportions as `EyeProjection`.
  private static func makeIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
      let scale: CGFloat = 18 / 72 * 1.5
      let eyeWidth = EyeProjection.eyeWidth * 72 * scale
      let eyeHeight = EyeProjection.eyeHeight * 72 * scale
      let centerOffset = sin(EyeProjection.eyeSeparation * .pi / 180) * 52 * scale
      NSColor.black.setFill()
      for sign in [CGFloat(-1), CGFloat(1)] {
        let eye = CGRect(
          x: rect.midX + sign * centerOffset - eyeWidth / 2,
          y: rect.midY - eyeHeight / 2,
          width: eyeWidth,
          height: eyeHeight
        )
        NSBezierPath(roundedRect: eye, xRadius: eyeWidth / 2, yRadius: eyeWidth / 2).fill()
      }
      return true
    }
    image.isTemplate = true
    return image
  }
}
