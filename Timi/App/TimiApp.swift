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
        requestShortcutPermission: appDelegate.requestGlobalShortcutPermission,
        testGlobalDictation: appDelegate.testGlobalDictation
      )
    }
  }
}
