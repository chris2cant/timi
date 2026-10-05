import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let appState = AppState()
  let dictationStore: DictationStore
  let dictationCoordinator: DictationCoordinator
  private var mascotWindowController: MascotWindowController?
  private var menuBarController: MenuBarController?
  let shortcutMonitor = GlobalShortcutMonitor()
  let updateManager = UpdateManager()
  private var wasHiddenBeforeDictation = false

  override init() {
    let store = DictationStore()
    dictationStore = store
    dictationCoordinator = DictationCoordinator(appState: appState, store: store)
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    configureApplicationIcon()

    let controller = MascotWindowController(
      appState: appState,
      dictationCoordinator: dictationCoordinator
    )
    mascotWindowController = controller
    menuBarController = MenuBarController(appState: appState, updateManager: updateManager)

    appState.autoHideModeDidChange = { [weak controller] mode in
      controller?.setAutoHideMode(mode)
    }
    appState.autoHideDelayDidChange = { [weak controller] delay in
      controller?.setAutoHideDelay(delay)
    }
    controller.setAutoHideDelay(appState.autoHideDelay)
    controller.setAutoHideMode(appState.autoHideMode)
    appState.placementDidChange = { [weak controller] position, offset, displayUUID in
      controller?.move(to: position, offset: offset, displayUUID: displayUUID)
    }
    controller.offsetDidChange = { [weak appState] offset, displayUUID in
      appState?.updatePlacement(offset: offset, displayUUID: displayUUID)
    }
    appState.visibilityDidChange = { [weak controller] isVisible in
      controller?.setVisible(isVisible)
    }
    dictationCoordinator.temporaryVisibilityChange = { [weak self, weak controller] active in
      guard let self, let controller else { return }
      if active {
        self.wasHiddenBeforeDictation = !self.appState.isVisible
        if self.wasHiddenBeforeDictation { controller.setVisible(true) }
      } else if self.wasHiddenBeforeDictation {
        controller.setVisible(false)
        self.wasHiddenBeforeDictation = false
      }
    }
    shortcutMonitor.onAction = { [weak dictationCoordinator] action in
      guard let coordinator = dictationCoordinator else { return }
      switch action {
      case .toggle:
        coordinator.toggleGlobal()
      case .beginHold:
        coordinator.start(destination: .global)
      case .endHold:
        coordinator.stop()
      }
    }
    shortcutMonitor.shortcut = appState.dictationShortcut
    appState.dictationShortcutDidChange = { [weak shortcutMonitor] shortcut in
      shortcutMonitor?.shortcut = shortcut
    }
    shortcutMonitor.start()

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

  func requestGlobalShortcutPermission() {
    shortcutMonitor.requestPermission()
  }

  func testGlobalDictation() {
    dictationCoordinator.toggleGlobal()
  }

  private func configureApplicationIcon() {
    guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
          let icon = NSImage(contentsOf: iconURL) else {
      return
    }
    NSApplication.shared.applicationIconImage = icon
  }
}
