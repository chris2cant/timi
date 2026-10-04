import AVFoundation
import NaturalLanguage

struct SpeechVoiceOption: Identifiable, Hashable {
  let identifier: String
  let name: String
  let language: String
  let quality: AVSpeechSynthesisVoiceQuality

  var id: String { identifier }

  var localizedLanguage: String {
    Locale.current.localizedString(forIdentifier: language) ?? language
  }

  var qualityTitle: String {
    switch quality {
    case .premium:
      "Premium"
    case .enhanced:
      "Enhanced"
    case .default:
      "Standard"
    @unknown default:
      "Unknown quality"
    }
  }
}

@MainActor
final class SpeechOutputController: NSObject, @preconcurrency AVSpeechSynthesizerDelegate {
  var isSpeakingDidChange: ((Bool) -> Void)?

  private lazy var synthesizer: AVSpeechSynthesizer = {
    let synthesizer = AVSpeechSynthesizer()
    synthesizer.delegate = self
    return synthesizer
  }()
  private var activeUtterance: AVSpeechUtterance?

  func speak(_ text: String, preferredVoiceIdentifier: String? = nil) {
    let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else { return }

    stop()

    let utterance = AVSpeechUtterance(string: content)
    utterance.voice = Self.voice(
      for: content,
      preferredVoiceIdentifier: preferredVoiceIdentifier
    )
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    activeUtterance = utterance
    isSpeakingDidChange?(true)
    synthesizer.speak(utterance)
  }

  func stop() {
    guard activeUtterance != nil || synthesizer.isSpeaking || synthesizer.isPaused else { return }
    activeUtterance = nil
    synthesizer.stopSpeaking(at: .immediate)
    isSpeakingDidChange?(false)
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    guard utterance === activeUtterance else { return }
    activeUtterance = nil
    isSpeakingDidChange?(false)
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    guard utterance === activeUtterance else { return }
    activeUtterance = nil
    isSpeakingDidChange?(false)
  }

  static func availableVoices(for languageCode: String) -> [SpeechVoiceOption] {
    eligibleVoices(for: languageCode)
      .map {
        SpeechVoiceOption(
          identifier: $0.identifier,
          name: $0.name,
          language: $0.language,
          quality: $0.quality
        )
      }
      .sorted { lhs, rhs in
        let qualityComparison = qualityRank(lhs.quality) - qualityRank(rhs.quality)
        if qualityComparison != 0 {
          return qualityComparison > 0
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
      }
  }

  static func automaticVoice(for text: String) -> SpeechVoiceOption? {
    guard let voice = bestAvailableVoice(for: text) else { return nil }
    return SpeechVoiceOption(
      identifier: voice.identifier,
      name: voice.name,
      language: voice.language,
      quality: voice.quality
    )
  }

  private static func voice(
    for text: String,
    preferredVoiceIdentifier: String?
  ) -> AVSpeechSynthesisVoice? {
    let languageCode = detectedLanguageCode(for: text)
    if let preferredVoiceIdentifier,
       let preferredVoice = AVSpeechSynthesisVoice(identifier: preferredVoiceIdentifier),
       Locale.Language(identifier: preferredVoice.language).languageCode?.identifier == languageCode {
      return preferredVoice
    }
    return bestAvailableVoice(for: text)
  }

  private static func bestAvailableVoice(for text: String) -> AVSpeechSynthesisVoice? {
    let languageCode = detectedLanguageCode(for: text)
    guard let languageCode else { return nil }

    let regionalLanguage = Locale.preferredLanguages.first {
      Locale.Language(identifier: $0).languageCode?.identifier == languageCode
    }
    let systemDefaultVoice = AVSpeechSynthesisVoice(language: regionalLanguage ?? languageCode)

    let voices = eligibleVoices(for: languageCode)

    let regionalVoices = voices.filter { voice in
      guard let regionalLanguage else { return false }
      return Locale(identifier: voice.language).language.region
        == Locale(identifier: regionalLanguage).language.region
    }

    let candidates = regionalVoices.isEmpty ? voices : regionalVoices
    guard let highestQuality = candidates.map({ qualityRank($0.quality) }).max() else {
      return systemDefaultVoice
    }

    let bestVoices = candidates.filter { qualityRank($0.quality) == highestQuality }
    return bestVoices.first { $0.identifier == systemDefaultVoice?.identifier }
      ?? bestVoices.first
  }

  private static func detectedLanguageCode(for text: String) -> String? {
    NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue
      ?? Locale.current.language.languageCode?.identifier
  }

  private static func eligibleVoices(for languageCode: String) -> [AVSpeechSynthesisVoice] {
    AVSpeechSynthesisVoice.speechVoices().filter { voice in
      Locale.Language(identifier: voice.language).languageCode?.identifier == languageCode
        && !voice.voiceTraits.contains(.isNoveltyVoice)
        && !voice.voiceTraits.contains(.isPersonalVoice)
    }
  }

  private static func qualityRank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
    switch quality {
    case .premium:
      3
    case .enhanced:
      2
    case .default:
      1
    @unknown default:
      0
    }
  }
}
