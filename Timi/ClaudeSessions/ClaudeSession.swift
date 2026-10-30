import Foundation

enum ClaudeSessionStatus: Equatable, Sendable {
  case idle
  /// Claude is running tools or generating.
  case working
  /// Blocked on the user: permission, question or plan approval.
  case needsYou
  /// Turn finished; Claude waits for the next prompt.
  case yourTurn
}

struct ClaudeSession: Identifiable, Equatable, Sendable {
  /// Claude Code `session_id`.
  let id: String
  var projectName: String
  var status: ClaudeSessionStatus
  var context: ClaudeHookContext

  /// Status after `event`. `current == nil` means the session is unknown.
  /// Returns `nil` when the session must not exist (ended, or end of an unknown one).
  static func nextStatus(
    from current: ClaudeSessionStatus?,
    on event: ClaudeHookEvent
  ) -> ClaudeSessionStatus? {
    let next: ClaudeSessionStatus?
    switch event.hookEventName {
    case "SessionEnd":
      return nil
    case "SessionStart":
      next = event.source == "compact" ? (current ?? .idle) : .idle
    case "UserPromptSubmit", "PostToolUse", "PostToolUseFailure", "SubagentStart", "SubagentStop":
      next = .working
    case "PreToolUse":
      next = event.toolName.map { ["AskUserQuestion", "ExitPlanMode"].contains($0) } == true ? .needsYou : .working
    case "PermissionRequest":
      next = .needsYou
    case "Notification":
      switch event.notificationType {
      case "permission_prompt", "elicitation_dialog":
        next = .needsYou
      case "idle_prompt":
        next = current == .needsYou ? .needsYou : .yourTurn
      default:
        next = current ?? .idle
      }
    case "Stop":
      next = .yourTurn
    default:
      next = current ?? .idle
    }
    // Sub-agent activity must not clear a pending request for the user.
    if current == .needsYou, event.agentID != nil, next == .working {
      return .needsYou
    }
    return next
  }

  /// Name of the git repository containing `cwd`, else its last path component.
  static func projectName(
    forWorkingDirectory cwd: String?,
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
  ) -> String {
    guard let cwd, !cwd.isEmpty else { return "Claude" }
    var directory = cwd
    for _ in 0..<50 {
      if fileExists("\(directory)/.git") {
        return URL(fileURLWithPath: directory).lastPathComponent
      }
      let parent = URL(fileURLWithPath: directory).deletingLastPathComponent().path
      if parent == directory { break }
      directory = parent
    }
    let name = URL(fileURLWithPath: cwd).lastPathComponent
    return name.isEmpty ? "Claude" : name
  }

}
