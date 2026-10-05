import AppKit
import Combine
import Sparkle

/// Owns the Sparkle updater for the whole app lifetime. Sparkle checks in the background
/// (see `SUEnableAutomaticChecks`) and always asks the user before installing anything.
@MainActor
final class UpdateManager: ObservableObject {
  @Published private(set) var canCheckForUpdates = false

  private let controller: SPUStandardUpdaterController
  private var cancellable: AnyCancellable?

  init() {
    controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
    cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] value in self?.canCheckForUpdates = value }
  }

  var automaticallyChecksForUpdates: Bool {
    get { controller.updater.automaticallyChecksForUpdates }
    set {
      objectWillChange.send()
      controller.updater.automaticallyChecksForUpdates = newValue
    }
  }

  /// The mascot panel never activates the app, so bring Timi forward or Sparkle's window
  /// could appear behind other apps.
  func checkForUpdates() {
    NSApp.activate()
    controller.checkForUpdates(nil)
  }
}
