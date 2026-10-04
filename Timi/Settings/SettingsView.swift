import AVFoundation
import SwiftUI

struct SettingsView: View {
  @ObservedObject var appState: AppState
  @State private var speechPreview = SpeechOutputController()
  @State private var voiceCatalogVersion = 0

  private let columns = Array(repeating: GridItem(.fixed(86), spacing: 10), count: 3)

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Mascot Position")
          .font(.headline)
        Text("Choose where Timi sits in the usable area of its current display.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      LazyVGrid(columns: columns, spacing: 10) {
        ForEach(0..<9, id: \.self) { cell in
          if cell == 4 {
            Color.clear
              .frame(height: 58)
          } else if let position = position(for: cell) {
            positionButton(position)
          }
        }
      }

      Divider()

      Toggle("Show Timi", isOn: $appState.isVisible)

      Divider()

      VStack(alignment: .leading, spacing: 10) {
        Text("Dictée")
          .font(.headline)

        Picker("Langue", selection: $appState.dictationLanguage) {
          ForEach(DictationLanguage.allCases) { language in
            Text(language.title)
              .tag(language)
          }
        }

        Text("La langue choisie est utilisée pour reconnaître le texte dicté.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Divider()

      VStack(alignment: .leading, spacing: 10) {
        Text("Voice")
          .font(.headline)

        Picker("Voice", selection: $appState.speechVoiceIdentifier) {
          Text(automaticVoiceTitle)
            .tag(nil as String?)

          ForEach(availableVoices) { voice in
            Text("\(voice.name) — \(voice.qualityTitle)")
              .tag(voice.identifier as String?)
          }
        }
        .labelsHidden()

        HStack {
          Text(voiceDetail)
            .font(.caption)
            .foregroundStyle(.secondary)

          Spacer()

          Button("Preview", systemImage: "speaker.wave.2") {
            speechPreview.speak(
              "Bonjour, je suis Timi. Voici un aperçu de ma voix.",
              preferredVoiceIdentifier: appState.speechVoiceIdentifier
            )
          }
        }
      }

      Divider()

      HStack {
        Text("Drag Timi to move it, or click it for a reaction.")
          .font(.callout)
          .foregroundStyle(.secondary)

        Spacer()

        Button("Reset Offset") {
          appState.resetOffset()
        }
        .disabled(appState.offset == .zero)
      }
    }
    .padding(24)
    .frame(width: 380)
    .onReceive(
      NotificationCenter.default.publisher(
        for: AVSpeechSynthesizer.availableVoicesDidChangeNotification
      )
    ) { _ in
      voiceCatalogVersion += 1
    }
    .onDisappear {
      speechPreview.stop()
    }
  }

  private var languageCode: String {
    Locale.current.language.languageCode?.identifier ?? "fr"
  }

  private var availableVoices: [SpeechVoiceOption] {
    _ = voiceCatalogVersion
    return SpeechOutputController.availableVoices(for: languageCode)
  }

  private var automaticVoice: SpeechVoiceOption? {
    _ = voiceCatalogVersion
    return SpeechOutputController.automaticVoice(
      for: "Bonjour, je suis Timi. Voici un aperçu de ma voix."
    )
  }

  private var automaticVoiceTitle: String {
    guard let automaticVoice else { return "Automatic — System voice" }
    return "Automatic — \(automaticVoice.name) (\(automaticVoice.qualityTitle))"
  }

  private var voiceDetail: String {
    if let identifier = appState.speechVoiceIdentifier,
       let voice = availableVoices.first(where: { $0.identifier == identifier }) {
      return "\(voice.localizedLanguage) · \(voice.qualityTitle)"
    }
    if let automaticVoice {
      return "Best installed voice · \(automaticVoice.localizedLanguage)"
    }
    return "Timi will use the system voice."
  }

  private func positionButton(_ position: MascotPosition) -> some View {
    Button {
      appState.select(position)
    } label: {
      Text(position.title)
        .font(.caption)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 50)
        .contentShape(Rectangle())
    }
    .buttonStyle(.bordered)
    .tint(appState.position == position ? .accentColor : nil)
    .accessibilityAddTraits(appState.position == position ? .isSelected : [])
  }

  private func position(for cell: Int) -> MascotPosition? {
    let row = cell / 3
    let column = cell % 3
    return MascotPosition.allCases.first {
      $0.gridRow == row && $0.gridColumn == column
    }
  }
}

struct SettingsView_Previews: PreviewProvider {
  static var previews: some View {
    SettingsView(appState: AppState(defaults: UserDefaults(suiteName: "TimiPreview")!))
  }
}
