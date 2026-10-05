import AVFoundation
import SwiftUI

struct SettingsView: View {
  @ObservedObject var appState: AppState
  @ObservedObject var dictationStore: DictationStore
  @ObservedObject var shortcutMonitor: GlobalShortcutMonitor
  @ObservedObject var updateManager: UpdateManager
  let requestShortcutPermission: () -> Void
  let testGlobalDictation: () -> Void

  @State private var speechPreview = SpeechOutputController()
  @State private var voiceCatalogVersion = 0
  @State private var vocabularySearch = ""
  @State private var historySearch = ""
  @State private var newTerm = ""
  @State private var newHeardForm = ""
  @State private var newWantedForm = ""
  @State private var recordToCorrect: DictationRecord?
  @State private var correctionText = ""
  @State private var selectedSuggestions: Set<String> = []

  var body: some View {
    TabView {
      generalTab.tabItem { Label("Timi", systemImage: "face.smiling") }
      dictationTab.tabItem { Label("Dictée", systemImage: "waveform") }
      vocabularyTab.tabItem { Label("Vocabulaire", systemImage: "text.book.closed") }
      historyTab.tabItem { Label("Historique", systemImage: "clock.arrow.circlepath") }
    }
    .padding(18)
    .frame(width: 620, height: 540)
    .sheet(item: $recordToCorrect) { record in correctionSheet(for: record) }
    .onReceive(NotificationCenter.default.publisher(
      for: AVSpeechSynthesizer.availableVoicesDidChangeNotification
    )) { _ in voiceCatalogVersion += 1 }
    .onDisappear { speechPreview.stop() }
  }

  private static var versionDescription: String {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "?"
    let build = info?["CFBundleVersion"] as? String ?? "?"
    return "\(version) (\(build))"
  }

  private var generalTab: some View {
    Form {
      Section("Visibilité") {
        Toggle("Afficher Timi", isOn: $appState.isVisible)
        Button("Réinitialiser le décalage") { appState.resetOffset() }
          .disabled(appState.offset == .zero)
      }
      Section("Masquage automatique") {
        Picker("Mode", selection: $appState.autoHideMode) {
          ForEach(AutoHideMode.allCases) { mode in Text(mode.title).tag(mode) }
        }
        if appState.autoHideMode != .off {
          Stepper(value: $appState.autoHideDelay, in: AppState.autoHideDelayRange, step: 0.5) {
            Text("Délai avant masquage : \(appState.autoHideDelay, specifier: "%.1f") s")
          }
        }
        Text("Timi se cache contre le bord d’écran le plus proche et réapparaît quand la souris touche cet endroit.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section("Position") {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
          ForEach(MascotPosition.allCases) { position in
            Button(position.title) { appState.select(position) }
              .buttonStyle(.bordered)
              .tint(appState.position == position ? .accentColor : nil)
          }
        }
      }
      Section("Mises à jour") {
        Toggle(
          "Vérifier automatiquement",
          isOn: Binding(
            get: { updateManager.automaticallyChecksForUpdates },
            set: { updateManager.automaticallyChecksForUpdates = $0 }
          )
        )
        Button("Rechercher des mises à jour…") { updateManager.checkForUpdates() }
          .disabled(!updateManager.canCheckForUpdates)
        Text("Version \(Self.versionDescription). Timi demande toujours avant d’installer une mise à jour.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section("Voix de Timi") {
        Picker("Voix", selection: $appState.speechVoiceIdentifier) {
          Text(automaticVoiceTitle).tag(nil as String?)
          ForEach(availableVoices) { voice in
            Text("\(voice.name) — \(voice.qualityTitle)").tag(voice.identifier as String?)
          }
        }
        Button("Écouter un aperçu", systemImage: "speaker.wave.2") {
          speechPreview.speak(
            "Bonjour, je suis Timi. Voici un aperçu de ma voix.",
            preferredVoiceIdentifier: appState.speechVoiceIdentifier
          )
        }
      }
    }
    .formStyle(.grouped)
  }

  private var dictationTab: some View {
    Form {
      Section("Raccourci global") {
        Picker("Raccourci", selection: $appState.dictationShortcut) {
          ForEach(DictationShortcut.allCases) { shortcut in
            Text(shortcut.title).tag(shortcut)
          }
        }
        Text("Appui bref : bascule. Maintien : enregistre jusqu’au relâchement.")
          .font(.caption).foregroundStyle(.secondary)
        Label(
          shortcutMonitor.status.title,
          systemImage: shortcutMonitor.status == .active
            ? "checkmark.circle.fill" : "exclamationmark.triangle"
        )
        .foregroundStyle(shortcutMonitor.status == .active ? .green : .orange)
        if shortcutMonitor.permissionMissing {
          Label("La Surveillance de l’entrée et l’Accessibilité sont requises pour neutraliser ce raccourci hors de Timi.", systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
        }
        Button("Vérifier ou autoriser le raccourci global") { requestShortcutPermission() }
        Button("Tester la dictée sans raccourci") { testGlobalDictation() }
        if appState.dictationShortcut == .controlSpace && Self.controlSpaceMayConflict {
          Label("⌃ Espace semble attribué au changement de source de saisie dans macOS.", systemImage: "keyboard.badge.exclamationmark")
            .foregroundStyle(.orange)
        }
      }
      Section("Transcription") {
        Picker("Langue", selection: $appState.dictationLanguage) {
          ForEach(DictationLanguage.allCases) { language in Text(language.title).tag(language) }
        }
        Toggle("Nettoyage fidèle avec Apple Intelligence", isOn: $appState.dictationCleanupEnabled)
        Text("En cas d’indisponibilité ou après 8 secondes, Timi applique seulement les corrections exactes et un nettoyage conservateur.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section("Confidentialité") {
        Text("L’audio n’est jamais enregistré. La transcription et le nettoyage sont locaux. Le contexte autour du curseur n’est ni conservé ni ajouté à l’historique.")
          .font(.callout)
        if let error = dictationStore.loadError {
          Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
      }
    }
    .formStyle(.grouped)
  }

  private var vocabularyTab: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        TextField("Ajouter un terme", text: $newTerm)
        Button("Ajouter") {
          dictationStore.addTerm(newTerm, language: appState.dictationLanguage.locale.identifier)
          newTerm = ""
        }
        .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      HStack {
        TextField("Forme entendue", text: $newHeardForm)
        Image(systemName: "arrow.right")
        TextField("Forme voulue", text: $newWantedForm)
        Button("Ajouter l’association") {
          dictationStore.addCorrection(
            heard: newHeardForm,
            replacement: newWantedForm,
            language: appState.dictationLanguage.locale.identifier
          )
          newHeardForm = ""
          newWantedForm = ""
        }
        .disabled(
          newHeardForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || newWantedForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
      }
      TextField("Rechercher", text: $vocabularySearch).textFieldStyle(.roundedBorder)
      List {
        Section("Termes") {
          ForEach(filteredTerms) { term in
            HStack {
              Toggle("", isOn: termEnabledBinding(term)).labelsHidden()
              TextField("Terme", text: termTextBinding(term))
              Text(term.language).foregroundStyle(.secondary)
              Button("Supprimer", systemImage: "trash", role: .destructive) {
                if let index = dictationStore.vocabulary.firstIndex(where: { $0.id == term.id }) {
                  dictationStore.removeTerms(at: IndexSet(integer: index))
                }
              }.labelStyle(.iconOnly)
            }
          }
        }
        Section("Corrections entendu → voulu") {
          ForEach(dictationStore.corrections) { rule in
            HStack {
              Toggle("", isOn: ruleEnabledBinding(rule)).labelsHidden()
              Text("\(rule.heard) → \(rule.replacement)")
              Spacer()
              Button("Supprimer", systemImage: "trash", role: .destructive) {
                if let index = dictationStore.corrections.firstIndex(where: { $0.id == rule.id }) {
                  dictationStore.removeCorrections(at: IndexSet(integer: index))
                }
              }.labelStyle(.iconOnly)
            }
          }
        }
      }
      HStack {
        Text("\(dictationStore.vocabulary.count) termes · \(dictationStore.corrections.count) corrections")
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Tout effacer", role: .destructive) { dictationStore.clearVocabulary() }
      }
    }
  }

  private var historyTab: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        TextField("Rechercher dans l’historique", text: $historySearch).textFieldStyle(.roundedBorder)
        if let first = dictationStore.history.first {
          Button("Corriger la dernière dictée") { beginCorrection(first) }
        }
      }
      List(filteredHistory) { record in
        VStack(alignment: .leading, spacing: 5) {
          HStack {
            Text(record.date, format: .dateTime.day().month().hour().minute())
              .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Corriger") { beginCorrection(record) }
          }
          Text(record.correction ?? record.refinedText).textSelection(.enabled)
          if record.rawText != record.refinedText {
            Text("Brut : \(record.rawText)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
          }
        }.padding(.vertical, 4)
      }
      HStack {
        Text("Maximum 100 dictées pendant 30 jours, sans audio ni contexte d’application.")
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Effacer l’historique", role: .destructive) { dictationStore.clearHistory() }
      }
    }
  }

  private func correctionSheet(for record: DictationRecord) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Corriger la dictée").font(.headline)
      TextEditor(text: $correctionText).frame(minHeight: 120)
      let suggestions = Self.safeSubstitutions(from: record.refinedText, to: correctionText)
      if !suggestions.isEmpty {
        Text("Associations courtes proposées").font(.subheadline.weight(.semibold))
        ForEach(suggestions, id: \.0) { heard, replacement in
          Toggle("\(heard) → \(replacement)", isOn: suggestionBinding(heard, replacement))
            .font(.callout)
        }
        Text("Seules les associations cochées seront ajoutées au catalogue local.")
          .font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        Spacer()
        Button("Annuler") { recordToCorrect = nil }
        Button("Enregistrer") {
          dictationStore.correctRecord(id: record.id, text: correctionText)
          for (heard, replacement) in suggestions where selectedSuggestions.contains(suggestionKey(heard, replacement)) {
            dictationStore.addCorrection(heard: heard, replacement: replacement, language: record.language)
          }
          recordToCorrect = nil
        }.buttonStyle(.borderedProminent)
      }
    }
    .padding(22)
    .frame(width: 480)
  }

  private var languageCode: String { Locale.current.language.languageCode?.identifier ?? "fr" }
  private var availableVoices: [SpeechVoiceOption] {
    _ = voiceCatalogVersion
    return SpeechOutputController.availableVoices(for: languageCode)
  }
  private var automaticVoiceTitle: String {
    guard let voice = SpeechOutputController.automaticVoice(for: "Bonjour, je suis Timi.") else {
      return "Automatique — voix système"
    }
    return "Automatique — \(voice.name) (\(voice.qualityTitle))"
  }
  private var filteredTerms: [VocabularyTerm] {
    vocabularySearch.isEmpty ? dictationStore.vocabulary : dictationStore.vocabulary.filter {
      $0.term.localizedCaseInsensitiveContains(vocabularySearch)
    }
  }
  private var filteredHistory: [DictationRecord] {
    historySearch.isEmpty ? dictationStore.history : dictationStore.history.filter {
      $0.refinedText.localizedCaseInsensitiveContains(historySearch)
        || $0.rawText.localizedCaseInsensitiveContains(historySearch)
    }
  }
  private func beginCorrection(_ record: DictationRecord) {
    correctionText = record.correction ?? record.refinedText
    selectedSuggestions = []
    recordToCorrect = record
  }
  private func suggestionKey(_ heard: String, _ replacement: String) -> String {
    "\(heard)\u{0}\(replacement)"
  }
  private func suggestionBinding(_ heard: String, _ replacement: String) -> Binding<Bool> {
    let key = suggestionKey(heard, replacement)
    return Binding(
      get: { selectedSuggestions.contains(key) },
      set: { selected in
        if selected { selectedSuggestions.insert(key) } else { selectedSuggestions.remove(key) }
      }
    )
  }
  private func termEnabledBinding(_ term: VocabularyTerm) -> Binding<Bool> {
    Binding(get: { term.isEnabled }, set: { value in
      var updated = term; updated.isEnabled = value; dictationStore.updateTerm(updated)
    })
  }
  private func termTextBinding(_ term: VocabularyTerm) -> Binding<String> {
    Binding(get: { term.term }, set: { value in
      var updated = term; updated.term = value; dictationStore.updateTerm(updated)
    })
  }
  private func ruleEnabledBinding(_ rule: CorrectionRule) -> Binding<Bool> {
    Binding(get: { rule.isEnabled }, set: { value in
      var updated = rule; updated.isEnabled = value; dictationStore.updateCorrection(updated)
    })
  }

  static func safeSubstitutions(from original: String, to correction: String) -> [(String, String)] {
    let before = original.split(whereSeparator: \.isWhitespace).map(String.init)
    let after = correction.split(whereSeparator: \.isWhitespace).map(String.init)
    guard before.count == after.count else { return [] }
    return zip(before, after).compactMap { heard, wanted in
      guard heard != wanted, heard.count <= 32, wanted.count <= 32,
            !heard.contains(where: \.isPunctuation), !wanted.contains(where: \.isPunctuation) else {
        return nil
      }
      return (heard, wanted)
    }
  }

  private static var controlSpaceMayConflict: Bool {
    guard let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
          let hotkeys = domain["AppleSymbolicHotKeys"] as? [String: Any] else { return false }
    return ["60", "61"].contains { key in
      guard let entry = hotkeys[key] as? [String: Any] else { return false }
      return entry["enabled"] as? Bool == true
    }
  }
}

struct SettingsView_Previews: PreviewProvider {
  static var previews: some View {
    let defaults = UserDefaults(suiteName: "TimiPreview")!
    SettingsView(
      appState: AppState(defaults: defaults),
      dictationStore: DictationStore(fileURL: FileManager.default.temporaryDirectory.appending(path: "timi-preview.json")),
      shortcutMonitor: GlobalShortcutMonitor(),
      updateManager: UpdateManager(),
      requestShortcutPermission: {},
      testGlobalDictation: {}
    )
  }
}
