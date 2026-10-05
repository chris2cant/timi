import SwiftUI

@main
struct TimiApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      SettingsView(
        appState: appDelegate.appState,
        dictationStore: appDelegate.dictationStore,
        shortcutMonitor: appDelegate.shortcutMonitor,
        updateManager: appDelegate.updateManager,
        requestShortcutPermission: appDelegate.requestGlobalShortcutPermission,
        testGlobalDictation: appDelegate.testGlobalDictation
      )
    }
    .commands {
      CommandGroup(after: .appInfo) {
        Button("Rechercher des mises à jour…") { appDelegate.updateManager.checkForUpdates() }
      }
    }
  }
}
