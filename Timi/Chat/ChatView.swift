import SwiftUI

struct ChatView: View {
  @ObservedObject var state: ChatState
  @ObservedObject private var speechInput: SpeechInputController
  let close: () -> Void

  @FocusState private var inputIsFocused: Bool

  init(state: ChatState, close: @escaping () -> Void) {
    self.state = state
    _speechInput = ObservedObject(wrappedValue: state.speechInput)
    self.close = close
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider().opacity(0.45)
      conversation
      Divider().opacity(0.45)
      composer
    }
    .frame(width: ChatWindowController.windowSize.width, height: ChatWindowController.windowSize.height)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .stroke(.white.opacity(0.12), lineWidth: 1)
    }
    .onAppear {
      state.refreshAvailability()
      inputIsFocused = true
    }
    .onExitCommand(perform: closeConversation)
  }

  private var header: some View {
    HStack(spacing: 10) {
      Circle()
        .fill(.black)
        .frame(width: 28, height: 28)
        .overlay {
          HStack(spacing: 6) {
            Circle().fill(.white).frame(width: 5, height: 5)
            Circle().fill(.white).frame(width: 5, height: 5)
          }
        }

      VStack(alignment: .leading, spacing: 1) {
        Text("Timi")
          .font(.headline)
        Text("Apple Intelligence · sur ce Mac")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button(action: state.stopSpeaking) {
        Image(systemName: "speaker.slash.fill")
          .font(.system(size: 11, weight: .semibold))
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.plain)
      .foregroundStyle(state.isSpeaking ? Color.primary : Color.secondary)
      .disabled(!state.isSpeaking)
      .opacity(state.isSpeaking ? 1 : 0.45)
      .accessibilityLabel("Arrêter la lecture")

      Button(action: closeConversation) {
        Image(systemName: "xmark")
          .font(.system(size: 11, weight: .semibold))
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .accessibilityLabel("Fermer la conversation")
    }
    .padding(.horizontal, 16)
    .frame(height: 56)
  }

  private var conversation: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 12) {
          if state.messages.isEmpty {
            emptyState
          } else {
            ForEach(state.messages) { message in
              messageBubble(message)
                .id(message.id)
            }
          }
        }
        .padding(16)
      }
      .onChange(of: state.messages) {
        guard let lastID = state.messages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.15)) {
          proxy.scrollTo(lastID, anchor: .bottom)
        }
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Spacer(minLength: 38)
      Text("Bonjour 👋")
        .font(.title3.weight(.semibold))

      if let availabilityMessage = state.availabilityMessage {
        Text(availabilityMessage)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      } else {
        Text("Pose-moi une question. Mes réponses sont générées localement par Apple Intelligence.")
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      Spacer(minLength: 38)
    }
    .frame(maxWidth: .infinity)
  }

  private func messageBubble(_ message: ChatMessage) -> some View {
    HStack {
      if message.role == .user {
        Spacer(minLength: 42)
      }

      Group {
        if message.content.isEmpty {
          ProgressView()
            .controlSize(.small)
            .padding(.horizontal, 4)
        } else {
          Text(message.content)
            .textSelection(.enabled)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .background(
        message.role == .user ? Color.accentColor : Color.primary.opacity(0.075),
        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
      )
      .foregroundStyle(message.role == .user ? Color.white : Color.primary)

      if message.role == .timi {
        Spacer(minLength: 42)
      }
    }
    .frame(maxWidth: .infinity)
  }

  private var composer: some View {
    VStack(alignment: .leading, spacing: 7) {
      if state.availabilityMessage != nil {
        Label("Active Apple Intelligence pour envoyer", systemImage: "exclamationmark.circle")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let statusMessage = speechInput.statusMessage {
        Label(
          statusMessage,
          systemImage: speechInput.isRecording ? "waveform" : "info.circle"
        )
        .font(.caption)
        .foregroundStyle(speechInput.isRecording ? Color.accentColor : Color.secondary)
      }

      HStack(alignment: .bottom, spacing: 8) {
        TextField("Pose-moi une question…", text: $state.input, axis: .vertical)
          .textFieldStyle(.plain)
          .lineLimit(1...4)
          .focused($inputIsFocused)
          .onSubmit(state.send)

        Button(action: state.toggleDictation) {
          Group {
            if speechInput.isPreparing {
              ProgressView()
                .controlSize(.small)
            } else {
              Image(systemName: speechInput.isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: 12, weight: .semibold))
            }
          }
          .foregroundStyle(speechInput.isRecording ? Color.white : Color.accentColor)
          .frame(width: 28, height: 28)
          .background(
            speechInput.isRecording ? Color.red : Color.accentColor.opacity(0.12),
            in: Circle()
          )
        }
        .buttonStyle(.plain)
        .disabled(speechInput.isPreparing || state.isResponding)
        .accessibilityLabel(speechInput.isRecording ? "Arrêter la dictée" : "Démarrer la dictée")

        Button(action: state.send) {
          Image(systemName: "arrow.up")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(Color.accentColor, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!state.canSend)
        .opacity(state.canSend ? 1 : 0.4)
        .accessibilityLabel("Envoyer")
      }
    }
    .padding(10)
    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .padding(12)
  }

  private func closeConversation() {
    state.stopDictation()
    state.stopSpeaking()
    close()
  }
}
