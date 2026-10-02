import AppKit
import ColorSync
import SwiftUI

@MainActor
private final class DraggableHostingView<Content: View>: NSHostingView<Content> {
  var didFinishDragging: ((CGPoint) -> Void)?
  var didClick: (() -> Void)?

  override func mouseDown(with event: NSEvent) {
    guard let window else {
      super.mouseDown(with: event)
      return
    }

    let initialOrigin = window.frame.origin
    window.performDrag(with: event)

    let distance = hypot(
      window.frame.origin.x - initialOrigin.x,
      window.frame.origin.y - initialOrigin.y
    )
    if distance < 3 {
      didClick?()
    }
    didFinishDragging?(NSEvent.mouseLocation)
  }
}

@MainActor
final class MascotWindowController: NSObject {
  static let windowSize = CGSize(width: 148, height: 104)
  static let edgeMargin: CGFloat = 20
  static let edgeSnapThreshold: CGFloat = 36

  private let panel: NSPanel
  private let interactionState: MascotInteractionState
  private var currentPosition = MascotPosition.bottomRight
  private var currentOffset = CGSize.zero
  private var currentDisplayUUID: String?

  var offsetDidChange: ((CGSize, String?) -> Void)?

  override init() {
    let interactionState = MascotInteractionState()
    self.interactionState = interactionState
    panel = NSPanel(
      contentRect: CGRect(origin: .zero, size: Self.windowSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    super.init()

    let hostingView = DraggableHostingView(
      rootView: MascotView(interactionState: interactionState)
    )
    hostingView.didClick = { [weak interactionState] in
      interactionState?.reactToClick()
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
      windowSize: Self.windowSize,
      margin: Self.edgeMargin,
      offset: offset
    )
    let origin = PositionCalculator.clamped(
      origin: requestedOrigin,
      windowSize: Self.windowSize,
      to: screen.frame
    )
    panel.setFrameOrigin(origin)
  }

  private func dragEnded(at pointerLocation: CGPoint) {
    guard let screen = screenContaining(pointerLocation)
      ?? screenContainingMost(of: panel.frame)
      ?? resolvedScreen(preferredUUID: currentDisplayUUID) else {
      return
    }
    let screenFrame = screen.frame

    let snappedOrigin = PositionCalculator.snappedToEdges(
      origin: panel.frame.origin,
      windowSize: Self.windowSize,
      in: screenFrame,
      threshold: Self.edgeSnapThreshold
    )
    panel.setFrameOrigin(snappedOrigin)

    let anchorOrigin = PositionCalculator.origin(
      for: currentPosition,
      in: screen.visibleFrame,
      windowSize: Self.windowSize,
      margin: Self.edgeMargin
    )
    let offset = CGSize(
      width: panel.frame.minX - anchorOrigin.x,
      height: panel.frame.minY - anchorOrigin.y
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

    return screenContainingMost(of: panel.frame)
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
