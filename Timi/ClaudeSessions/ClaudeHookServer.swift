import Foundation
import Network
import os

/// Listens on a Unix domain socket for Claude Code hook requests.
final class ClaudeHookServer: @unchecked Sendable {
  static var defaultSocketURL: URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return support.appending(path: "Timi", directoryHint: .isDirectory)
      .appending(path: "claude-hooks.sock")
  }

  let socketURL: URL

  private let onRequest: @MainActor (ClaudeHookRequest) -> Void
  private let queue = DispatchQueue(label: "io.github.chris2cant.Timi.ClaudeHookServer")
  private let logger = Logger(subsystem: "io.github.chris2cant.Timi", category: "ClaudeHooks")
  // Only touched from start() and stop(), which are called from the main actor.
  private var listener: NWListener?

  init(
    socketURL: URL = ClaudeHookServer.defaultSocketURL,
    onRequest: @escaping @MainActor (ClaudeHookRequest) -> Void
  ) {
    self.socketURL = socketURL
    self.onRequest = onRequest
  }

  func start() throws {
    guard listener == nil else { return }
    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: socketURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    // A socket left by a crashed run would make the bind fail.
    try? fileManager.removeItem(at: socketURL)

    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .unix(path: socketURL.path)
    let listener = try NWListener(using: parameters)
    listener.newConnectionHandler = { [weak self] connection in
      self?.accept(connection)
    }
    let ready = DispatchSemaphore(value: 0)
    listener.stateUpdateHandler = { [logger] state in
      switch state {
      case .ready:
        ready.signal()
      case .failed(let error):
        logger.error("Hook listener failed: \(error.localizedDescription, privacy: .public)")
        ready.signal()
      default:
        break
      }
    }
    listener.start(queue: queue)
    // Binding is near-instant; waiting avoids refused connections from a hook fired right after launch.
    _ = ready.wait(timeout: .now() + 1)
    self.listener = listener
  }

  func stop() {
    listener?.cancel()
    listener = nil
    try? FileManager.default.removeItem(at: socketURL)
  }

  private func accept(_ connection: NWConnection) {
    let handler = ConnectionHandler(
      connection: connection, queue: queue, logger: logger, onRequest: onRequest)
    handler.start()
  }
}

/// Reads one request from a connection, answers it and closes. Confined to the server queue.
private final class ConnectionHandler: @unchecked Sendable {
  private static let timeout: DispatchTimeInterval = .seconds(2)
  private static let noContent = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
  private static let badRequest = "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"

  private let connection: NWConnection
  private let queue: DispatchQueue
  private let logger: Logger
  private let onRequest: @MainActor (ClaudeHookRequest) -> Void
  private var buffer = Data()
  private var finished = false

  init(
    connection: NWConnection,
    queue: DispatchQueue,
    logger: Logger,
    onRequest: @escaping @MainActor (ClaudeHookRequest) -> Void
  ) {
    self.connection = connection
    self.queue = queue
    self.logger = logger
    self.onRequest = onRequest
  }

  func start() {
    connection.start(queue: queue)
    queue.asyncAfter(deadline: .now() + Self.timeout) { [self] in
      guard !finished else { return }
      finished = true
      connection.cancel()
    }
    receive()
  }

  private func receive() {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
      [self] data, _, isComplete, error in
      guard !finished else { return }
      if let data { buffer.append(data) }

      switch ClaudeHookRequestParser.parse(buffer) {
      case .request(let request):
        reply(Self.noContent)
        let event = request.event
        logger.debug(
          "Hook \(event.hookEventName, privacy: .public) session \(event.sessionID, privacy: .public) pid \(request.context.pid ?? 0)"
        )
        // The main queue is FIFO, unlike unstructured tasks: event order drives the state machine.
        let onRequest = onRequest
        DispatchQueue.main.async { MainActor.assumeIsolated { onRequest(request) } }
      case .invalid:
        logger.error("Rejected invalid hook request (\(self.buffer.count) bytes)")
        reply(Self.badRequest)
      case .needsMoreData:
        if error != nil || isComplete {
          finished = true
          connection.cancel()
        } else {
          receive()
        }
      }
    }
  }

  private func reply(_ response: String) {
    finished = true
    connection.send(
      content: Data(response.utf8),
      completion: .contentProcessed { [connection] _ in connection.cancel() })
  }
}
