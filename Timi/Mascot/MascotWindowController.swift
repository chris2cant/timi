import AppKit
import ColorSync
import SwiftUI

extension NSPanel {
  /// Borderless, transparent panel floating over every app, Space and full-screen window,
  /// shared by the main mascot and the session mascots.
  static func floatingMascotPanel(size: CGSize) -> NSPanel {
    let panel = NSPanel(
      contentRect: CGRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
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
    return panel
  }
}

@MainActor
private final class DraggableHostingView<Content: View>: NSHostingView<Content> {
  private static var dragThreshold: CGFloat { 3 }

  var didBeginDragging: (() -> Void)?
  var didFinishDragging: ((CGPoint) -> Void)?
  var didClick: (() -> Void)?
  var constrainedOrigin: ((CGPoint, CGPoint) -> CGPoint)?
  var draggableRect = CGRect.zero

  private var initialPointerLocation: CGPoint?
  private var initialWindowOrigin: CGPoint?
  private var isDragging = false

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard draggableRect.contains(point) else { return nil }
    return super.hitTest(point)
  }

  override func mouseDown(with event: NSEvent) {
    guard let window else {
      super.mouseDown(with: event)
      return
    }

    initialPointerLocation = NSEvent.mouseLocation
    initialWindowOrigin = window.frame.origin
    isDragging = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard let window,
          let initialPointerLocation,
          let initialWindowOrigin else {
      return
    }

    let pointerLocation = NSEvent.mouseLocation
    let delta = CGPoint(
      x: pointerLocation.x - initialPointerLocation.x,
      y: pointerLocation.y - initialPointerLocation.y
    )
    // Below the threshold the press stays a click and the mascot does not move.
    if !isDragging {
      guard hypot(delta.x, delta.y) >= Self.dragThreshold else { return }
      isDragging = true
      didBeginDragging?()
    }

    let proposedOrigin = CGPoint(
      x: initialWindowOrigin.x + delta.x,
      y: initialWindowOrigin.y + delta.y
    )
    window.setFrameOrigin(constrainedOrigin?(proposedOrigin, pointerLocation) ?? proposedOrigin)
  }

  override func mouseUp(with event: NSEvent) {
    guard initialPointerLocation != nil else { return }
    if isDragging {
      didFinishDragging?(NSEvent.mouseLocation)
    } else {
      didClick?()
    }

    initialPointerLocation = nil
    initialWindowOrigin = nil
    isDragging = false
  }
}

@MainActor
final class MascotWindowController: NSObject {
  nonisolated static let mascotSize = CGSize(width: 148, height: 104)
  nonisolated static let drawingMargin: CGFloat = 22
  nonisolated static let windowSize = CGSize(
    width: mascotSize.width + drawingMargin * 2,
    height: mascotSize.height + drawingMargin * 2
  )
  static let edgeMargin: CGFloat = 20
  static let edgeSnapThreshold: CGFloat = 36

  private let panel: NSPanel
  private let interactionState: MascotInteractionState
  private let chatWindowController: ChatWindowController
  private var currentPosition = MascotPosition.bottomRight
  private var currentOffset = CGSize.zero
  private var currentDisplayUUID: String?

  // Auto-hide. The panel is a borderless NSPanel, so AppKit does not pull it
  // back on screen when it is slid past the screen edge.
  private static let autoHideRevealThickness: CGFloat = 2
  private static let autoHideAnimationDuration: TimeInterval = 0.18
  private let dictationCoordinator: DictationCoordinator
  private var autoHideMode = AutoHideMode.off
  private var autoHideDelay = AppState.defaultAutoHideDelay
  private var autoHideTimer: Timer?
  private var isDragging = false
  private var pointerLeftDate: Date?
  /// Set while the mascot is slid away: the edge, its screen and the mascot origin to restore.
  private var autoHidden: (edge: HideEdge, screenFrame: CGRect, shownOrigin: CGPoint)? {
    didSet { updateEyesPause() }
  }

  var offsetDidChange: ((CGSize, String?) -> Void)?
  /// Displayed mascot frame (no transparent margin, ignoring auto-hide) and its screen.
  var mascotFrameDidChange: ((CGRect, NSScreen) -> Void)?

  init(appState: AppState, dictationCoordinator: DictationCoordinator) {
    let interactionState = MascotInteractionState()
    self.interactionState = interactionState
    self.dictationCoordinator = dictationCoordinator
    chatWindowController = ChatWindowController(
      appState: appState,
      dictationCoordinator: dictationCoordinator
    )
    panel = .floatingMascotPanel(size: Self.windowSize)
    super.init()

    interactionState.activationHandler = { [weak self] in
      if dictationCoordinator.phase.isActive {
        dictationCoordinator.stop()
      } else {
        self?.toggleChat()
      }
    }

    // NSEvent.mouseLocation needs no permission, unlike a global event monitor;
    // the eyes' TimelineView already ticks, so polling is enough.
    interactionState.pointerOffsetProvider = { [weak self] in
      guard let self, panel.isVisible else { return nil }
      let pointer = NSEvent.mouseLocation
      let frame = mascotFrame
      return CGVector(dx: pointer.x - frame.midX, dy: pointer.y - frame.midY)
    }

    let hostingView = DraggableHostingView(
      rootView: MascotView(
        interactionState: interactionState,
        dictationCoordinator: dictationCoordinator
      )
    )
    hostingView.draggableRect = CGRect(
      origin: CGPoint(x: Self.drawingMargin, y: Self.drawingMargin),
      size: Self.mascotSize
    )
    hostingView.constrainedOrigin = { [weak self] proposedOrigin, pointerLocation in
      self?.constrainedWindowOrigin(proposedOrigin, pointerLocation: pointerLocation)
        ?? proposedOrigin
    }
    hostingView.didClick = { [weak interactionState] in
      interactionState?.activate()
    }
    hostingView.didBeginDragging = { [weak self] in
      self?.isDragging = true
      self?.chatWindowController.hide()
    }
    hostingView.didFinishDragging = { [weak self] pointerLocation in
      self?.dragEnded(at: pointerLocation)
    }
    panel.contentView = hostingView

    // Selector-based observers are removed automatically when the observer is deallocated.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenParametersDidChange),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
  }

  func show(at position: MascotPosition, offset: CGSize, displayUUID: String?) {
    move(to: position, offset: offset, displayUUID: displayUUID)
    panel.orderFrontRegardless()
    updateAutoHideTimer()
    updateEyesPause()
  }

  func setVisible(_ isVisible: Bool) {
    if isVisible {
      show(at: currentPosition, offset: currentOffset, displayUUID: currentDisplayUUID)
    } else {
      chatWindowController.hide()
      panel.orderOut(nil)
      updateAutoHideTimer()
      updateEyesPause()
    }
  }

  func setAutoHideDelay(_ delay: TimeInterval) {
    autoHideDelay = delay
  }

  func setAutoHideMode(_ mode: AutoHideMode) {
    autoHideMode = mode
    pointerLeftDate = nil
    if mode == .off, autoHidden != nil {
      reveal()
    }
    updateAutoHideTimer()
  }

  /// Polls the pointer only while auto-hide is on and the mascot is shown.
  private func updateAutoHideTimer() {
    let needsTimer = autoHideMode != .off && panel.isVisible
    guard needsTimer != (autoHideTimer != nil) else { return }
    autoHideTimer?.invalidate()
    autoHideTimer = nil
    guard needsTimer else { return }
    let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.autoHideTick() }
    }
    timer.tolerance = 0.01
    autoHideTimer = timer
  }

  private func autoHideTick() {
    guard !isDragging else { return }
    let pointer = NSEvent.mouseLocation

    if let autoHidden {
      let zone = PositionCalculator.revealZone(
        origin: autoHidden.shownOrigin,
        windowSize: Self.mascotSize,
        in: autoHidden.screenFrame,
        edge: autoHidden.edge,
        thickness: autoHideMode == .peek
          ? AutoHideMode.peekStrip : Self.autoHideRevealThickness
      )
      if zone.contains(pointer) || dictationCoordinator.phase.isActive {
        reveal()
      }
      return
    }

    if chatWindowController.isVisible
      || dictationCoordinator.phase.isActive
      || mascotFrame.insetBy(dx: -12, dy: -12).contains(pointer) {
      pointerLeftDate = nil
      return
    }
    let now = Date()
    let leftDate = pointerLeftDate ?? now
    pointerLeftDate = leftDate
    if now.timeIntervalSince(leftDate) >= autoHideDelay {
      hide()
    }
  }

  private func hide() {
    // Reset first, so a mascot that cannot hide here retries after a full delay, not every tick.
    pointerLeftDate = nil
    let origin = mascotFrame.origin
    guard let screen = screen(forMascotFrame: mascotFrame),
          let edge = PositionCalculator.hideEdge(
            origin: origin,
            windowSize: Self.mascotSize,
            in: screen.frame,
            otherFrames: NSScreen.screens.map(\.frame).filter { $0 != screen.frame }
          ) else {
      return
    }

    autoHidden = (edge, screen.frame, origin)
    // The transparent margin around the mascot would otherwise swallow clicks.
    panel.ignoresMouseEvents = true

    let hiddenOrigin = PositionCalculator.hiddenOrigin(
      origin: origin,
      windowSize: Self.mascotSize,
      in: screen.frame,
      edge: edge,
      visibleStrip: autoHideMode.visibleStrip
    )
    animatePanel(toMascotOrigin: hiddenOrigin)
  }

  private func reveal() {
    guard let autoHidden else { return }
    self.autoHidden = nil
    pointerLeftDate = nil
    panel.ignoresMouseEvents = false
    animatePanel(toMascotOrigin: autoHidden.shownOrigin)
  }

  private func animatePanel(toMascotOrigin origin: CGPoint) {
    let frame = CGRect(origin: panelOrigin(forMascotOrigin: origin), size: panel.frame.size)
    NSAnimationContext.runAnimationGroup { [panel] context in
      context.duration = Self.autoHideAnimationDuration
      panel.animator().setFrame(frame, display: true)
    }
  }

  func move(to position: MascotPosition, offset: CGSize, displayUUID: String?) {
    // Any explicit placement cancels a pending hide; the timer re-hides if needed.
    autoHidden = nil
    panel.ignoresMouseEvents = false
    pointerLeftDate = nil
    currentPosition = position
    currentOffset = offset
    let preferredUUID = displayUUID ?? currentDisplayUUID
    guard let screen = resolvedScreen(preferredUUID: preferredUUID) else { return }
    // Keep the preferred display when it is momentarily missing (e.g. while
    // displays reconnect after sleep): the fallback screen is only a temporary
    // placement, and the next screen-change notification restores the real one.
    let screenUUID = Self.displayUUID(for: screen)
    if preferredUUID == nil || screenUUID == preferredUUID {
      currentDisplayUUID = screenUUID ?? preferredUUID
    }

    let requestedOrigin = PositionCalculator.origin(
      for: position,
      in: screen.visibleFrame,
      windowSize: Self.mascotSize,
      margin: Self.edgeMargin,
      offset: offset
    )
    let mascotOrigin = PositionCalculator.clamped(
      origin: requestedOrigin,
      windowSize: Self.mascotSize,
      to: screen.frame
    )
    place(atMascotOrigin: mascotOrigin, on: screen)
  }

  private func dragEnded(at pointerLocation: CGPoint) {
    isDragging = false
    guard let screen = screenContaining(pointerLocation)
      ?? screen(forMascotFrame: mascotFrame) else {
      return
    }

    let snappedOrigin = PositionCalculator.snappedToEdges(
      origin: mascotFrame.origin,
      windowSize: Self.mascotSize,
      in: screen.frame,
      threshold: Self.edgeSnapThreshold
    )
    place(atMascotOrigin: snappedOrigin, on: screen)

    let anchorOrigin = PositionCalculator.origin(
      for: currentPosition,
      in: screen.visibleFrame,
      windowSize: Self.mascotSize,
      margin: Self.edgeMargin
    )
    let offset = CGSize(
      width: snappedOrigin.x - anchorOrigin.x,
      height: snappedOrigin.y - anchorOrigin.y
    )
    currentOffset = offset
    currentDisplayUUID = Self.displayUUID(for: screen)
    offsetDidChange?(offset, currentDisplayUUID)
  }

  /// Moves the panel so the mascot sits at `origin`, and lets the edges, the session
  /// mascots and the chat bubble follow.
  private func place(atMascotOrigin origin: CGPoint, on screen: NSScreen) {
    panel.setFrameOrigin(panelOrigin(forMascotOrigin: origin))
    updateAttachmentEdges(at: origin, on: screen)
    mascotFrameDidChange?(mascotFrame, screen)
    if chatWindowController.isVisible {
      chatWindowController.move(attachedTo: mascotFrame, on: screen)
    }
  }

  /// Screen showing most of `frame`, else the current display.
  private func screen(forMascotFrame frame: CGRect) -> NSScreen? {
    screenContainingMost(of: frame) ?? resolvedScreen(preferredUUID: currentDisplayUUID)
  }

  private func resolvedScreen(preferredUUID: String?) -> NSScreen? {
    if let preferredUUID,
       let screen = NSScreen.screens.first(where: {
         Self.displayUUID(for: $0) == preferredUUID
       }) {
      return screen
    }

    return screenContainingMost(of: mascotFrame)
      ?? panel.screen
      ?? NSScreen.main
      ?? NSScreen.screens.first
  }

  private func screenContainingMost(of windowFrame: CGRect) -> NSScreen? {
    let screens = NSScreen.screens
    return PositionCalculator.indexOfFrameContainingMost(
      windowFrame,
      among: screens.map(\.frame),
      preferredIndex: currentScreenIndex(in: screens)
    ).map { screens[$0] }
  }

  private func screenContaining(_ point: CGPoint) -> NSScreen? {
    let screens = NSScreen.screens
    return PositionCalculator.indexOfFrame(
      containing: point,
      among: screens.map(\.frame),
      preferredIndex: currentScreenIndex(in: screens)
    ).map { screens[$0] }
  }

  private func currentScreenIndex(in screens: [NSScreen]) -> Int? {
    currentDisplayUUID.flatMap { uuid in
      screens.firstIndex { Self.displayUUID(for: $0) == uuid }
    }
  }

  /// Where the mascot is shown, even while it is slid away by auto-hide.
  var displayedMascotPlacement: (frame: CGRect, screen: NSScreen)? {
    let frame = autoHidden.map { CGRect(origin: $0.shownOrigin, size: Self.mascotSize) }
      ?? mascotFrame
    return screen(forMascotFrame: frame).map { (frame, $0) }
  }

  private var mascotFrame: CGRect {
    CGRect(
      origin: CGPoint(
        x: panel.frame.minX + Self.drawingMargin,
        y: panel.frame.minY + Self.drawingMargin
      ),
      size: Self.mascotSize
    )
  }

  private func panelOrigin(forMascotOrigin origin: CGPoint) -> CGPoint {
    CGPoint(
      x: origin.x - Self.drawingMargin,
      y: origin.y - Self.drawingMargin
    )
  }

  private func toggleChat() {
    chatWindowController.toggle(attachedTo: mascotFrame, on: screen(forMascotFrame: mascotFrame))
  }

  private func constrainedWindowOrigin(
    _ proposedOrigin: CGPoint,
    pointerLocation: CGPoint
  ) -> CGPoint {
    let proposedMascotOrigin = CGPoint(
      x: proposedOrigin.x + Self.drawingMargin,
      y: proposedOrigin.y + Self.drawingMargin
    )
    let proposedFrame = CGRect(origin: proposedMascotOrigin, size: Self.mascotSize)
    guard let screen = screenContaining(pointerLocation)
      ?? screen(forMascotFrame: proposedFrame) else {
      return proposedOrigin
    }

    // snappedToEdges clamps inside the screen first.
    let previewMascotOrigin = PositionCalculator.snappedToEdges(
      origin: proposedMascotOrigin,
      windowSize: Self.mascotSize,
      in: screen.frame,
      threshold: Self.edgeSnapThreshold
    )
    updateAttachmentEdges(at: previewMascotOrigin, on: screen)
    mascotFrameDidChange?(CGRect(origin: previewMascotOrigin, size: Self.mascotSize), screen)
    return panelOrigin(forMascotOrigin: previewMascotOrigin)
  }

  private func updateAttachmentEdges(at origin: CGPoint, on screen: NSScreen) {
    let edges = PositionCalculator.attachmentEdges(
      origin: origin,
      windowSize: Self.mascotSize,
      in: screen.frame
    )
    interactionState.updateAttachmentEdges(edges)
  }

  /// Nobody sees the eyes of a hidden or slid-away mascot: stop their 30 fps timeline.
  private func updateEyesPause() {
    interactionState.updateEyesArePaused(autoHidden != nil || !panel.isVisible)
  }

  private static func displayUUID(for screen: NSScreen) -> String? {
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    guard let screenNumber = screen.deviceDescription[key] as? NSNumber else { return nil }
    let displayID = CGDirectDisplayID(screenNumber.uint32Value)
    let uuid = CGDisplayCreateUUIDFromDisplayID(displayID).takeRetainedValue()
    return CFUUIDCreateString(nil, uuid) as String
  }

  @objc
  private func screenParametersDidChange() {
    move(
      to: currentPosition,
      offset: currentOffset,
      displayUUID: currentDisplayUUID
    )
  }
}
