import AppKit
import Combine
import Foundation
import FoundationModels

@MainActor
final class DictationCoordinator: ObservableObject {
  enum Destination {
    case global
    case conversation
  }

  @Published private(set) var phase: DictationPhase = .idle
  @Published private(set) var meterLevels = Array(repeating: Float.zero, count: 9)
  @Published private(set) var startedAt: Date?
  @Published private(set) var isSilent = false
  @Published private(set) var rawTranscript = ""

  let speechInput = SpeechInputController()
  let store: DictationStore

  var temporaryVisibilityChange: ((Bool) -> Void)?
  var onConversationTranscript: ((String) -> Void)?

  private let appState: AppState
  private let insertionService = TextInsertionService()
  private var destination = Destination.global
  private var lastBufferDate: Date?
  private var lastAudibleDate: Date?
  private var watchdogTask: Task<Void, Never>?
  private var preparedRefinementSession: LanguageModelSession?
  private var uncertainAlternatives: [String] = []

  init(appState: AppState, store: DictationStore) {
    self.appState = appState
    self.store = store

    speechInput.onTranscriptChange = { [weak self] transcript in
      guard let self else { return }
      rawTranscript = transcript
      if destination == .conversation { onConversationTranscript?(transcript) }
    }
    speechInput.onMeterChange = { [weak self] snapshot in
      self?.receive(snapshot)
    }
    speechInput.onFinished = { [weak self] transcript in
      guard let self else { return }
      Task { await self.finish(transcript: transcript) }
    }
    speechInput.onFailure = { [weak self] message, transcript in
      self?.fail(message, recoverableText: transcript)
    }
    speechInput.onAlternativesChange = { [weak self] alternatives in
      guard let self else { return }
      uncertainAlternatives = Array(alternatives.prefix(2))
    }
  }

  var isListening: Bool { phase == .listening || phase == .preparing }

  func toggleGlobal() {
    if phase.isActive {
      stop()
    } else {
      start(destination: .global)
    }
  }

  func start(destination: Destination) {
    guard !phase.isActive else { return }
    self.destination = destination
    rawTranscript = ""
    uncertainAlternatives = []
    meterLevels = Array(repeating: 0, count: 9)
    isSilent = false
    let now = Date()
    startedAt = now
    lastBufferDate = now
    lastAudibleDate = now
    phase = .preparing

    if destination == .global {
      temporaryVisibilityChange?(true)
      announce("Début de la dictée")
      preparedRefinementSession = makeRefinementSession()
    }

    speechInput.start(
      locale: appState.dictationLanguage.locale,
      contextualStrings: store.contextualTerms(
        for: appState.dictationLanguage.locale.identifier
      )
    )
    watchdogTask?.cancel()
    watchdogTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled, let self, self.phase.isActive else { return }
        if self.speechInput.isRecording, let last = self.lastBufferDate,
           Date().timeIntervalSince(last) > 1.5 {
          self.fail("Micro interrompu", recoverableText: self.rawTranscript)
          self.speechInput.stop()
          return
        }
      }
    }

    Task { [weak self] in
      while !Task.isCancelled, let self, self.phase == .preparing {
        try? await Task.sleep(for: .milliseconds(50))
        if self.speechInput.isRecording { self.phase = .listening }
      }
    }
  }

  func stop() {
    guard phase == .listening || phase == .preparing else { return }
    phase = .finalizing
    watchdogTask?.cancel()
    announce("Arrêt de la dictée")
    speechInput.stop()
  }

  private func receive(_ snapshot: AudioMeterSnapshot) {
    lastBufferDate = snapshot.lastBufferDate
    meterLevels.removeFirst()
    meterLevels.append(snapshot.level)
    if snapshot.level > 0.08 {
      lastAudibleDate = snapshot.lastBufferDate
      isSilent = false
    } else if let lastAudibleDate,
              snapshot.lastBufferDate.timeIntervalSince(lastAudibleDate) >= 3,
              !isSilent {
      isSilent = true
      announce("Aucun son détecté")
    }
  }

  private func finish(transcript: String) async {
    watchdogTask?.cancel()
    if case .failed = phase { return }
    guard destination == .global else {
      preparedRefinementSession = nil
      phase = .idle
      startedAt = nil
      return
    }

    let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else {
      fail("Aucun texte reconnu", recoverableText: "")
      return
    }

    phase = .refining
    let language = appState.dictationLanguage.locale.identifier
    let rules = store.corrections.filter { $0.language == language || $0.language.isEmpty }
    let context = insertionService.focusedContext().surroundingText
    let refined = await refine(raw, language: language, context: context, rules: rules)
    preparedRefinementSession = nil

    phase = .inserting
    let result = await insertionService.insertOrCopy(refined)
    store.addRecord(DictationRecord(
      language: language,
      rawText: raw,
      refinedText: refined
    ))
    phase = .succeeded(result)
    announce(result == .pasted ? "Texte collé" : "Texte copié")
    temporaryVisibilityChange?(false)
    try? await Task.sleep(for: .seconds(1))
    if case .succeeded = phase { reset() }
  }

  private func refine(
    _ raw: String,
    language: String,
    context: String,
    rules: [CorrectionRule]
  ) async -> String {
    let fallback = DictationTextCleanup.conservative(raw, rules: rules)
    guard appState.dictationCleanupEnabled,
          SystemLanguageModel.default.availability == .available,
          let session = preparedRefinementSession else {
      return fallback
    }

    let corrections = rules.filter(\.isEnabled)
      .map { "\($0.heard) → \($0.replacement)" }
      .joined(separator: "\n")
    let terms = store.contextualTerms(for: language).joined(separator: ", ")
    let alternatives = uncertainAlternatives.joined(separator: " | ")
    let prompt = """
      Texte dicté :
      \(raw)

      Contexte autour du curseur (ne pas le reproduire) :
      \(context)

      Corrections exactes :
      \(corrections)

      Alternatives de reconnaissance possibles :
      \(alternatives)

      Termes préférés : \(terms)
      """

    let generation = Task { @MainActor in
      try await session.respond(to: prompt).content
    }
    let timeout = Task { @MainActor in
      try await Task.sleep(for: .seconds(8))
      generation.cancel()
    }
    defer { timeout.cancel() }
    do {
      let candidate = try await generation.value.trimmingCharacters(in: .whitespacesAndNewlines)
      return DictationTextCleanup.isAcceptable(refined: candidate, comparedTo: raw)
        ? candidate : fallback
    } catch {
      return fallback
    }
  }

  private func makeRefinementSession() -> LanguageModelSession? {
    guard SystemLanguageModel.default.availability == .available else { return nil }
    return LanguageModelSession(instructions: """
      Tu nettoies fidèlement une dictée. Retourne uniquement le texte final, sans commentaire.
      Supprime hésitations, répétitions, bégaiements et faux départs. Corrige la ponctuation et
      les erreurs probables, sans changer le sens, le ton ni les réserves. Préserve exactement
      noms, nombres, URL, chemins, code et termes techniques. Ne complète jamais les idées.
      """)
  }

  private func fail(_ message: String, recoverableText: String) {
    watchdogTask?.cancel()
    preparedRefinementSession = nil
    rawTranscript = recoverableText
    if !recoverableText.isEmpty {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(recoverableText, forType: .string)
    }
    phase = .failed(message)
    temporaryVisibilityChange?(false)
    announce(message)
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(2))
      guard let self, case .failed = self.phase else { return }
      self.reset()
    }
  }

  private func reset() {
    phase = .idle
    startedAt = nil
    lastBufferDate = nil
    lastAudibleDate = nil
    isSilent = false
    meterLevels = Array(repeating: 0, count: 9)
  }

  private func announce(_ message: String) {
    NSAccessibility.post(
      element: NSApp!,
      notification: .announcementRequested,
      userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]
    )
  }
}
