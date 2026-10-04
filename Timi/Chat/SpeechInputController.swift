import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
final class SpeechInputController: ObservableObject {
  @Published private(set) var isRecording = false
  @Published private(set) var isPreparing = false
  @Published private(set) var statusMessage: String?

  var onTranscriptChange: ((String) -> Void)?
  var onMeterChange: ((AudioMeterSnapshot) -> Void)?
  var onFinished: ((String) -> Void)?
  var onFailure: ((String, String) -> Void)?
  var onAlternativesChange: (([String]) -> Void)?

  var isActive: Bool {
    isRecording || isPreparing
  }

  private var pipeline: SpeechAudioPipeline?
  private var resultsTask: Task<Void, Never>?
  private var preparationTask: Task<Void, Never>?
  private var finalizedTranscript = ""
  private var volatileTranscript = ""

  var transcript: String {
    (finalizedTranscript + volatileTranscript)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  deinit {
    preparationTask?.cancel()
    resultsTask?.cancel()
  }

  func toggle(locale: Locale) {
    if isRecording {
      stop()
    } else if !isPreparing {
      start(locale: locale)
    }
  }

  func start(locale: Locale, contextualStrings: [String] = []) {
    guard !isActive else { return }

    isPreparing = true
    statusMessage = "Préparation du microphone…"
    finalizedTranscript = ""
    volatileTranscript = ""

    preparationTask = Task { [weak self] in
      guard let self else { return }

      do {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
          throw SpeechInputError.microphoneAccessDenied
        }

        try Task.checkCancellation()
        if SpeechTranscriber.isAvailable,
           let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
          var preset = SpeechTranscriber.Preset.progressiveTranscription
          preset.reportingOptions.insert(.alternativeTranscriptions)
          preset.attributeOptions.insert(.transcriptionConfidence)
          let transcriber = SpeechTranscriber(locale: supportedLocale, preset: preset)
          try await begin(using: transcriber, contextualStrings: contextualStrings)
        } else if let supportedLocale = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
          let transcriber = DictationTranscriber(
            locale: supportedLocale,
            preset: .progressiveShortDictation
          )
          try await begin(using: transcriber, contextualStrings: contextualStrings)
        } else {
          throw SpeechInputError.unsupportedLocale
        }
      } catch is CancellationError {
        await self.stopPipeline(finalize: false)
        reset()
      } catch {
        await self.stopPipeline(finalize: false)
        fail(with: error)
      }
    }
  }

  func stop() {
    guard isActive else { return }

    preparationTask?.cancel()
    preparationTask = nil
    isPreparing = true
    isRecording = false
    statusMessage = "Finalisation de la dictée…"

    let pipeline = pipeline
    let resultsTask = resultsTask
    self.pipeline = nil

    Task { [weak self] in
      do {
        try await pipeline?.stop(finalize: true)
        await resultsTask?.value
      } catch {
        guard !Task.isCancelled else { return }
        self?.fail(with: error)
        return
      }
      guard let self else { return }
      let transcript = self.transcript
      self.reset(keepingTranscript: true)
      self.onFinished?(transcript)
    }
  }

  private func begin(
    using transcriber: SpeechTranscriber,
    contextualStrings: [String]
  ) async throws {
    resultsTask = Task { [weak self] in
      do {
        for try await result in transcriber.results {
          guard !Task.isCancelled else { return }
          self?.onAlternativesChange?(
            result.alternatives.prefix(2).map { String($0.characters) }
          )
          self?.receive(text: String(result.text.characters), isFinal: result.isFinal)
        }
      } catch {
        guard !Task.isCancelled else { return }
        await self?.handleResultsFailure(error)
      }
    }

    try await beginAnalysis(modules: [transcriber], contextualStrings: contextualStrings)
  }

  private func begin(
    using transcriber: DictationTranscriber,
    contextualStrings: [String]
  ) async throws {
    resultsTask = Task { [weak self] in
      do {
        for try await result in transcriber.results {
          guard !Task.isCancelled else { return }
          self?.onAlternativesChange?(
            result.alternatives.prefix(2).map { String($0.characters) }
          )
          self?.receive(text: String(result.text.characters), isFinal: result.isFinal)
        }
      } catch {
        guard !Task.isCancelled else { return }
        await self?.handleResultsFailure(error)
      }
    }

    try await beginAnalysis(modules: [transcriber], contextualStrings: contextualStrings)
  }

  private func beginAnalysis(
    modules: [any SpeechModule],
    contextualStrings: [String]
  ) async throws {
    try Task.checkCancellation()

    let assetStatus = await AssetInventory.status(forModules: modules)
    switch assetStatus {
    case .installed:
      break
    case .supported, .downloading:
      statusMessage = "Téléchargement du modèle vocal…"
      if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
        try await request.downloadAndInstall()
      }
    case .unsupported:
      throw SpeechInputError.modelUnavailable
    @unknown default:
      throw SpeechInputError.modelUnavailable
    }

    try Task.checkCancellation()
    statusMessage = "Préparation de la dictée…"

    let pipeline = SpeechAudioPipeline()
    self.pipeline = pipeline
    try await pipeline.start(modules: modules, contextualStrings: contextualStrings) { [weak self] snapshot in
      Task { @MainActor [weak self] in
        self?.onMeterChange?(snapshot)
      }
    }
    try Task.checkCancellation()

    preparationTask = nil
    isPreparing = false
    isRecording = true
    statusMessage = "À l’écoute… clique sur le micro pour terminer."
  }

  private func handleResultsFailure(_ error: Error) async {
    await stopPipeline(finalize: false)
    fail(with: error)
  }

  private func stopPipeline(finalize: Bool) async {
    let pipeline = pipeline
    self.pipeline = nil
    try? await pipeline?.stop(finalize: finalize)
  }

  private func receive(text: String, isFinal: Bool) {
    if isFinal {
      finalizedTranscript += text
      volatileTranscript = ""
    } else {
      volatileTranscript = text
    }

    let transcript = (finalizedTranscript + volatileTranscript)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    onTranscriptChange?(transcript)
  }

  private func fail(with error: Error) {
    let message: String
    switch error {
    case SpeechInputError.microphoneAccessDenied:
      message = "Autorise le microphone dans Réglages Système > Confidentialité et sécurité."
    case SpeechInputError.unsupportedLocale:
      message = "La langue actuelle n’est pas disponible pour la dictée sur ce Mac."
    case SpeechInputError.modelUnavailable:
      message = "Le modèle de transcription n’est pas disponible sur ce Mac."
    case SpeechInputError.microphoneUnavailable:
      message = "Aucun microphone utilisable n’a été détecté."
    default:
      message = "La dictée n’a pas pu démarrer. Réessaie dans un instant."
    }

    reset(keepingTranscript: true)
    statusMessage = message
    onFailure?(message, transcript)
  }

  private func reset(keepingTranscript: Bool = false) {
    resultsTask?.cancel()

    pipeline = nil
    resultsTask = nil
    preparationTask = nil
    isPreparing = false
    isRecording = false
    statusMessage = nil

    if !keepingTranscript {
      finalizedTranscript = ""
      volatileTranscript = ""
    }
  }
}

/// Audio device setup can synchronously wait on Core Audio. Keeping it on a
/// dedicated actor prevents that system work from blocking SwiftUI's main actor.
private actor SpeechAudioPipeline {
  private var analyzer: SpeechAnalyzer?
  private var audioEngine: AVAudioEngine?
  private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
  private var hasInputTap = false

  func start(
    modules: [any SpeechModule],
    contextualStrings: [String],
    onMeter: @escaping @Sendable (AudioMeterSnapshot) -> Void
  ) async throws {
    do {
      guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
        compatibleWith: modules
      ) else {
        throw SpeechInputError.audioFormatUnavailable
      }

      try Task.checkCancellation()

      let engine = AVAudioEngine()
      let inputNode = engine.inputNode
      let inputFormat = inputNode.outputFormat(forBus: 0)
      guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
        throw SpeechInputError.microphoneUnavailable
      }

      let converter = try AudioBufferConverter(from: inputFormat, to: analyzerFormat)
      let meter = AudioMeterProcessor(onSnapshot: onMeter)
      let (inputSequence, continuation) = AsyncStream<AnalyzerInput>.makeStream()
      let analyzer = SpeechAnalyzer(modules: modules)
      if !contextualStrings.isEmpty {
        let context = AnalysisContext()
        context.contextualStrings[.general] = Array(contextualStrings.prefix(200))
        try await analyzer.setContext(context)
      }

      self.analyzer = analyzer
      audioEngine = engine
      inputContinuation = continuation

      try await analyzer.start(inputSequence: inputSequence)
      try Task.checkCancellation()

      inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { buffer, _ in
        meter.consume(buffer)
        do {
          for input in try converter.convert(buffer) {
            continuation.yield(input)
          }
        } catch {
          continuation.finish()
        }
      }
      hasInputTap = true

      engine.prepare()
      try engine.start()
    } catch {
      cleanUpAudioInput()
      analyzer = nil
      throw error
    }
  }

  func stop(finalize: Bool) async throws {
    let analyzer = analyzer
    cleanUpAudioInput()

    defer {
      self.analyzer = nil
    }

    if finalize {
      try await analyzer?.finalizeAndFinishThroughEndOfInput()
    }
  }

  private func cleanUpAudioInput() {
    if hasInputTap {
      audioEngine?.inputNode.removeTap(onBus: 0)
      hasInputTap = false
    }
    audioEngine?.stop()
    inputContinuation?.finish()
    inputContinuation = nil
    audioEngine = nil
  }
}

private final class AudioMeterProcessor: @unchecked Sendable {
  private let lock = NSLock()
  private var smoother = AudioLevelSmoother()
  private var lastPublish = Date.distantPast
  private let onSnapshot: @Sendable (AudioMeterSnapshot) -> Void

  init(onSnapshot: @escaping @Sendable (AudioMeterSnapshot) -> Void) {
    self.onSnapshot = onSnapshot
  }

  func consume(_ buffer: AVAudioPCMBuffer) {
    let now = Date()
    guard let channel = buffer.floatChannelData?.pointee else {
      onSnapshot(AudioMeterSnapshot(level: 0, lastBufferDate: now))
      return
    }
    let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
    let rms = AudioLevelMeter.rootMeanSquare(samples)

    lock.lock()
    let level = smoother.push(rms: rms)
    let shouldPublish = now.timeIntervalSince(lastPublish) >= 0.05
    if shouldPublish { lastPublish = now }
    lock.unlock()

    if shouldPublish {
      onSnapshot(AudioMeterSnapshot(level: level, lastBufferDate: now))
    }
  }
}

private enum SpeechInputError: Error {
  case microphoneAccessDenied
  case microphoneUnavailable
  case unsupportedLocale
  case modelUnavailable
  case audioFormatUnavailable
}

private final class AudioBufferConverter: @unchecked Sendable {
  private let converter: AVAudioConverter
  private let outputFormat: AVAudioFormat

  init(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) throws {
    guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
      throw SpeechInputError.audioFormatUnavailable
    }
    self.converter = converter
    self.outputFormat = outputFormat
  }

  func convert(_ inputBuffer: AVAudioPCMBuffer) throws -> [AnalyzerInput] {
    let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
    let capacity = AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio))
    guard let outputBuffer = AVAudioPCMBuffer(
      pcmFormat: outputFormat,
      frameCapacity: max(capacity, 1)
    ) else {
      throw SpeechInputError.audioFormatUnavailable
    }

    var conversionError: NSError?
    let inputSource = ConverterInputSource(buffer: inputBuffer)
    let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outputStatus in
      inputSource.next(outputStatus: outputStatus)
    }

    if let conversionError {
      throw conversionError
    }
    guard status != .error, outputBuffer.frameLength > 0 else { return [] }

    return [AnalyzerInput(buffer: outputBuffer)]
  }
}

/// `AVAudioConverter` declares its input callback as concurrently executable.
/// This wrapper owns the non-Sendable Core Audio buffer and synchronizes the
/// one-shot handoff instead of capturing mutable local state in that callback.
private final class ConverterInputSource: @unchecked Sendable {
  private let buffer: AVAudioPCMBuffer
  private let lock = NSLock()
  private var hasSuppliedBuffer = false

  init(buffer: AVAudioPCMBuffer) {
    self.buffer = buffer
  }

  func next(outputStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
    lock.lock()
    defer { lock.unlock() }

    guard !hasSuppliedBuffer else {
      outputStatus.pointee = .noDataNow
      return nil
    }

    hasSuppliedBuffer = true
    outputStatus.pointee = .haveData
    return buffer
  }
}
