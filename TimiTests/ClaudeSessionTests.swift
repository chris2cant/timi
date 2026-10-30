import XCTest

@testable import Timi

private func event(
  _ name: String, session: String = "s1", cwd: String? = nil, agent: String? = nil,
  tool: String? = nil, notification: String? = nil, source: String? = nil
) -> ClaudeHookEvent {
  ClaudeHookEvent(
    hookEventName: name, sessionID: session, cwd: cwd, agentID: agent, toolName: tool,
    notificationType: notification, source: source)
}

final class ClaudeSessionStateTests: XCTestCase {
  private func next(_ current: ClaudeSessionStatus?, _ event: ClaudeHookEvent) -> ClaudeSessionStatus? {
    ClaudeSession.nextStatus(from: current, on: event)
  }

  func testTransitionTable() {
    for name in [
      "UserPromptSubmit", "PostToolUse", "PostToolUseFailure", "SubagentStart",
    ] {
      XCTAssertEqual(next(.idle, event(name)), .working, name)
    }
    XCTAssertEqual(next(.working, event("SubagentStop", agent: "a1")), .working)
    XCTAssertEqual(next(.yourTurn, event("SubagentStop", agent: "a1")), .yourTurn)
    XCTAssertEqual(next(.idle, event("SessionStart")), .idle)
    XCTAssertEqual(next(.working, event("SessionStart")), .idle)
    XCTAssertEqual(next(.idle, event("PreToolUse", tool: "Bash")), .working)
    XCTAssertEqual(next(.idle, event("PreToolUse", tool: "AskUserQuestion")), .needsYou)
    XCTAssertEqual(next(.working, event("PreToolUse", tool: "ExitPlanMode")), .needsYou)
    XCTAssertEqual(next(.working, event("PermissionRequest")), .needsYou)
    XCTAssertEqual(next(.working, event("Notification", notification: "permission_prompt")), .needsYou)
    XCTAssertEqual(next(.working, event("Notification", notification: "elicitation_dialog")), .needsYou)
    XCTAssertEqual(next(.working, event("Notification", notification: "idle_prompt")), .yourTurn)
    XCTAssertEqual(next(.working, event("Notification", notification: "other")), .working)
    XCTAssertEqual(next(.working, event("Stop")), .yourTurn)
    XCTAssertNil(next(.working, event("SessionEnd")))
  }

  func testIdlePromptDoesNotDowngradeNeedsYou() {
    XCTAssertEqual(next(.needsYou, event("Notification", notification: "idle_prompt")), .needsYou)
  }

  func testSubAgentActivityKeepsNeedsYou() {
    XCTAssertEqual(next(.needsYou, event("PostToolUse", agent: "a1")), .needsYou)
    XCTAssertEqual(next(.needsYou, event("PreToolUse", agent: "a1", tool: "Bash")), .needsYou)
    XCTAssertEqual(next(.needsYou, event("PostToolUse")), .working)
    XCTAssertEqual(next(.yourTurn, event("PostToolUse", agent: "a1")), .working)
  }

  func testUnknownSessionIsCreatedByFirstEvent() {
    XCTAssertEqual(next(nil, event("SessionStart")), .idle)
    XCTAssertEqual(next(nil, event("Stop")), .yourTurn)
    XCTAssertEqual(next(nil, event("PostToolUse")), .working)
    XCTAssertEqual(next(nil, event("TaskCompleted")), .idle)
    XCTAssertEqual(next(nil, event("Notification", notification: "auth_success")), .idle)
    XCTAssertNil(next(nil, event("SessionEnd")))
  }

  func testUnlistedEventsAndCompactKeepStatus() {
    XCTAssertEqual(next(.working, event("TaskCompleted")), .working)
    XCTAssertEqual(next(.yourTurn, event("PreCompact")), .yourTurn)
    XCTAssertEqual(next(.working, event("SessionStart", source: "compact")), .working)
    XCTAssertEqual(next(.working, event("SessionStart", source: "resume")), .idle)
  }

  func testProjectName() {
    let repos: Set<String> = ["/work/app/.git"]
    let exists: (String) -> Bool = { repos.contains($0) }
    XCTAssertEqual(
      ClaudeSession.projectName(forWorkingDirectory: "/work/app/src/deep", fileExists: exists), "app")
    XCTAssertEqual(
      ClaudeSession.projectName(forWorkingDirectory: "/other/place", fileExists: exists), "place")
    XCTAssertEqual(ClaudeSession.projectName(forWorkingDirectory: nil, fileExists: exists), "Claude")
    XCTAssertEqual(ClaudeSession.projectName(forWorkingDirectory: "", fileExists: exists), "Claude")
  }
}

final class ClaudeHookRequestParserTests: XCTestCase {
  private let body = #"{"hook_event_name":"Stop","session_id":"s1","tool_input":{"x":1}}"#

  private func request(
    headers: [String] = [], body: String? = nil, contentLength: Bool = true
  ) -> Data {
    let body = body ?? self.body
    var lines = ["POST /claude-hook HTTP/1.1", "Host: timi"] + headers
    if contentLength { lines.append("Content-Length: \(body.utf8.count)") }
    return Data((lines.joined(separator: "\r\n") + "\r\n\r\n" + body).utf8)
  }

  private func parsed(_ data: Data) -> ClaudeHookRequest? {
    if case .request(let request) = ClaudeHookRequestParser.parse(data) { return request }
    return nil
  }

  func testCompleteRequestWithContext() throws {
    let data = request(headers: [
      "X-Timi-Pid: 123", "X-Timi-Cmux-Workspace: ws", "X-Timi-Cmux-Surface: sf",
      "X-Timi-Cmux-Socket: /tmp/c.sock", "X-Timi-Cmux-Cli: /bin/cmux", "X-Timi-Herdr-Pane: w1:p2",
      "X-Timi-Herdr-Socket: /tmp/h.sock", "X-Timi-Herdr-Cli: /bin/herdr",
    ])
    let parsed = try XCTUnwrap(parsed(data))
    XCTAssertEqual(parsed.event.hookEventName, "Stop")
    XCTAssertEqual(parsed.event.sessionID, "s1")
    XCTAssertEqual(
      parsed.context,
      ClaudeHookContext(
        pid: 123, cmuxWorkspaceID: "ws", cmuxSurfaceID: "sf", cmuxSocketPath: "/tmp/c.sock",
        cmuxCLIPath: "/bin/cmux", herdrPaneID: "w1:p2", herdrSocketPath: "/tmp/h.sock",
        herdrCLIPath: "/bin/herdr"))
  }

  func testSplitRequestNeedsMoreData() {
    let data = request()
    for cut in [10, data.count - 5] {
      XCTAssertEqual(ClaudeHookRequestParser.parse(data.prefix(cut)), .needsMoreData)
    }
    XCTAssertNotNil(parsed(data))
  }

  func testEmptyHeadersAndInvalidPidAreNil() throws {
    for pid in ["", "  ", "abc", "0", "-4"] {
      let data = request(headers: ["X-Timi-Pid: \(pid)", "X-Timi-Cmux-Workspace:"])
      let context = try XCTUnwrap(parsed(data)).context
      XCTAssertEqual(context, ClaudeHookContext(), pid)
    }
  }

  func testHeaderNamesAreCaseInsensitive() throws {
    let context = try XCTUnwrap(parsed(request(headers: ["x-timi-PID: 7", "CONTENT-type: x"]))).context
    XCTAssertEqual(context.pid, 7)
  }

  func testInvalidPayloads() {
    XCTAssertEqual(ClaudeHookRequestParser.parse(request(body: "not json")), .invalid)
    XCTAssertEqual(ClaudeHookRequestParser.parse(request(contentLength: false)), .invalid)
    XCTAssertEqual(
      ClaudeHookRequestParser.parse(request(body: #"{"hook_event_name":"Stop","session_id":""}"#)),
      .invalid)
    XCTAssertEqual(
      ClaudeHookRequestParser.parse(Data(repeating: 0x61, count: 2_000_000)), .invalid)
  }
}

@MainActor
final class ClaudeSessionStoreTests: XCTestCase {
  private var clock = Date(timeIntervalSince1970: 1_000)
  private var deadPIDs: Set<pid_t> = []

  private func makeStore() -> ClaudeSessionStore {
    ClaudeSessionStore(now: { [unowned self] in clock }, isProcessAlive: { [unowned self] in !deadPIDs.contains($0) })
  }

  private func request(
    _ name: String, session: String = "s1", pid: pid_t? = nil, workspace: String? = nil
  ) -> ClaudeHookRequest {
    ClaudeHookRequest(
      event: event(name, session: session, cwd: "/tmp/proj"),
      context: ClaudeHookContext(pid: pid, cmuxWorkspaceID: workspace))
  }

  func testCreationOrderAndStatusUpdates() {
    let store = makeStore()
    store.handle(request("SessionStart", session: "a"))
    store.handle(request("Stop", session: "b"))
    store.handle(request("UserPromptSubmit", session: "a"))

    XCTAssertEqual(store.sessions.map(\.id), ["a", "b"])
    XCTAssertEqual(store.sessions.map(\.status), [.working, .yourTurn])
    XCTAssertEqual(store.sessions[0].projectName, "proj")
  }

  func testContextIsMergedAndSessionEndRemoves() {
    let store = makeStore()
    store.handle(request("SessionStart", pid: 42))
    store.handle(request("PostToolUse", workspace: "ws"))
    XCTAssertEqual(store.sessions[0].context.pid, 42)
    XCTAssertEqual(store.sessions[0].context.cmuxWorkspaceID, "ws")

    store.handle(request("SessionEnd"))
    XCTAssertTrue(store.sessions.isEmpty)
  }

  func testPruneRemovesDeadPIDAndLongSilentSessionsWithoutPID() {
    let store = makeStore()
    store.handle(request("Stop", session: "dead", pid: 1))
    store.handle(request("Stop", session: "alive", pid: 2))
    store.handle(request("Stop", session: "silent"))
    deadPIDs = [1]
    clock.addTimeInterval(2 * 3600 - 1)
    store.pruneSessions()
    XCTAssertEqual(store.sessions.map(\.id), ["alive", "silent"])

    clock.addTimeInterval(2)
    store.pruneSessions()
    XCTAssertEqual(store.sessions.map(\.id), ["alive"])
  }

  func testSeedAddsLiveUnknownSessions() {
    let store = makeStore()
    store.handle(request("PermissionRequest", session: "known"))
    deadPIDs = [3]
    store.seed([
      ClaudeSessionDiscovery.Entry(sessionId: "known", pid: 1, status: "busy"),
      ClaudeSessionDiscovery.Entry(sessionId: "busy", pid: 2, cwd: "/tmp/proj", status: "busy"),
      ClaudeSessionDiscovery.Entry(sessionId: "dead", pid: 3, status: "busy"),
      ClaudeSessionDiscovery.Entry(sessionId: "idle", pid: 4, status: "idle"),
      ClaudeSessionDiscovery.Entry(sessionId: "idle", pid: 5, status: "busy"),
    ])

    XCTAssertEqual(store.sessions.map(\.id), ["known", "busy", "idle"])
    XCTAssertEqual(store.sessions.map(\.status), [.needsYou, .working, .idle])
    XCTAssertEqual(store.sessions[1].projectName, "proj")
    XCTAssertEqual(store.sessions[2].context.pid, 4)
  }

  func testHeartbeatKeepsSilentSessionAlive() {
    let store = makeStore()
    store.handle(request("Stop"))
    clock.addTimeInterval(3600)
    store.handle(request("PostToolUse"))
    clock.addTimeInterval(3600 + 60)
    store.pruneSessions()
    XCTAssertEqual(store.sessions.count, 1)
  }
}

final class ClaudeSessionDiscoveryTests: XCTestCase {
  func testEntriesAreReadFromJSONFilesOldestFirst() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let files = [
      "20.json": #"{"pid":20,"sessionId":"new","cwd":"/a","status":"busy","startedAt":2000,"kind":"interactive"}"#,
      "10.json": #"{"pid":10,"sessionId":"old","status":"idle","startedAt":1000}"#,
      "30.json": #"{"pid":30,"cwd":"/no-session-id"}"#,
      "40.json": "not json",
      "10.abc.key": "secret",
    ]
    for (name, content) in files {
      try Data(content.utf8).write(to: directory.appending(path: name))
    }

    let entries = ClaudeSessionDiscovery.entries(in: directory)
    XCTAssertEqual(entries.map(\.sessionId), ["old", "new"])
    XCTAssertEqual(entries[1].cwd, "/a")
    XCTAssertEqual(entries.map(ClaudeSessionDiscovery.status(of:)), [.idle, .working])
  }

  func testMissingDirectoryHasNoEntries() {
    XCTAssertEqual(ClaudeSessionDiscovery.entries(in: URL(filePath: "/nonexistent-timi")), [])
  }

  func testInvalidPIDIsRejected() {
    XCTAssertNil(ClaudeSessionDiscovery.entry(from: Data(#"{"pid":0,"sessionId":"s"}"#.utf8)))
  }
}

final class ClaudeHookServerTests: XCTestCase {
  func testCurlRequestIsAnsweredAndDelivered() async throws {
    let path = FileManager.default.temporaryDirectory
      .appending(path: "timi-\(UUID().uuidString.prefix(6)).sock")
    let received = expectation(description: "request received")
    let box = LockedBox<ClaudeHookRequest?>(nil)
    let server = ClaudeHookServer(socketURL: path) { request in
      box.set(request)
      received.fulfill()
    }
    try server.start()
    defer { server.stop() }

    let code = try await Task.detached {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
      process.arguments = [
        "--unix-socket", path.path, "-s", "-m", "3", "-o", "/dev/null", "-w", "%{http_code}",
        "-H", "X-Timi-Pid: 123",
        "--data-binary", #"{"hook_event_name":"Stop","session_id":"s1"}"#,
        "http://timi/claude-hook",
      ]
      let pipe = Pipe()
      process.standardOutput = pipe
      try process.run()
      process.waitUntilExit()
      return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }.value

    XCTAssertEqual(code, "204")
    await fulfillment(of: [received], timeout: 3)
    XCTAssertEqual(box.value?.event.sessionID, "s1")
    XCTAssertEqual(box.value?.context.pid, 123)
  }
}

private final class LockedBox<T: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: T
  init(_ value: T) { stored = value }
  var value: T { lock.withLock { stored } }
  func set(_ value: T) { lock.withLock { stored = value } }
}
