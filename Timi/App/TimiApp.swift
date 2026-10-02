import SwiftUI

@main
struct TimiApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      SettingsView(appState: appDelegate.appState)
    }
  }
}
