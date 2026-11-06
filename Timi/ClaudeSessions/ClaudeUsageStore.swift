import Combine
import Foundation

/// Latest subscription usage reported by any Claude Code status line.
@MainActor
final class ClaudeUsageStore: ObservableObject {
  @Published private(set) var limits: ClaudeUsageLimits?

  private let defaults: UserDefaults
  private static let defaultsKey = "claudeUsageLimits"

  /// Restores the last reading: the status line only reports again at a session's next
  /// refresh, and expired windows already read as empty.
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    limits = defaults.data(forKey: Self.defaultsKey)
      .flatMap { try? JSONDecoder().decode(ClaudeUsageLimits.self, from: $0) }
  }

  func update(with reading: ClaudeUsageLimits) {
    let merged = limits.map { $0.merged(with: reading) } ?? reading
    guard merged != limits else { return }
    limits = merged
    defaults.set(try? JSONEncoder().encode(merged), forKey: Self.defaultsKey)
  }
}
