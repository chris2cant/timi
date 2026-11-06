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

/// Brief event the mascot reacts to with a gesture, on top of its status.
struct ClaudeSessionReaction: Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case promptReceived, toolSucceeded, toolFailed, subagentStarted
  }
  let kind: Kind
  /// Grows with every reaction, so two identical reactions in a row still differ.
  let serial: Int
}

struct ClaudeSession: Identifiable, Equatable, Sendable {
  /// Claude Code `session_id`.
  let id: String
  var projectName: String
  var status: ClaudeSessionStatus
  var context: ClaudeHookContext
  /// Last gesture to play; kept until the next one.
  var reaction: ClaudeSessionReaction? = nil

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
    case "UserPromptSubmit", "PostToolUse", "PostToolUseFailure", "SubagentStart":
      next = .working
    case "SubagentStop":
      // Claude Code ends internal background agents after `Stop`: the turn stays over.
      next = current ?? .idle
    case "PreToolUse":
      next = event.toolName == "AskUserQuestion" || event.toolName == "ExitPlanMode" ? .needsYou : .working
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

  /// Gesture for `event`, given the status `current` before it (`nil` when unknown).
  /// Sub-agent activity during `.needsYou` stays silent, like in `nextStatus`.
  static func reactionKind(
    for event: ClaudeHookEvent,
    from current: ClaudeSessionStatus?
  ) -> ClaudeSessionReaction.Kind? {
    if current == .needsYou, event.agentID != nil { return nil }
    switch event.hookEventName {
    case "UserPromptSubmit": return .promptReceived
    case "PostToolUse": return .toolSucceeded
    case "PostToolUseFailure": return .toolFailed
    case "SubagentStart": return .subagentStarted
    default: return nil
    }
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
