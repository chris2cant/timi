import Combine
import CoreGraphics
import Foundation

enum DictationLanguage: String, CaseIterable, Identifiable {
  case automatic
  case french = "fr-FR"
  case english = "en-US"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .automatic: "Automatique — langue du Mac"
    case .french: "Français"
    case .english: "English"
    }
  }

  var locale: Locale {
    switch self {
    case .automatic: .current
    case .french, .english: Locale(identifier: rawValue)
    }
  }
}

enum DictationShortcut: String, CaseIterable, Identifiable {
  case controlSpace
  case controlOptionSpace
  case commandShiftSpace

  var id: String { rawValue }

  var title: String {
    switch self {
    case .controlSpace: "⌃ Espace"
    case .controlOptionSpace: "⌃⌥ Espace"
    case .commandShiftSpace: "⌘⇧ Espace"
    }
  }

  var eventFlags: CGEventFlags {
    switch self {
    case .controlSpace: [.maskControl]
    case .controlOptionSpace: [.maskControl, .maskAlternate]
    case .commandShiftSpace: [.maskCommand, .maskShift]
    }
  }
}

enum AutoHideMode: String, CaseIterable, Identifiable {
  case off
  case hidden
  case peek

  var id: String { rawValue }

  /// Points of the mascot that stay on screen when hidden.
  static let peekStrip: CGFloat = 4

  var visibleStrip: CGFloat {
    self == .peek ? Self.peekStrip : 0
  }

  var title: String {
    switch self {
    case .off: "Désactivé"
    case .hidden: "Masquer complètement"
    case .peek: "Masquer (\(Int(Self.peekStrip)) pt visibles)"
    }
  }
}

@MainActor
final class AppState: ObservableObject {
  static let defaultAutoHideDelay: TimeInterval = 0.5
  static let autoHideDelayRange: ClosedRange<TimeInterval> = 0...10

  private enum Keys {
    static let mascotPosition = "mascotPosition"
    static let mascotOffsetX = "mascotOffsetX"
    static let mascotOffsetY = "mascotOffsetY"
    static let mascotIsVisible = "mascotIsVisible"
    static let mascotDisplayUUID = "mascotDisplayUUID"
    static let speechVoiceIdentifier = "speechVoiceIdentifier"
    static let dictationLanguage = "dictationLanguage"
    static let dictationCleanupEnabled = "dictationCleanupEnabled"
    static let dictationShortcut = "dictationShortcut"
    static let autoHideMode = "autoHideMode"
    static let autoHideDelay = "autoHideDelay"
  }

  @Published private(set) var position: MascotPosition
  @Published private(set) var offset: CGSize
  @Published private(set) var displayUUID: String?
  @Published var speechVoiceIdentifier: String? {
    didSet {
      if let speechVoiceIdentifier {
        defaults.set(speechVoiceIdentifier, forKey: Keys.speechVoiceIdentifier)
      } else {
        defaults.removeObject(forKey: Keys.speechVoiceIdentifier)
      }
    }
  }
  @Published var dictationLanguage: DictationLanguage {
    didSet {
      defaults.set(dictationLanguage.rawValue, forKey: Keys.dictationLanguage)
    }
  }
  @Published var dictationCleanupEnabled: Bool {
    didSet {
      defaults.set(dictationCleanupEnabled, forKey: Keys.dictationCleanupEnabled)
    }
  }
  @Published var dictationShortcut: DictationShortcut {
    didSet {
      defaults.set(dictationShortcut.rawValue, forKey: Keys.dictationShortcut)
      dictationShortcutDidChange?(dictationShortcut)
    }
  }
  @Published var isVisible: Bool {
    didSet {
      defaults.set(isVisible, forKey: Keys.mascotIsVisible)
      visibilityDidChange?(isVisible)
    }
  }
  @Published var autoHideDelay: TimeInterval {
    didSet {
      defaults.set(autoHideDelay, forKey: Keys.autoHideDelay)
      autoHideDelayDidChange?(autoHideDelay)
    }
  }
  @Published var autoHideMode: AutoHideMode {
    didSet {
      defaults.set(autoHideMode.rawValue, forKey: Keys.autoHideMode)
      autoHideModeDidChange?(autoHideMode)
    }
  }

  private let defaults: UserDefaults
  var placementDidChange: ((MascotPosition, CGSize, String?) -> Void)?
  var visibilityDidChange: ((Bool) -> Void)?
  var autoHideModeDidChange: ((AutoHideMode) -> Void)?
  var autoHideDelayDidChange: ((TimeInterval) -> Void)?
  var dictationShortcutDidChange: ((DictationShortcut) -> Void)?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let storedValue = defaults.string(forKey: Keys.mascotPosition)
    position = storedValue.flatMap(MascotPosition.init(rawValue:)) ?? .bottomRight
    offset = CGSize(
      width: defaults.double(forKey: Keys.mascotOffsetX),
      height: defaults.double(forKey: Keys.mascotOffsetY)
    )
    displayUUID = defaults.string(forKey: Keys.mascotDisplayUUID)
    speechVoiceIdentifier = defaults.string(forKey: Keys.speechVoiceIdentifier)
    dictationLanguage = defaults.string(forKey: Keys.dictationLanguage)
      .flatMap(DictationLanguage.init(rawValue:)) ?? .french
    dictationCleanupEnabled = defaults.object(forKey: Keys.dictationCleanupEnabled) as? Bool ?? true
    dictationShortcut = defaults.string(forKey: Keys.dictationShortcut)
      .flatMap(DictationShortcut.init(rawValue:)) ?? .controlSpace
    isVisible = defaults.object(forKey: Keys.mascotIsVisible) as? Bool ?? true
    autoHideMode = defaults.string(forKey: Keys.autoHideMode)
      .flatMap(AutoHideMode.init(rawValue:)) ?? .off
    autoHideDelay = defaults.object(forKey: Keys.autoHideDelay) as? Double ?? Self.defaultAutoHideDelay
  }

  func select(_ position: MascotPosition) {
    self.position = position
    offset = .zero
    persistPlacement()
  }

  func updateOffset(_ offset: CGSize) {
    updatePlacement(offset: offset, displayUUID: displayUUID)
  }

  func updatePlacement(offset: CGSize, displayUUID: String?) {
    self.offset = offset
    self.displayUUID = displayUUID
    persistPlacement()
  }

  func resetOffset() {
    updateOffset(.zero)
  }

  private func persistPlacement() {
    defaults.set(position.rawValue, forKey: Keys.mascotPosition)
    defaults.set(offset.width, forKey: Keys.mascotOffsetX)
    defaults.set(offset.height, forKey: Keys.mascotOffsetY)
    if let displayUUID {
      defaults.set(displayUUID, forKey: Keys.mascotDisplayUUID)
    } else {
      defaults.removeObject(forKey: Keys.mascotDisplayUUID)
    }
    placementDidChange?(position, offset, displayUUID)
  }
}
