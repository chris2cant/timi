import AppKit
import os

/// Brings the terminal of a Claude Code session to the front.
///
/// Uses the herdr and cmux CLIs and `NSRunningApplication` rather than Apple Events,
/// so no automation permission is needed.
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
    // herdr is a TUI inside a host terminal: select the agent pane first, then
    // bring the host terminal (cmux) forward.
    if let paneID = context.herdrPaneID {
      run(
        "herdr", candidates: [context.herdrCLIPath].compactMap(\.self) + herdrFallbackCLIPaths,
        arguments: ["agent", "focus", paneID],
        socketVariable: ("HERDR_SOCKET_PATH", context.herdrSocketPath))
    }

    guard let cmux = NSRunningApplication
      .runningApplications(withBundleIdentifier: cmuxBundleIdentifier).first else {
      return
    }
    if let workspaceID = context.cmuxWorkspaceID {
      run(
        "cmux", candidates: [context.cmuxCLIPath].compactMap(\.self) + cmuxFallbackCLIPaths,
        arguments: ["select-workspace", "--workspace", workspaceID],
        socketVariable: ("CMUX_SOCKET_PATH", context.cmuxSocketPath))
    }
    // `activate()` from a background app can be refused by cooperative activation
    // (macOS 14+); asking Launch Services to open the running app is honored.
    guard let bundleURL = cmux.bundleURL else { return }
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
    guard let cliPath = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
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
