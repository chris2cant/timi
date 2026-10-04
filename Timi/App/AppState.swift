import Combine
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

@MainActor
final class AppState: ObservableObject {
  private enum Keys {
    static let mascotPosition = "mascotPosition"
    static let mascotOffsetX = "mascotOffsetX"
    static let mascotOffsetY = "mascotOffsetY"
    static let mascotIsVisible = "mascotIsVisible"
    static let mascotDisplayUUID = "mascotDisplayUUID"
    static let speechVoiceIdentifier = "speechVoiceIdentifier"
    static let dictationLanguage = "dictationLanguage"
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
  @Published var isVisible: Bool {
    didSet {
      defaults.set(isVisible, forKey: Keys.mascotIsVisible)
      visibilityDidChange?(isVisible)
    }
  }

  private let defaults: UserDefaults
  var placementDidChange: ((MascotPosition, CGSize, String?) -> Void)?
  var visibilityDidChange: ((Bool) -> Void)?

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
    isVisible = defaults.object(forKey: Keys.mascotIsVisible) as? Bool ?? true
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
