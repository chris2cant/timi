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
    /// Milliseconds since 1970, last change of `status`.
    var statusUpdatedAt: Double? = nil
    /// `cli` or `claude-desktop`.
    var entrypoint: String? = nil
    /// Claude Desktop's own id for the session (`local_…`).
    var hostSessionId: String? = nil
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

  /// Entry of the session run by process `pid`, if Claude Code keeps one.
  static func entry(pid: pid_t, in directory: URL = defaultDirectory) -> Entry? {
    guard let data = try? Data(contentsOf: directory.appending(path: "\(pid).json")),
      let entry = entry(from: data), entry.pid == pid
    else { return nil }
    return entry
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

  /// Date of the last status change, if the file records it.
  static func lastActivity(of entry: Entry) -> Date? {
    entry.statusUpdatedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
  }

  /// Deep link that makes Claude Desktop show this session, `nil` for other entry points.
  /// Undocumented: it is what Desktop's own dock menu uses (`claude://code/continue?session=…`).
  static func desktopURL(of entry: Entry) -> URL? {
    guard entry.entrypoint == "claude-desktop", let id = entry.hostSessionId,
      id.wholeMatch(of: /local_[A-Za-z0-9-]{1,64}/) != nil
    else { return nil }
    return URL(string: "claude://code/continue?session=\(id)")
  }
}
