import XCTest

@testable import Timi

final class DictationSignalTests: XCTestCase {
  func testRMSForSilenceAndHalfScaleSignal() {
    let silence = [Float](repeating: 0, count: 32)
    let half = [Float](repeating: 0.5, count: 32)

    let silentDB = silence.withUnsafeBufferPointer(AudioLevelMeter.rootMeanSquare)
    let halfDB = half.withUnsafeBufferPointer(AudioLevelMeter.rootMeanSquare)

    XCTAssertEqual(silentDB, -80)
    XCTAssertEqual(halfDB, -6.0206, accuracy: 0.001)
  }

  func testSmootherAttacksFasterThanItReleasesAndResets() {
    var smoother = AudioLevelSmoother(attack: 0.5, release: 0.1)
    let attack = smoother.push(rms: -10)
    let release = smoother.push(rms: -80)

    XCTAssertGreaterThan(attack, 0.45)
    XCTAssertGreaterThan(release, attack * 0.85)
    smoother.reset()
    XCTAssertEqual(smoother.level, 0)
  }
}

final class HybridShortcutStateTests: XCTestCase {
  func testShortPressTogglesAndIgnoresRepeat() {
    var state = HybridShortcutState()
    XCTAssertTrue(state.keyDown(isRepeat: false))
    XCTAssertFalse(state.keyDown(isRepeat: true))
    XCTAssertEqual(state.keyUp(), .toggle)
    XCTAssertNil(state.keyUp())
  }

  func testHoldStartsAtThresholdAndStopsOnRelease() {
    var state = HybridShortcutState()
    XCTAssertTrue(state.keyDown(isRepeat: false))
    XCTAssertEqual(state.holdThresholdReached(), .beginHold)
    XCTAssertNil(state.holdThresholdReached())
    XCTAssertEqual(state.keyUp(), .endHold)
  }
}

@MainActor
final class DictationCleanupTests: XCTestCase {
  func testConservativeCleanupAppliesExactRuleAndHesitationRemoval() {
    let rule = CorrectionRule(heard: "Timmy", replacement: "Timi", language: "fr-FR")
    let result = DictationTextCleanup.conservative(
      "euh timmy  ouvre le fichier .",
      rules: [rule]
    )
    XCTAssertEqual(result, "Timi ouvre le fichier.")
  }

  func testOutputValidationRejectsEmptyExtremeAndConversationalText() {
    XCTAssertFalse(DictationTextCleanup.isAcceptable(refined: "", comparedTo: "bonjour"))
    XCTAssertFalse(DictationTextCleanup.isAcceptable(refined: "Oui", comparedTo: "une phrase beaucoup plus longue que oui"))
    XCTAssertFalse(DictationTextCleanup.isAcceptable(refined: "Bien sûr, voici le texte demandé", comparedTo: "voici le texte demandé"))
    XCTAssertTrue(DictationTextCleanup.isAcceptable(refined: "Bonjour, Timi.", comparedTo: "bonjour Timi"))
  }

  func testOnlyShortWordForWordCorrectionsAreSuggested() {
    XCTAssertEqual(
      SettingsView.safeSubstitutions(from: "Bonjour Timmy", to: "Bonjour Timi").count,
      1
    )
    XCTAssertTrue(
      SettingsView.safeSubstitutions(from: "Une phrase", to: "Une reformulation complète").isEmpty
    )
  }
}

@MainActor
final class DictationStoreTests: XCTestCase {
  func testStorePersistsVocabularyCorrectionsAndHistory() {
    let url = temporaryURL()
    let store = DictationStore(fileURL: url)
    store.addTerm("Timi", language: "fr-FR")
    store.addCorrection(heard: "Timmy", replacement: "Timi", language: "fr-FR")
    store.addRecord(DictationRecord(language: "fr-FR", rawText: "Timmy", refinedText: "Timi"))

    let reloaded = DictationStore(fileURL: url)
    XCTAssertEqual(reloaded.corrections.count, 1)
    XCTAssertEqual(reloaded.history.first?.refinedText, "Timi")
    XCTAssertTrue(reloaded.vocabulary.contains { $0.term == "Timi" })
  }

  func testHistoryIsLimitedToOneHundredAndThirtyDays() {
    let store = DictationStore(fileURL: temporaryURL())
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    store.addRecord(DictationRecord(
      date: now.addingTimeInterval(-31 * 86_400),
      language: "fr-FR",
      rawText: "ancien",
      refinedText: "ancien"
    ), now: now)
    for index in 0..<110 {
      store.addRecord(DictationRecord(
        date: now.addingTimeInterval(Double(-index)),
        language: "fr-FR",
        rawText: "\(index)",
        refinedText: "\(index)"
      ), now: now)
    }

    XCTAssertEqual(store.history.count, 100)
    XCTAssertFalse(store.history.contains { $0.rawText == "ancien" })
  }

  func testCorruptDataIsReportedWithoutBeingOverwritten() throws {
    let url = temporaryURL()
    try Data("not json".utf8).write(to: url)
    let store = DictationStore(fileURL: url)

    XCTAssertNotNil(store.loadError)
    XCTAssertEqual(try Data(contentsOf: url), Data("not json".utf8))
  }

  private func temporaryURL() -> URL {
    FileManager.default.temporaryDirectory
      .appending(path: "TimiTests-\(UUID().uuidString).json")
  }
}
