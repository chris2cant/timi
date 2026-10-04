import Combine
import Foundation
import FoundationModels

struct ChatMessage: Identifiable, Equatable, Sendable {
  enum Role: Sendable {
    case user
    case timi
  }

  let id: UUID
  let role: Role
  var content: String

  init(id: UUID = UUID(), role: Role, content: String) {
    self.id = id
    self.role = role
    self.content = content
  }
}

@MainActor
final class ChatState: ObservableObject {
  @Published var input = ""
  @Published private(set) var messages: [ChatMessage] = []
  @Published private(set) var availabilityMessage: String?
  @Published private(set) var isResponding = false
  @Published private(set) var isSpeaking = false

  let speechInput: SpeechInputController
  private let dictationCoordinator: DictationCoordinator
  private let speechOutput = SpeechOutputController()
  private let appState: AppState

  private var session: LanguageModelSession?
  private var inputBeforeDictation = ""

  private var responseTask: Task<Void, Never>?

  var canSend: Bool {
    !isResponding && !speechInput.isActive
      && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  init(appState: AppState, dictationCoordinator: DictationCoordinator) {
    self.appState = appState
    self.dictationCoordinator = dictationCoordinator
    speechInput = dictationCoordinator.speechInput
    dictationCoordinator.onConversationTranscript = { [weak self] transcript in
      guard let self else { return }
      let separator = inputBeforeDictation.isEmpty || transcript.isEmpty ? "" : " "
      input = inputBeforeDictation + separator + transcript
    }
    speechOutput.isSpeakingDidChange = { [weak self] isSpeaking in
      self?.isSpeaking = isSpeaking
    }
    refreshAvailability()
  }

  deinit {
    responseTask?.cancel()
  }

  func refreshAvailability() {
    switch SystemLanguageModel.default.availability {
    case .available:
      availabilityMessage = nil
    case .unavailable(.appleIntelligenceNotEnabled):
      availabilityMessage = "Active Apple Intelligence dans Réglages Système pour discuter avec Timi."
    case .unavailable(.deviceNotEligible):
      availabilityMessage = "Ce Mac n’est pas compatible avec Apple Intelligence."
    case .unavailable(.modelNotReady):
      availabilityMessage = "Le modèle Apple Intelligence est encore en préparation. Réessaie bientôt."
    case .unavailable:
      availabilityMessage = "Apple Intelligence n’est pas disponible pour le moment."
    }
  }

  func send() {
    let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !question.isEmpty, !isResponding else { return }

    refreshAvailability()
    guard availabilityMessage == nil else { return }

    speechOutput.stop()
    input = ""
    messages.append(ChatMessage(role: .user, content: question))
    let responseID = UUID()
    messages.append(ChatMessage(id: responseID, role: .timi, content: ""))
    isResponding = true

    responseTask?.cancel()
    responseTask = Task { [weak self] in
      guard let self else { return }
      await self.generateResponse(to: question, messageID: responseID)
    }
  }

  func toggleDictation() {
    if !speechInput.isActive {
      inputBeforeDictation = input.trimmingCharacters(in: .whitespacesAndNewlines)
      dictationCoordinator.start(destination: .conversation)
    } else {
      dictationCoordinator.stop()
    }
  }

  func stopDictation() {
    if speechInput.isActive { dictationCoordinator.stop() }
  }

  func stopSpeaking() {
    speechOutput.stop()
  }

  private func modelSession() -> LanguageModelSession {
    if let session {
      return session
    }

    let session = LanguageModelSession(instructions: """
      Tu es Timi, un petit compagnon de bureau macOS amical, calme et concis.
      Réponds dans la langue utilisée par la personne.
      Donne des réponses utiles et brèves, sans prétendre avoir consulté Internet.
      Si tu ne sais pas, dis-le simplement.
      """)
    self.session = session
    return session
  }

  private func generateResponse(to question: String, messageID: UUID) async {
    do {
      let stream = modelSession().streamResponse(to: question)
      for try await snapshot in stream {
        guard !Task.isCancelled else { return }
        updateMessage(id: messageID, content: snapshot.content)
      }

      if messageContent(id: messageID).isEmpty {
        updateMessage(id: messageID, content: "Je n’ai pas réussi à formuler une réponse.")
      }
      isResponding = false
      speechOutput.speak(
        messageContent(id: messageID),
        preferredVoiceIdentifier: appState.speechVoiceIdentifier
      )
    } catch is CancellationError {
      isResponding = false
    } catch {
      finishWithError("Je n’arrive pas à répondre pour le moment. Réessaie dans un instant.", messageID: messageID)
    }
  }

  private func updateMessage(id: UUID, content: String) {
    guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
    messages[index].content = content
  }

  private func messageContent(id: UUID) -> String {
    messages.first(where: { $0.id == id })?.content ?? ""
  }

  private func finishWithError(_ message: String, messageID: UUID) {
    updateMessage(id: messageID, content: message)
    isResponding = false
    speechOutput.speak(
      message,
      preferredVoiceIdentifier: appState.speechVoiceIdentifier
    )
  }
}
