import AppKit
import Combine
import SwiftUI

@MainActor
private final class SessionMascotHostingView: NSHostingView<SessionMascotView> {
  var didClick: (() -> Void)?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard isClickable(convert(point, from: superview)) else { return nil }
    return super.hitTest(point)
  }

  override func mouseDown(with event: NSEvent) {}

  override func mouseUp(with event: NSEvent) {
    if isClickable(convert(event.locationInWindow, from: nil)) {
      didClick?()
    }
  }

  private func isClickable(_ localPoint: CGPoint) -> Bool {
    // Silhouette and label only: the room left for the hop and the "!" bubble stays
    // click-through.
    let frames = SessionMascotView.frames(for: rootView.edges, isAsleep: rootView.isAsleep)
    let y = isFlipped ? bounds.height - localPoint.y : localPoint.y
    return frames.body.union(frames.label).contains(CGPoint(x: localPoint.x, y: y))
  }
}

/// Owns one floating panel per Claude Code session, lined up next to the main mascot.
@MainActor
final class SessionMascotsWindowController {
  private static let gap: CGFloat = 4
  /// Keeps the joins of the main mascot and of the first session mascot apart.
  private static let leadingGap: CGFloat = 24

  private struct Entry {
    let panel: NSPanel
    let hostingView: SessionMascotHostingView
  }

  private var sessions: [ClaudeSession] = []
  private var entries: [String: Entry] = [:]
  private var anchor: (mascotFrame: CGRect, screen: NSScreen)?
  private var isVisible = true
  private var subscription: AnyCancellable?

  init(store: ClaudeSessionStore) {
    // @Published emits on the main actor, from the store's mutations.
    subscription = store.$sessions.sink { [weak self] sessions in
      self?.apply(sessions)
    }
  }

  func updateAnchor(mascotFrame: CGRect, screen: NSScreen) {
    anchor = (mascotFrame, screen)
    layout()
  }

  func setVisible(_ visible: Bool) {
    isVisible = visible
    if visible {
      layout()
    } else {
      entries.values.forEach { $0.panel.orderOut(nil) }
    }
  }

  private func apply(_ sessions: [ClaudeSession]) {
    self.sessions = sessions
    let ids = Set(sessions.map(\.id))
    for (id, entry) in entries where !ids.contains(id) {
      entry.panel.close()
      entries[id] = nil
    }
    for session in sessions where entries[session.id] == nil {
      entries[session.id] = makeEntry(for: session)
    }
    layout()
  }

  private func layout() {
    let placements = anchor.map { anchor in
      SessionMascotLayout.placements(
        count: sessions.count,
        windowSize: SessionMascotView.windowSize,
        attachedTo: anchor.mascotFrame,
        // Same bounds as the main mascot, which may sit over the Dock area.
        in: anchor.screen.frame,
        gap: Self.gap,
        leadingGap: Self.leadingGap
      )
    } ?? []

    for (index, session) in sessions.enumerated() {
      guard let entry = entries[session.id] else { continue }
      let placement = placements.indices.contains(index) ? placements[index] : nil
      let edges = placement?.edges ?? []
      let rootView = entry.hostingView.rootView
      // Replacing the root view keeps the SwiftUI @State of the same view identity.
      if rootView.session != session || rootView.edges != edges {
        entry.hostingView.rootView = view(for: session, edges: edges, in: entry.panel)
      }
      if isVisible, let placement {
        entry.panel.setFrameOrigin(placement.origin)
        entry.panel.orderFrontRegardless()
      }
    }
  }

  private func makeEntry(for session: ClaudeSession) -> Entry {
    let panel = NSPanel(
      contentRect: CGRect(origin: .zero, size: SessionMascotView.windowSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    let hostingView = SessionMascotHostingView(rootView: view(for: session, edges: [], in: panel))
    let id = session.id
    hostingView.didClick = { [weak self] in
      guard let session = self?.sessions.first(where: { $0.id == id }) else { return }
      SessionFocuser.focus(session)
    }
    panel.contentView = hostingView
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.isReleasedWhenClosed = false
    panel.isFloatingPanel = true
    panel.becomesKeyOnlyIfNeeded = true
    panel.hidesOnDeactivate = false
    panel.level = .screenSaver
    panel.animationBehavior = .none
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    return Entry(panel: panel, hostingView: hostingView)
  }

  private func view(
    for session: ClaudeSession,
    edges: MascotAttachmentEdges,
    in panel: NSPanel
  ) -> SessionMascotView {
    let body = SessionMascotView.frames(for: edges, isAsleep: session.status == .idle).body
    let center = CGPoint(x: body.midX, y: body.midY)
    return SessionMascotView(session: session, edges: edges) { [weak panel] in
      guard let panel else { return .zero }
      let pointer = NSEvent.mouseLocation
      return CGVector(
        dx: pointer.x - (panel.frame.minX + center.x),
        dy: pointer.y - (panel.frame.minY + center.y)
      )
    }
  }
}
