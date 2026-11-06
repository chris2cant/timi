import AppKit
import Combine
import SwiftUI

extension NSView {
  /// Whether `localPoint` falls on the silhouette or the label of a session-row view;
  /// the room left for the hop and the "!" bubble stays click-through.
  fileprivate func sessionRowContains(
    _ localPoint: CGPoint,
    edges: MascotAttachmentEdges,
    isAsleep: Bool
  ) -> Bool {
    let frames = SessionMascotView.frames(for: edges, isAsleep: isAsleep)
    let y = isFlipped ? bounds.height - localPoint.y : localPoint.y
    return frames.body.union(frames.label).contains(CGPoint(x: localPoint.x, y: y))
  }
}

@MainActor
private final class SessionMascotHostingView: NSHostingView<SessionMascotView> {
  var didClick: (() -> Void)?
  var makeMenu: (() -> NSMenu?)?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard isClickable(convert(point, from: superview)) else { return nil }
    return super.hitTest(point)
  }

  override func mouseDown(with event: NSEvent) {
    if event.modifierFlags.contains(.control) {
      showMenu(for: event)
    }
  }

  override func mouseUp(with event: NSEvent) {
    if !event.modifierFlags.contains(.control), isClickable(convert(event.locationInWindow, from: nil)) {
      didClick?()
    }
  }

  private func isClickable(_ localPoint: CGPoint) -> Bool {
    sessionRowContains(localPoint, edges: rootView.edges, isAsleep: rootView.isAsleep)
  }

  override func rightMouseDown(with event: NSEvent) {
    showMenu(for: event)
  }

  /// AppKit menu rather than SwiftUI `contextMenu`: the panel never becomes key, and the
  /// hit test above already limits clicks to the silhouette and the label.
  private func showMenu(for event: NSEvent) {
    guard let menu = makeMenu?() else { return }
    NSMenu.popUpContextMenu(menu, with: event, for: self)
  }
}

/// Hover-only: shows its tooltip, and lets clicks outside the silhouette and label through.
@MainActor
private final class UsageGaugeHostingView: NSHostingView<UsageGaugeView> {
  override func hitTest(_ point: NSPoint) -> NSView? {
    guard sessionRowContains(convert(point, from: superview), edges: rootView.edges, isAsleep: false) else {
      return nil
    }
    return super.hitTest(point)
  }
}

/// Owns one floating panel per Claude Code session, lined up next to the main mascot.
/// The usage gauge, when there is a reading, closes the line.
@MainActor
final class SessionMascotsWindowController {
  private static let gap: CGFloat = 4
  /// Keeps the joins of the main mascot and of the first session mascot apart.
  private static let leadingGap: CGFloat = 24

  private struct Entry {
    let panel: NSPanel
    let hostingView: SessionMascotHostingView
  }

  private let appState: AppState
  private var sessions: [ClaudeSession] = []
  private var limits: ClaudeUsageLimits?
  private var gauge: (panel: NSPanel, hostingView: UsageGaugeHostingView)?
  private var entries: [String: Entry] = [:]
  private var anchor: (mascotFrame: CGRect, screen: NSScreen)?
  private var isVisible = true
  private var subscriptions: Set<AnyCancellable> = []

  init(store: ClaudeSessionStore, usageStore: ClaudeUsageStore, appState: AppState) {
    self.appState = appState
    // @Published emits on the main actor, from the stores' mutations.
    store.$sessions.sink { [weak self] sessions in
      self?.apply(sessions)
    }
    .store(in: &subscriptions)
    usageStore.$limits.sink { [weak self] limits in
      self?.limits = limits
      self?.layout()
    }
    .store(in: &subscriptions)
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
      gauge?.panel.orderOut(nil)
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
    // Limits are account-wide: they only matter next to at least one session.
    let gaugeLimits = sessions.isEmpty ? nil : limits
    let placements = anchor.map { anchor in
      SessionMascotLayout.placements(
        count: sessions.count + (gaugeLimits == nil ? 0 : 1),
        windowSize: SessionMascotView.windowSize,
        attachedTo: anchor.mascotFrame,
        // Same bounds as the main mascot, which may sit over the Dock area.
        in: anchor.screen.frame,
        gap: Self.gap,
        leadingGap: Self.leadingGap
      )
    } ?? []
    func placement(at index: Int) -> SessionMascotPlacement? {
      placements.indices.contains(index) ? placements[index] : nil
    }

    for (index, session) in sessions.enumerated() {
      guard let entry = entries[session.id] else { continue }
      let placement = placement(at: index)
      let edges = placement?.edges ?? []
      let rootView = entry.hostingView.rootView
      // Replacing the root view keeps the SwiftUI @State of the same view identity.
      let color = appState.color(forProject: session.projectName)
      if rootView.session != session || rootView.edges != edges || rootView.color != color {
        entry.hostingView.rootView = view(for: session, edges: edges, color: color, in: entry.panel)
      }
      show(entry.panel, at: placement)
    }
    layoutGauge(limits: gaugeLimits, placement: placement(at: sessions.count))
  }

  private func layoutGauge(limits: ClaudeUsageLimits?, placement: SessionMascotPlacement?) {
    guard let limits else {
      gauge?.panel.close()
      gauge = nil
      return
    }
    let edges = placement?.edges ?? []
    let gauge = gauge ?? {
      let panel = NSPanel.floatingMascotPanel(size: SessionMascotView.windowSize)
      let hostingView = UsageGaugeHostingView(rootView: UsageGaugeView(limits: limits, edges: edges))
      panel.contentView = hostingView
      return (panel, hostingView)
    }()
    self.gauge = gauge
    let rootView = gauge.hostingView.rootView
    if rootView.limits != limits || rootView.edges != edges {
      gauge.hostingView.rootView = UsageGaugeView(limits: limits, edges: edges)
    }
    show(gauge.panel, at: placement)
  }

  /// Moves a row panel to its placement and orders it in, touching the window server only
  /// when something changes: the main mascot reports its frame on every drag event.
  private func show(_ panel: NSPanel, at placement: SessionMascotPlacement?) {
    guard isVisible, let placement else { return }
    if panel.frame.origin != placement.origin {
      panel.setFrameOrigin(placement.origin)
    }
    if !panel.isVisible {
      panel.orderFrontRegardless()
    }
  }

  private func makeEntry(for session: ClaudeSession) -> Entry {
    let panel = NSPanel.floatingMascotPanel(size: SessionMascotView.windowSize)
    let hostingView = SessionMascotHostingView(rootView: view(for: session, edges: [], color: appState.color(forProject: session.projectName), in: panel))
    let id = session.id
    hostingView.didClick = { [weak self] in
      guard let session = self?.sessions.first(where: { $0.id == id }) else { return }
      SessionFocuser.focus(session)
    }
    hostingView.makeMenu = { [weak self] in
      guard let session = self?.sessions.first(where: { $0.id == id }) else { return nil }
      return self?.colorMenu(for: session.projectName)
    }
    panel.contentView = hostingView
    return Entry(panel: panel, hostingView: hostingView)
  }

  private func colorMenu(for projectName: String) -> NSMenu {
    let menu = NSMenu()
    menu.addItem(.sectionHeader(title: "Couleur de « \(projectName) »"))
    let current = appState.color(forProject: projectName)
    for color in MascotColor.allCases {
      let item = ClosureMenuItem(title: color.title) { [weak self] in
        self?.appState.setColor(color, forProject: projectName)
        self?.layout()
      }
      item.image = .swatch(color)
      item.state = color == current ? .on : .off
      menu.addItem(item)
    }
    return menu
  }

  private func view(
    for session: ClaudeSession,
    edges: MascotAttachmentEdges,
    color: MascotColor,
    in panel: NSPanel
  ) -> SessionMascotView {
    let body = SessionMascotView.frames(for: edges, isAsleep: session.status == .idle).body
    let center = CGPoint(x: body.midX, y: body.midY)
    return SessionMascotView(session: session, edges: edges, color: color) { [weak panel] in
      guard let panel else { return .zero }
      let pointer = NSEvent.mouseLocation
      return CGVector(
        dx: pointer.x - (panel.frame.minX + center.x),
        dy: pointer.y - (panel.frame.minY + center.y)
      )
    }
  }
}

/// Menu item running a closure, for menus built by controllers that are not `NSObject`s.
private final class ClosureMenuItem: NSMenuItem {
  private let handler: () -> Void

  init(title: String, handler: @escaping () -> Void) {
    self.handler = handler
    super.init(title: title, action: #selector(run), keyEquivalent: "")
    target = self
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  @objc private func run() {
    handler()
  }
}

extension NSImage {
  /// Rounded color sample shown next to a palette entry; the outline keeps black visible
  /// on a dark menu.
  fileprivate static func swatch(_ color: MascotColor) -> NSImage {
    NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
      let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
      NSColor(srgbRed: color.rgb.red, green: color.rgb.green, blue: color.rgb.blue, alpha: 1).setFill()
      path.fill()
      NSColor.separatorColor.setStroke()
      path.stroke()
      return true
    }
  }
}
