import Combine
import Foundation

@MainActor
final class ClaudeSessionStore: ObservableObject {
  /// Sessions in order of first appearance.
  @Published private(set) var sessions: [ClaudeSession] = []

  private let now: () -> Date
  private let isProcessAlive: (pid_t) -> Bool
  private var livenessTimer: Timer?
  /// Kept apart from `sessions` so that a plain heartbeat does not republish.
  private var lastActivity: [String: Date] = [:]

  private static let livenessInterval: TimeInterval = 10
  private static let silenceTimeout: TimeInterval = 2 * 60 * 60

  init(
    now: @escaping () -> Date = Date.init,
    isProcessAlive: @escaping (pid_t) -> Bool = { kill($0, 0) == 0 || errno == EPERM }
  ) {
    self.now = now
    self.isProcessAlive = isProcessAlive
  }

  func handle(_ request: ClaudeHookRequest) {
    let event = request.event
    let index = sessions.firstIndex { $0.id == event.sessionID }
    guard let status = ClaudeSession.nextStatus(from: index.map { sessions[$0].status }, on: event)
    else {
      if let index { sessions.remove(at: index) }
      lastActivity[event.sessionID] = nil
      return
    }

    lastActivity[event.sessionID] = now()
    guard let index else {
      sessions.append(
        ClaudeSession(
          id: event.sessionID,
          projectName: ClaudeSession.projectName(forWorkingDirectory: event.cwd),
          status: status,
          context: request.context
        ))
      return
    }

    var session = sessions[index]
    session.status = status
    session.context = Self.merged(session.context, with: request.context)
    if session != sessions[index] {
      sessions[index] = session
    }
  }

  /// Starts the periodic removal of sessions whose process died or went silent.
  func startLivenessChecks() {
    guard livenessTimer == nil else { return }
    livenessTimer = Timer.scheduledTimer(withTimeInterval: Self.livenessInterval, repeats: true) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.pruneSessions() }
    }
  }

  func stopLivenessChecks() {
    livenessTimer?.invalidate()
    livenessTimer = nil
  }

  /// Removes dead or long-silent sessions. Called by the timer; exposed for tests.
  func pruneSessions() {
    let current = now()
    let alive = sessions.filter { session in
      if let pid = session.context.pid { return isProcessAlive(pid) }
      return current.timeIntervalSince(lastActivity[session.id] ?? current) <= Self.silenceTimeout
    }
    if alive.count != sessions.count {
      sessions = alive
      lastActivity = lastActivity.filter { id, _ in alive.contains { $0.id == id } }
    }
  }

  private static func merged(_ old: ClaudeHookContext, with new: ClaudeHookContext)
    -> ClaudeHookContext
  {
    ClaudeHookContext(
      pid: new.pid ?? old.pid,
      cmuxWorkspaceID: new.cmuxWorkspaceID ?? old.cmuxWorkspaceID,
      cmuxSurfaceID: new.cmuxSurfaceID ?? old.cmuxSurfaceID,
      cmuxSocketPath: new.cmuxSocketPath ?? old.cmuxSocketPath,
      cmuxCLIPath: new.cmuxCLIPath ?? old.cmuxCLIPath,
      herdrPaneID: new.herdrPaneID ?? old.herdrPaneID,
      herdrSocketPath: new.herdrSocketPath ?? old.herdrSocketPath,
      herdrCLIPath: new.herdrCLIPath ?? old.herdrCLIPath
    )
  }
}
