import Foundation

/// Account-wide usage of the Claude subscription limits, as read by the status line.
struct ClaudeUsageLimits: Equatable, Codable, Sendable {
  struct Window: Equatable, Codable, Sendable {
    /// 0...100, as reported by Claude Code.
    var usedPercentage: Double
    var resetsAt: Date

    /// Resets within this tolerance belong to the same window.
    private static let sameWindowTolerance: TimeInterval = 60

    /// Used fraction (0...1) at `date`: the window is empty again once it has reset.
    func usedFraction(at date: Date) -> Double {
      date >= resetsAt ? 0 : min(max(usedPercentage / 100, 0), 1)
    }

    /// Elapsed fraction (0...1) of a window lasting `duration`, or `nil` once it has reset.
    func elapsedFraction(at date: Date, duration: TimeInterval) -> Double? {
      guard date < resetsAt else { return nil }
      return min(max(1 - resetsAt.timeIntervalSince(date) / duration, 0), 1)
    }

    /// `newer` coming from any session. Usage only grows within a window, and sessions
    /// may report an older reading than another one did: keep the latest window and,
    /// within it, the highest usage.
    func merged(with newer: Window) -> Window {
      if abs(newer.resetsAt.timeIntervalSince(resetsAt)) < Self.sameWindowTolerance {
        return Window(
          usedPercentage: max(usedPercentage, newer.usedPercentage),
          resetsAt: max(resetsAt, newer.resetsAt)
        )
      }
      return newer.resetsAt > resetsAt ? newer : self
    }
  }

  enum Level: Comparable, Sendable {
    case normal, warning, critical

    init(fraction: Double) {
      self = fraction >= 0.9 ? .critical : fraction >= 0.75 ? .warning : .normal
    }
  }

  static let fiveHourDuration: TimeInterval = 5 * 60 * 60
  static let sevenDayDuration: TimeInterval = 7 * 24 * 60 * 60

  var fiveHour: Window?
  var sevenDay: Window?

  func merged(with newer: ClaudeUsageLimits) -> ClaudeUsageLimits {
    ClaudeUsageLimits(
      fiveHour: Self.merged(fiveHour, newer.fiveHour),
      sevenDay: Self.merged(sevenDay, newer.sevenDay)
    )
  }

  private static func merged(_ old: Window?, _ new: Window?) -> Window? {
    guard let old else { return new }
    guard let new else { return old }
    return old.merged(with: new)
  }

  /// Limits in a Claude Code status line payload; `nil` without any (API key accounts,
  /// or before the session's first response).
  static func fromStatusLine(_ data: Data) -> ClaudeUsageLimits? {
    guard let payload = try? JSONDecoder().decode(StatusLinePayload.self, from: data),
          let limits = payload.rateLimits
    else { return nil }
    let result = ClaudeUsageLimits(
      fiveHour: limits.fiveHour?.window,
      sevenDay: limits.sevenDay?.window
    )
    return result.fiveHour == nil && result.sevenDay == nil ? nil : result
  }

  private struct StatusLinePayload: Decodable {
    struct RateLimits: Decodable {
      let fiveHour: RawWindow?
      let sevenDay: RawWindow?

      enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
      }
    }

    struct RawWindow: Decodable {
      let usedPercentage: Double?
      /// Unix epoch seconds.
      let resetsAt: Double?

      enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
      }

      // A field of an unexpected type drops only that window, not the whole reading.
      init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercentage = try? container.decode(Double.self, forKey: .usedPercentage)
        resetsAt = try? container.decode(Double.self, forKey: .resetsAt)
      }

      var window: Window? {
        guard let usedPercentage, let resetsAt else { return nil }
        return Window(usedPercentage: usedPercentage, resetsAt: Date(timeIntervalSince1970: resetsAt))
      }
    }

    let rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
      case rateLimits = "rate_limits"
    }
  }
}
