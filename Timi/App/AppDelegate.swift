import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let appState = AppState()
  private var mascotWindowController: MascotWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    configureApplicationIcon()

    let controller = MascotWindowController()
    mascotWindowController = controller

    appState.placementDidChange = { [weak controller] position, offset, displayUUID in
      controller?.move(to: position, offset: offset, displayUUID: displayUUID)
    }
    controller.offsetDidChange = { [weak appState] offset, displayUUID in
      appState?.updatePlacement(offset: offset, displayUUID: displayUUID)
    }
    appState.visibilityDidChange = { [weak controller] isVisible in
      controller?.setVisible(isVisible)
    }

    if appState.isVisible {
      controller.show(
        at: appState.position,
        offset: appState.offset,
        displayUUID: appState.displayUUID
      )
    } else {
      controller.move(
        to: appState.position,
        offset: appState.offset,
        displayUUID: appState.displayUUID
      )
    }
  }

  private func configureApplicationIcon() {
    guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
          let icon = NSImage(contentsOf: iconURL) else {
      return
    }
    NSApplication.shared.applicationIconImage = icon
  }
}
