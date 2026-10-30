import Foundation

/// Fields Timi reads from a Claude Code hook payload. Unknown fields are ignored.
struct ClaudeHookEvent: Decodable, Equatable, Sendable {
  let hookEventName: String
  let sessionID: String
  var cwd: String? = nil
  var agentID: String? = nil
  var toolName: String? = nil
  var notificationType: String? = nil
  var source: String? = nil

  enum CodingKeys: String, CodingKey {
    case hookEventName = "hook_event_name"
    case sessionID = "session_id"
    case cwd
    case agentID = "agent_id"
    case toolName = "tool_name"
    case notificationType = "notification_type"
    case source
  }
}

/// Terminal context forwarded by the hook command as `X-Timi-*` headers.
/// Empty header values (variable unset in the hook shell) are stored as `nil`.
struct ClaudeHookContext: Equatable, Sendable {
  var pid: pid_t? = nil
  var cmuxWorkspaceID: String? = nil
  var cmuxSurfaceID: String? = nil
  var cmuxSocketPath: String? = nil
  var cmuxCLIPath: String? = nil
  var herdrPaneID: String? = nil
  var herdrSocketPath: String? = nil
  var herdrCLIPath: String? = nil
}

struct ClaudeHookRequest: Equatable, Sendable {
  let event: ClaudeHookEvent
  let context: ClaudeHookContext
}

/// Minimal HTTP/1.1 request parsing for what the hook's `curl` sends.
enum ClaudeHookRequestParser {
  enum Result: Equatable {
    /// Headers or body not fully received yet.
    case needsMoreData
    case request(ClaudeHookRequest)
    /// Malformed HTTP or a payload without `hook_event_name` / `session_id`.
    case invalid
  }

  static let maxRequestSize = 1_048_576
  private static let headerTerminator = Data("\r\n\r\n".utf8)

  static func parse(_ data: Data) -> Result {
    guard data.count <= maxRequestSize else { return .invalid }
    guard let headerEnd = data.range(of: headerTerminator) else { return .needsMoreData }

    let head = String(decoding: data[data.startIndex..<headerEnd.lowerBound], as: UTF8.self)
    var lines = head.components(separatedBy: "\r\n")
    guard lines.removeFirst().hasPrefix("POST ") else { return .invalid }

    var headers: [String: String] = [:]
    for line in lines {
      guard let colon = line.firstIndex(of: ":") else { return .invalid }
      let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
      headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }

    var contentLength = 0
    if let value = headers["content-length"] {
      guard let length = Int(value), length >= 0, length <= maxRequestSize else { return .invalid }
      contentLength = length
    }
    let body = data[headerEnd.upperBound...]
    guard body.count >= contentLength else { return .needsMoreData }

    guard
      let event = try? JSONDecoder().decode(ClaudeHookEvent.self, from: body.prefix(contentLength)),
      !event.sessionID.isEmpty
    else { return .invalid }

    func text(_ name: String) -> String? {
      guard let value = headers[name], !value.isEmpty else { return nil }
      return value
    }
    let pid = text("x-timi-pid").flatMap { Int32($0) }.flatMap { $0 > 0 ? $0 : nil }
    let context = ClaudeHookContext(
      pid: pid,
      cmuxWorkspaceID: text("x-timi-cmux-workspace"),
      cmuxSurfaceID: text("x-timi-cmux-surface"),
      cmuxSocketPath: text("x-timi-cmux-socket"),
      cmuxCLIPath: text("x-timi-cmux-cli"),
      herdrPaneID: text("x-timi-herdr-pane"),
      herdrSocketPath: text("x-timi-herdr-socket"),
      herdrCLIPath: text("x-timi-herdr-cli")
    )
    return .request(ClaudeHookRequest(event: event, context: context))
  }
}
