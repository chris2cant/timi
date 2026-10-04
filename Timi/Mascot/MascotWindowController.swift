import AppKit
import ColorSync
import SwiftUI

@MainActor
private final class DraggableHostingView<Content: View>: NSHostingView<Content> {
  var didBeginDragging: (() -> Void)?
  var didFinishDragging: ((CGPoint) -> Void)?
  var didClick: (() -> Void)?
  var constrainedOrigin: ((CGPoint, CGPoint) -> CGPoint)?
  var draggableRect = CGRect.zero

  private var initialPointerLocation: CGPoint?
  private var initialWindowOrigin: CGPoint?
  private var draggedDistance: CGFloat = 0
  private var reportedDrag = false

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
    draggedDistance = 0
    reportedDrag = false
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
    draggedDistance = max(draggedDistance, hypot(delta.x, delta.y))
    if draggedDistance >= 3, !reportedDrag {
      reportedDrag = true
      didBeginDragging?()
    }

    let proposedOrigin = CGPoint(
      x: initialWindowOrigin.x + delta.x,
      y: initialWindowOrigin.y + delta.y
    )
    window.setFrameOrigin(constrainedOrigin?(proposedOrigin, pointerLocation) ?? proposedOrigin)
  }

  override func mouseUp(with event: NSEvent) {
    if draggedDistance < 3 {
      didClick?()
    }
    didFinishDragging?(NSEvent.mouseLocation)

    initialPointerLocation = nil
    initialWindowOrigin = nil
    draggedDistance = 0
    reportedDrag = false
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

  var offsetDidChange: ((CGSize, String?) -> Void)?

  init(appState: AppState) {
    let interactionState = MascotInteractionState()
    self.interactionState = interactionState
    chatWindowController = ChatWindowController(appState: appState)
    panel = NSPanel(
      contentRect: CGRect(origin: .zero, size: Self.windowSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    super.init()

    interactionState.activationHandler = { [weak self] in
      self?.toggleChat()
    }

    let hostingView = DraggableHostingView(
      rootView: MascotView(interactionState: interactionState)
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
      self?.chatWindowController.hide()
    }
    hostingView.didFinishDragging = { [weak self] pointerLocation in
      self?.dragEnded(at: pointerLocation)
    }
    panel.contentView = hostingView
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.isMovable = true
    panel.isReleasedWhenClosed = false
    panel.isFloatingPanel = true
    panel.becomesKeyOnlyIfNeeded = true
    panel.hidesOnDeactivate = false
    panel.level = .screenSaver
    panel.animationBehavior = .none
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenParametersDidChange),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  func show(at position: MascotPosition, offset: CGSize, displayUUID: String?) {
    move(to: position, offset: offset, displayUUID: displayUUID)
    panel.orderFrontRegardless()
  }

  func setVisible(_ isVisible: Bool) {
    if isVisible {
      move(
        to: currentPosition,
        offset: currentOffset,
        displayUUID: currentDisplayUUID
      )
      panel.orderFrontRegardless()
    } else {
      chatWindowController.hide()
      panel.orderOut(nil)
    }
  }

  func move(to position: MascotPosition, offset: CGSize, displayUUID: String?) {
    currentPosition = position
    currentOffset = offset
    let preferredUUID = displayUUID ?? currentDisplayUUID
    guard let screen = resolvedScreen(preferredUUID: preferredUUID) else { return }
    currentDisplayUUID = Self.displayUUID(for: screen) ?? preferredUUID
    let visibleFrame = screen.visibleFrame

    let requestedOrigin = PositionCalculator.origin(
      for: position,
      in: visibleFrame,
      windowSize: Self.mascotSize,
      margin: Self.edgeMargin,
      offset: offset
    )
    let mascotOrigin = PositionCalculator.clamped(
      origin: requestedOrigin,
      windowSize: Self.mascotSize,
      to: screen.frame
    )
    panel.setFrameOrigin(panelOrigin(forMascotOrigin: mascotOrigin))
    updateAttachmentEdges(at: mascotOrigin, on: screen)
    if chatWindowController.isVisible {
      chatWindowController.move(attachedTo: mascotFrame, on: screen)
    }
  }

  private func dragEnded(at pointerLocation: CGPoint) {
    guard let screen = screenContaining(pointerLocation)
      ?? screenContainingMost(of: mascotFrame)
      ?? resolvedScreen(preferredUUID: currentDisplayUUID) else {
      return
    }
    let screenFrame = screen.frame

    let snappedOrigin = PositionCalculator.snappedToEdges(
      origin: mascotFrame.origin,
      windowSize: Self.mascotSize,
      in: screenFrame,
      threshold: Self.edgeSnapThreshold
    )
    panel.setFrameOrigin(panelOrigin(forMascotOrigin: snappedOrigin))
    updateAttachmentEdges(at: snappedOrigin, on: screen)
    if chatWindowController.isVisible {
      chatWindowController.move(attachedTo: mascotFrame, on: screen)
    }

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
    let frames = screens.map(\.frame)
    let preferredIndex = currentDisplayUUID.flatMap { uuid in
      screens.firstIndex { Self.displayUUID(for: $0) == uuid }
    }
    guard let index = PositionCalculator.indexOfFrameContainingMost(
      windowFrame,
      among: frames,
      preferredIndex: preferredIndex
    ) else {
      return nil
    }
    return screens[index]
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
    let screen = screenContainingMost(of: mascotFrame)
      ?? resolvedScreen(preferredUUID: currentDisplayUUID)
    chatWindowController.toggle(attachedTo: mascotFrame, on: screen)
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
    let screen = screenContaining(pointerLocation)
      ?? screenContainingMost(of: proposedFrame)
      ?? resolvedScreen(preferredUUID: currentDisplayUUID)

    guard let screen else { return proposedOrigin }
    let constrainedMascotOrigin = PositionCalculator.clamped(
      origin: proposedMascotOrigin,
      windowSize: Self.mascotSize,
      to: screen.frame
    )
    let previewMascotOrigin = PositionCalculator.snappedToEdges(
      origin: constrainedMascotOrigin,
      windowSize: Self.mascotSize,
      in: screen.frame,
      threshold: Self.edgeSnapThreshold
    )
    updateAttachmentEdges(at: previewMascotOrigin, on: screen)
    return panelOrigin(forMascotOrigin: previewMascotOrigin)
  }

  private func updateAttachmentEdges(at origin: CGPoint, on screen: NSScreen) {
    interactionState.updateAttachmentEdges(
      PositionCalculator.attachmentEdges(
        origin: origin,
        windowSize: Self.mascotSize,
        in: screen.frame
      )
    )
  }

  private func screenContaining(_ point: CGPoint) -> NSScreen? {
    let screens = NSScreen.screens
    let frames = screens.map(\.frame)
    let preferredIndex = currentDisplayUUID.flatMap { uuid in
      screens.firstIndex { Self.displayUUID(for: $0) == uuid }
    }
    guard let index = PositionCalculator.indexOfFrame(
      containing: point,
      among: frames,
      preferredIndex: preferredIndex
    ) else {
      return nil
    }
    return screens[index]
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
