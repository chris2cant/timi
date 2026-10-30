import AppKit
import os

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
  private let sessionStore = ClaudeSessionStore()
  private var hookServer: ClaudeHookServer?
  private var sessionMascotsController: SessionMascotsWindowController?
  private let logger = Logger(subsystem: "io.github.chris2cant.Timi", category: "ClaudeHooks")

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
    appState.visibilityDidChange = { [weak self, weak controller] isVisible in
      controller?.setVisible(isVisible)
      self?.updateSessionMascotsVisibility()
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
    startClaudeSessions(mascotController: controller)

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
    if let placement = controller.displayedMascotPlacement {
      sessionMascotsController?.updateAnchor(mascotFrame: placement.frame, screen: placement.screen)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    sessionStore.stopLivenessChecks()
    hookServer?.stop()
  }

  func requestGlobalShortcutPermission() {
    shortcutMonitor.requestPermission()
  }

  func testGlobalDictation() {
    dictationCoordinator.toggleGlobal()
  }

  private func startClaudeSessions(mascotController: MascotWindowController) {
    // The test host must not take the socket of an installed Timi running alongside.
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
      let server = ClaudeHookServer(onRequest: { [weak sessionStore] request in
        sessionStore?.handle(request)
      })
      do {
        try server.start()
      } catch {
        logger.error("Claude hook server failed to start: \(error.localizedDescription, privacy: .public)")
      }
      hookServer = server
    }
    sessionStore.startLivenessChecks()

    let sessionsController = SessionMascotsWindowController(store: sessionStore)
    sessionMascotsController = sessionsController
    updateSessionMascotsVisibility()
    mascotController.mascotFrameDidChange = { [weak sessionsController] frame, screen in
      sessionsController?.updateAnchor(mascotFrame: frame, screen: screen)
    }
    appState.showsClaudeSessionsDidChange = { [weak self] _ in
      self?.updateSessionMascotsVisibility()
    }
  }

  private func updateSessionMascotsVisibility() {
    sessionMascotsController?.setVisible(appState.isVisible && appState.showsClaudeSessions)
  }

  private func configureApplicationIcon() {
    guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
          let icon = NSImage(contentsOf: iconURL) else {
      return
    }
    NSApplication.shared.applicationIconImage = icon
  }
}
