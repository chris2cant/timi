import Combine
import Foundation

@MainActor
final class DictationStore: ObservableObject {
  private struct Payload: Codable {
    var version = 1
    var vocabulary: [VocabularyTerm] = []
    var corrections: [CorrectionRule] = []
    var history: [DictationRecord] = []
  }

  @Published private(set) var vocabulary: [VocabularyTerm] = []
  @Published private(set) var corrections: [CorrectionRule] = []
  @Published private(set) var history: [DictationRecord] = []
  @Published private(set) var loadError: String?

  private let fileURL: URL
  private let calendar: Calendar

  init(fileURL: URL? = nil, calendar: Calendar = .current) {
    self.calendar = calendar
    self.fileURL = fileURL ?? Self.defaultFileURL()
    load()
  }

  func contextualTerms(for language: String, limit: Int = 200) -> [String] {
    vocabulary
      .filter { $0.isEnabled && ($0.language == language || $0.language.isEmpty) }
      .sorted {
        if $0.usageCount != $1.usageCount { return $0.usageCount > $1.usageCount }
        return ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast)
      }
      .prefix(limit)
      .map(\.term)
  }

  func addTerm(_ term: String, language: String, source: VocabularySource = .manual) {
    let value = term.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return }
    if let index = vocabulary.firstIndex(where: {
      $0.language == language && $0.term.caseInsensitiveCompare(value) == .orderedSame
    }) {
      vocabulary[index].isEnabled = true
    } else {
      vocabulary.append(VocabularyTerm(term: value, language: language, source: source))
    }
    save()
  }

  func updateTerm(_ term: VocabularyTerm) {
    guard let index = vocabulary.firstIndex(where: { $0.id == term.id }) else { return }
    vocabulary[index] = term
    save()
  }

  func removeTerms(at offsets: IndexSet) {
    vocabulary.remove(atOffsets: offsets)
    save()
  }

  func addCorrection(heard: String, replacement: String, language: String) {
    let heard = heard.trimmingCharacters(in: .whitespacesAndNewlines)
    let replacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !heard.isEmpty, !replacement.isEmpty, heard != replacement else { return }
    corrections.append(CorrectionRule(heard: heard, replacement: replacement, language: language))
    addTerm(replacement, language: language, source: .correction)
    save()
  }

  func updateCorrection(_ rule: CorrectionRule) {
    guard let index = corrections.firstIndex(where: { $0.id == rule.id }) else { return }
    corrections[index] = rule
    save()
  }

  func removeCorrections(at offsets: IndexSet) {
    corrections.remove(atOffsets: offsets)
    save()
  }

  func addRecord(_ record: DictationRecord, now: Date = .now) {
    history.insert(record, at: 0)
    prune(now: now)
    save()
  }

  func correctRecord(id: UUID, text: String) {
    guard let index = history.firstIndex(where: { $0.id == id }) else { return }
    history[index].correction = text.trimmingCharacters(in: .whitespacesAndNewlines)
    save()
  }

  func clearHistory() {
    history = []
    save()
  }

  func clearVocabulary() {
    vocabulary = []
    corrections = []
    save()
  }

  func prune(now: Date = .now) {
    let cutoff = calendar.date(byAdding: .day, value: -30, to: now) ?? now
    history = Array(history.filter { $0.date >= cutoff }.sorted { $0.date > $1.date }.prefix(100))
  }

  private func load() {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
    do {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      let payload = try decoder.decode(Payload.self, from: Data(contentsOf: fileURL))
      vocabulary = payload.vocabulary
      corrections = payload.corrections
      history = payload.history
      prune()
    } catch {
      loadError = "Le catalogue local est illisible. Il n’a pas été remplacé."
    }
  }

  private func save() {
    do {
      let directory = fileURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      let payload = Payload(vocabulary: vocabulary, corrections: corrections, history: history)
      try encoder.encode(payload).write(to: fileURL, options: .atomic)
      loadError = nil
    } catch {
      loadError = "Impossible d’enregistrer le catalogue local."
    }
  }

  private static func defaultFileURL() -> URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return support.appending(path: "Timi", directoryHint: .isDirectory)
      .appending(path: "dictation-v1.json")
  }
}
