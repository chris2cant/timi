import Foundation

enum DictationPhase: Equatable, Sendable {
  case idle
  case preparing
  case listening
  case finalizing
  case refining
  case inserting
  case succeeded(DictationInsertionResult)
  case failed(String)

  var isActive: Bool {
    switch self {
    case .preparing, .listening, .finalizing, .refining, .inserting: true
    case .idle, .succeeded, .failed: false
    }
  }
}

enum DictationInsertionResult: String, Codable, Equatable, Sendable {
  case pasted
  case copied
}

struct AudioMeterSnapshot: Equatable, Sendable {
  let level: Float
  let lastBufferDate: Date
}

enum VocabularySource: String, Codable, CaseIterable, Sendable {
  case manual
  case correction
}

struct VocabularyTerm: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  var term: String
  var language: String
  var source: VocabularySource
  var isEnabled: Bool
  var usageCount: Int
  var lastUsedAt: Date?

  init(
    id: UUID = UUID(),
    term: String,
    language: String,
    source: VocabularySource = .manual,
    isEnabled: Bool = true,
    usageCount: Int = 0,
    lastUsedAt: Date? = nil
  ) {
    self.id = id
    self.term = term
    self.language = language
    self.source = source
    self.isEnabled = isEnabled
    self.usageCount = usageCount
    self.lastUsedAt = lastUsedAt
  }
}

struct CorrectionRule: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  var heard: String
  var replacement: String
  var language: String
  var isEnabled: Bool
  var applicationCount: Int

  init(
    id: UUID = UUID(),
    heard: String,
    replacement: String,
    language: String,
    isEnabled: Bool = true,
    applicationCount: Int = 0
  ) {
    self.id = id
    self.heard = heard
    self.replacement = replacement
    self.language = language
    self.isEnabled = isEnabled
    self.applicationCount = applicationCount
  }
}

struct DictationRecord: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let date: Date
  let language: String
  let rawText: String
  var refinedText: String
  var correction: String?

  init(
    id: UUID = UUID(),
    date: Date = .now,
    language: String,
    rawText: String,
    refinedText: String,
    correction: String? = nil
  ) {
    self.id = id
    self.date = date
    self.language = language
    self.rawText = rawText
    self.refinedText = refinedText
    self.correction = correction
  }
}

enum DictationTextCleanup {
  static func exactCorrections(
    in text: String,
    rules: [CorrectionRule]
  ) -> String {
    rules.filter(\.isEnabled).reduce(text) { result, rule in
      result.replacingOccurrences(
        of: "\\b\(NSRegularExpression.escapedPattern(for: rule.heard))\\b",
        with: rule.replacement,
        options: [.regularExpression, .caseInsensitive]
      )
    }
  }

  static func conservative(_ text: String, rules: [CorrectionRule]) -> String {
    var result = exactCorrections(in: text, rules: rules)
    result = result.replacingOccurrences(
      of: #"\b(euh+|heu+|hum+)\b[ ,]*"#,
      with: "",
      options: [.regularExpression, .caseInsensitive]
    )
    result = result.replacingOccurrences(
      of: #"[ \t]{2,}"#,
      with: " ",
      options: .regularExpression
    )
    result = result.replacingOccurrences(
      of: #"\s+([,.;:!?])"#,
      with: "$1",
      options: .regularExpression
    )
    result = result.trimmingCharacters(in: .whitespacesAndNewlines)
    if let first = result.first, first.isLowercase {
      result.replaceSubrange(result.startIndex...result.startIndex, with: String(first).uppercased())
    }
    return result
  }

  static func isAcceptable(refined: String, comparedTo raw: String) -> Bool {
    let refined = refined.trimmingCharacters(in: .whitespacesAndNewlines)
    let raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !refined.isEmpty, !raw.isEmpty else { return false }
    let ratio = Double(refined.count) / Double(raw.count)
    guard (0.55...1.65).contains(ratio) else { return false }
    let conversationalPrefixes = ["bien sûr", "voici", "certainement", "je peux"]
    return !conversationalPrefixes.contains { refined.lowercased().hasPrefix($0) }
  }
}

struct AudioLevelSmoother: Sendable {
  private(set) var level: Float = 0
  let attack: Float
  let release: Float

  init(attack: Float = 0.5, release: Float = 0.16) {
    self.attack = attack
    self.release = release
  }

  mutating func push(rms: Float) -> Float {
    let normalized = min(max((rms + 55) / 45, 0), 1)
    let factor = normalized > level ? attack : release
    level += (normalized - level) * factor
    return level
  }

  mutating func reset() {
    level = 0
  }
}

enum AudioLevelMeter {
  static func rootMeanSquare(_ samples: UnsafeBufferPointer<Float>) -> Float {
    guard !samples.isEmpty else { return -80 }
    let sum = samples.reduce(Float.zero) { $0 + $1 * $1 }
    let rms = sqrt(sum / Float(samples.count))
    return rms > 0 ? 20 * log10(rms) : -80
  }
}
