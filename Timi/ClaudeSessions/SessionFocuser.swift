import AppKit
import os

/// Brings the terminal of a Claude Code session to the front, or its Claude Desktop conversation.
///
/// Uses the herdr and cmux CLIs, a `claude://` link, the process tree and `NSRunningApplication`
/// rather than Apple Events, so no automation permission is needed.
@MainActor
enum SessionFocuser {
  private static let cmuxBundleIdentifier = "com.cmuxterm.app"
  private static let cmuxFallbackCLIPaths = ["/opt/homebrew/bin/cmux", "/usr/local/bin/cmux"]
  private static let herdrFallbackCLIPaths = [
    "\(NSHomeDirectory())/.local/bin/herdr", "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr",
  ]
  nonisolated private static let logger = Logger(
    subsystem: "io.github.chris2cant.Timi",
    category: "ClaudeHooks"
  )

  static func focus(_ session: ClaudeSession) {
    let context = session.context
    // Read at click time: hooks carry no entry point, the session file does.
    if let pid = context.pid,
      let entry = ClaudeSessionDiscovery.entry(pid: pid),
      let url = ClaudeSessionDiscovery.desktopURL(of: entry)
    {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      NSWorkspace.shared.open(url, configuration: configuration)
      return
    }

    // herdr is a TUI inside a host terminal: select the agent pane first, then
    // bring the host terminal (cmux) forward.
    if let paneID = context.herdrPaneID {
      run(
        "herdr", candidates: [context.herdrCLIPath].compactMap(\.self) + herdrFallbackCLIPaths,
        arguments: ["agent", "focus", paneID],
        socketVariable: ("HERDR_SOCKET_PATH", context.herdrSocketPath))
    }

    let cmux = NSRunningApplication
      .runningApplications(withBundleIdentifier: cmuxBundleIdentifier).first
    if let cmux, let workspaceID = context.cmuxWorkspaceID {
      run(
        "cmux", candidates: [context.cmuxCLIPath].compactMap(\.self) + cmuxFallbackCLIPaths,
        arguments: ["select-workspace", "--workspace", workspaceID],
        socketVariable: ("CMUX_SOCKET_PATH", context.cmuxSocketPath))
      bringToFront(cmux)
      return
    }

    // Any other terminal or editor (Terminal, iTerm2, Ghostty, VS Code…): bring forward the
    // app whose process tree runs `claude`. Only the app: picking its window or tab would
    // need Apple Events and an automation permission.
    if let pid = context.pid,
      let hostPID = hostApplicationPID(of: pid, parent: parentPID(of:), isApplication: {
        NSRunningApplication(processIdentifier: $0)?.activationPolicy == .regular
      }),
      let host = NSRunningApplication(processIdentifier: hostPID)
    {
      bringToFront(host)
      return
    }

    // No app in the tree (tmux or herdr server, unknown pid): cmux is the best guess.
    if let cmux { bringToFront(cmux) }
  }

  /// First ancestor of `pid`, itself included, that is a regular app. Stops below launchd.
  nonisolated static func hostApplicationPID(
    of pid: pid_t,
    parent: (pid_t) -> pid_t?,
    isApplication: (pid_t) -> Bool
  ) -> pid_t? {
    var current = pid
    for _ in 0..<64 where current > 1 {
      if isApplication(current) { return current }
      guard let next = parent(current), next != current else { return nil }
      current = next
    }
    return nil
  }

  /// Parent of `pid` from the kernel process table, readable without any permission.
  nonisolated private static func parentPID(of pid: pid_t) -> pid_t? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
    return info.kp_eproc.e_ppid
  }

  private static func bringToFront(_ app: NSRunningApplication) {
    // `activate()` from a background app can be refused by cooperative activation
    // (macOS 14+); asking Launch Services to open the running app is honored.
    guard let bundleURL = app.bundleURL else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
  }

  private static func run(
    _ name: String,
    candidates: [String],
    arguments: [String],
    socketVariable: (name: String, value: String?)
  ) {
    // Paths from hook headers must name the expected CLI, not just any executable.
    guard
      let cliPath = candidates.first(where: {
        URL(fileURLWithPath: $0).lastPathComponent == name
          && FileManager.default.isExecutableFile(atPath: $0)
      })
    else {
      logger.error("\(name, privacy: .public) CLI not found, cannot focus session")
      return
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: cliPath)
    process.arguments = arguments
    var environment = ProcessInfo.processInfo.environment
    if let value = socketVariable.value {
      environment[socketVariable.name] = value
    }
    process.environment = environment
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.terminationHandler = { process in
      guard process.terminationStatus != 0 else { return }
      logger.error(
        "\(name, privacy: .public) \(arguments.first ?? "", privacy: .public) exited with status \(process.terminationStatus)"
      )
    }
    do {
      try process.run()
    } catch {
      logger.error("Failed to run \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }
}
