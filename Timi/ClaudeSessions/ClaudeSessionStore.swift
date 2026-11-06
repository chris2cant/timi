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
  private var reactionSerial = 0

  private static let livenessInterval: TimeInterval = 10
  private static let silenceTimeout: TimeInterval = 5 * 60 * 60

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
    let current = index.map { sessions[$0].status }
    guard let status = ClaudeSession.nextStatus(from: current, on: event) else {
      if let index { sessions.remove(at: index) }
      lastActivity[event.sessionID] = nil
      return
    }

    lastActivity[event.sessionID] = now()
    var reaction: ClaudeSessionReaction?
    if let kind = ClaudeSession.reactionKind(for: event, from: current) {
      reactionSerial += 1
      reaction = ClaudeSessionReaction(kind: kind, serial: reactionSerial)
    }
    guard let index else {
      sessions.append(
        ClaudeSession(
          id: event.sessionID,
          projectName: ClaudeSession.projectName(forWorkingDirectory: event.cwd),
          status: status,
          context: request.context,
          reaction: reaction
        ))
      return
    }

    var session = sessions[index]
    session.status = status
    session.context = Self.merged(session.context, with: request.context)
    if let reaction { session.reaction = reaction }
    if session != sessions[index] {
      sessions[index] = session
    }
  }

  /// Adds sessions found on disk at launch, skipping known sessions, dead processes
  /// and sessions that would be pruned right away.
  func seed(_ entries: [ClaudeSessionDiscovery.Entry]) {
    var added: [ClaudeSession] = []
    var known = Set(sessions.map(\.id))
    let current = now()
    for entry in entries where isProcessAlive(entry.pid) {
      guard !known.contains(entry.sessionId) else { continue }
      let session = ClaudeSession(
        id: entry.sessionId,
        projectName: ClaudeSession.projectName(forWorkingDirectory: entry.cwd),
        status: ClaudeSessionDiscovery.status(of: entry),
        context: ClaudeHookContext(pid: entry.pid)
      )
      let activity = ClaudeSessionDiscovery.lastActivity(of: entry) ?? current
      guard !Self.isAsleep(session, lastActivity: activity, at: current) else { continue }
      lastActivity[entry.sessionId] = activity
      known.insert(entry.sessionId)
      added.append(session)
    }
    if !added.isEmpty {
      sessions += added
    }
  }

  /// Starts the periodic removal of sessions whose process died or went silent.
  func startLivenessChecks() {
    guard livenessTimer == nil else { return }
    livenessTimer = Timer.scheduledTimer(withTimeInterval: Self.livenessInterval, repeats: true) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.pruneSessions() }
    }
    // Pruning is not time-critical: let macOS coalesce the wake-ups.
    livenessTimer?.tolerance = Self.livenessInterval / 2
  }

  func stopLivenessChecks() {
    livenessTimer?.invalidate()
    livenessTimer = nil
  }

  /// Removes dead or long-silent sessions. Called by the timer; exposed for tests.
  func pruneSessions() {
    let current = now()
    let alive = sessions.filter { session in
      if let pid = session.context.pid, !isProcessAlive(pid) { return false }
      return !Self.isAsleep(session, lastActivity: lastActivity[session.id] ?? current, at: current)
    }
    if alive.count != sessions.count {
      sessions = alive
      lastActivity = lastActivity.filter { id, _ in alive.contains { $0.id == id } }
    }
  }

  /// Silent for longer than `silenceTimeout` with nothing to show. A live process is not
  /// enough to stay: Claude Desktop keeps one per open conversation for days.
  /// The session comes back at its next hook event.
  private static func isAsleep(_ session: ClaudeSession, lastActivity: Date, at current: Date)
    -> Bool
  {
    guard current.timeIntervalSince(lastActivity) > silenceTimeout else { return false }
    // Without a PID, silence is the only end signal. A long tool run or a pending request stays.
    return session.context.pid == nil || [.idle, .yourTurn].contains(session.status)
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
