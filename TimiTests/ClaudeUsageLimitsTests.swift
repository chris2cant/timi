import XCTest
@testable import Timi

final class ClaudeUsageLimitsTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func window(_ used: Double, resetsIn seconds: TimeInterval) -> ClaudeUsageLimits.Window {
    ClaudeUsageLimits.Window(usedPercentage: used, resetsAt: now.addingTimeInterval(seconds))
  }

  func testStatusLinePayloadIsDecoded() throws {
    let json = #"""
      {"session_id":"s1","model":{"display_name":"Opus"},
       "rate_limits":{"five_hour":{"used_percentage":62.5,"resets_at":1800003600},
                      "seven_day":{"used_percentage":18,"resets_at":1800259200}}}
      """#
    let limits = try XCTUnwrap(ClaudeUsageLimits.fromStatusLine(Data(json.utf8)))
    XCTAssertEqual(limits.fiveHour, window(62.5, resetsIn: 3600))
    XCTAssertEqual(limits.sevenDay, window(18, resetsIn: 259_200))
  }

  func testPayloadWithoutLimitsIsIgnored() {
    XCTAssertNil(ClaudeUsageLimits.fromStatusLine(Data(#"{"session_id":"s1"}"#.utf8)))
    XCTAssertNil(ClaudeUsageLimits.fromStatusLine(Data(#"{"rate_limits":{}}"#.utf8)))
    XCTAssertNil(ClaudeUsageLimits.fromStatusLine(Data("not json".utf8)))
  }

  func testMalformedWindowOnlyDropsThatWindow() throws {
    let json = #"""
      {"rate_limits":{"five_hour":{"used_percentage":"lots","resets_at":1800003600},
                      "seven_day":{"used_percentage":18,"resets_at":1800259200}}}
      """#
    let limits = try XCTUnwrap(ClaudeUsageLimits.fromStatusLine(Data(json.utf8)))
    XCTAssertNil(limits.fiveHour)
    XCTAssertEqual(limits.sevenDay?.usedPercentage, 18)
  }

  func testWindowIsEmptyOnceReset() {
    let window = window(80, resetsIn: 60)
    XCTAssertEqual(window.usedFraction(at: now), 0.8, accuracy: 1e-9)
    XCTAssertEqual(window.usedFraction(at: now.addingTimeInterval(60)), 0)
    XCTAssertNil(window.elapsedFraction(at: now.addingTimeInterval(60), duration: 3600))
  }

  func testUsedFractionIsClamped() {
    XCTAssertEqual(window(130, resetsIn: 60).usedFraction(at: now), 1)
    XCTAssertEqual(window(-4, resetsIn: 60).usedFraction(at: now), 0)
  }

  func testElapsedFraction() throws {
    let window = window(10, resetsIn: 4 * 3600)
    let elapsed = try XCTUnwrap(window.elapsedFraction(at: now, duration: ClaudeUsageLimits.fiveHourDuration))
    XCTAssertEqual(elapsed, 0.2, accuracy: 1e-9)
  }

  func testSameWindowKeepsHighestUsage() {
    let current = window(40, resetsIn: 3600)
    // An idle session refreshes with the reading of its last response.
    XCTAssertEqual(current.merged(with: window(30, resetsIn: 3600)).usedPercentage, 40)
    XCTAssertEqual(current.merged(with: window(55, resetsIn: 3620)).usedPercentage, 55)
  }

  func testNewerWindowReplacesOlderOne() {
    let current = window(90, resetsIn: 60)
    XCTAssertEqual(current.merged(with: window(5, resetsIn: 5 * 3600)), window(5, resetsIn: 5 * 3600))
    XCTAssertEqual(window(5, resetsIn: 5 * 3600).merged(with: current), window(5, resetsIn: 5 * 3600))
  }

  func testMergeKeepsWindowsMissingFromTheNewReading() {
    let current = ClaudeUsageLimits(fiveHour: window(40, resetsIn: 3600), sevenDay: window(20, resetsIn: 86_400))
    let merged = current.merged(with: ClaudeUsageLimits(fiveHour: window(45, resetsIn: 3600), sevenDay: nil))
    XCTAssertEqual(merged.fiveHour?.usedPercentage, 45)
    XCTAssertEqual(merged.sevenDay, current.sevenDay)
  }

  func testLevels() {
    XCTAssertEqual(ClaudeUsageLimits.Level(fraction: 0.74), .normal)
    XCTAssertEqual(ClaudeUsageLimits.Level(fraction: 0.75), .warning)
    XCTAssertEqual(ClaudeUsageLimits.Level(fraction: 0.9), .critical)
  }

  func testCountdown() {
    XCTAssertEqual(UsageGaugeView.countdown(until: now.addingTimeInterval(41 * 60 + 5), from: now), "42 min")
    XCTAssertEqual(UsageGaugeView.countdown(until: now.addingTimeInterval(2 * 3600 + 5 * 60), from: now), "2 h 05")
    XCTAssertEqual(UsageGaugeView.countdown(until: now.addingTimeInterval(3 * 86_400), from: now), "3 j")
  }

  func testStatusLineRequestIsRouted() {
    let body = #"{"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":1800003600}}}"#
    let head = "POST /claude-statusline HTTP/1.1\r\nHost: timi\r\nContent-Length: \(body.utf8.count)\r\n\r\n"
    XCTAssertEqual(
      ClaudeHookRequestParser.parse(Data((head + body).utf8)),
      .statusLine(ClaudeUsageLimits(fiveHour: window(12, resetsIn: 3600), sevenDay: nil))
    )
    let empty = "POST /claude-statusline HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}"
    XCTAssertEqual(ClaudeHookRequestParser.parse(Data(empty.utf8)), .statusLine(nil))
  }
}

@MainActor
final class ClaudeUsageStoreTests: XCTestCase {
  private var defaults: UserDefaults!
  private let suiteName = "ClaudeUsageStoreTests"

  override func setUp() async throws {
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
  }

  override func tearDown() async throws {
    defaults.removePersistentDomain(forName: suiteName)
  }

  func testReadingIsMergedAndRestored() {
    let resetsAt = Date(timeIntervalSince1970: 1_800_003_600)
    let store = ClaudeUsageStore(defaults: defaults)
    XCTAssertNil(store.limits)

    store.update(with: ClaudeUsageLimits(fiveHour: .init(usedPercentage: 40, resetsAt: resetsAt)))
    store.update(with: ClaudeUsageLimits(fiveHour: .init(usedPercentage: 30, resetsAt: resetsAt)))
    XCTAssertEqual(store.limits?.fiveHour?.usedPercentage, 40)

    XCTAssertEqual(ClaudeUsageStore(defaults: defaults).limits, store.limits)
  }
}

