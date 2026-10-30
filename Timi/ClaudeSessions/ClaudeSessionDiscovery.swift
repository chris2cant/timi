import Foundation

/// Sessions already running when Timi starts, read from the `<pid>.json` files
/// Claude Code keeps in `~/.claude/sessions`. The format is undocumented: unreadable
/// files are skipped, and hooks stay the source of truth once a session sends one.
enum ClaudeSessionDiscovery {
  struct Entry: Decodable, Equatable {
    let sessionId: String
    let pid: pid_t
    var cwd: String? = nil
    /// `busy` or `idle`.
    var status: String? = nil
    /// Milliseconds since 1970.
    var startedAt: Double? = nil
  }

  static var defaultDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/sessions")
  }

  /// Valid entries in `directory`, oldest session first.
  static func entries(in directory: URL = defaultDirectory) -> [Entry] {
    let urls =
      (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
      ?? []
    return
      urls
      .filter { $0.pathExtension == "json" }
      .compactMap { try? Data(contentsOf: $0) }
      .compactMap(entry(from:))
      .sorted { ($0.startedAt ?? 0) < ($1.startedAt ?? 0) }
  }

  static func entry(from data: Data) -> Entry? {
    guard let entry = try? JSONDecoder().decode(Entry.self, from: data),
      !entry.sessionId.isEmpty, entry.pid > 0
    else { return nil }
    return entry
  }

  /// `idle` only says Claude waits for a prompt, not that a turn just ended: no "your turn" alert.
  static func status(of entry: Entry) -> ClaudeSessionStatus {
    entry.status == "busy" ? .working : .idle
  }
}
