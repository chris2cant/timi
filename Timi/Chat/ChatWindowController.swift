import AppKit
import SwiftUI

private final class ChatPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

@MainActor
final class ChatWindowController: NSObject, NSWindowDelegate {
  nonisolated static let windowSize = CGSize(width: 380, height: 420)

  private let panel: NSPanel
  private let state: ChatState

  var isVisible: Bool { panel.isVisible }

  init(appState: AppState, dictationCoordinator: DictationCoordinator) {
    state = ChatState(appState: appState, dictationCoordinator: dictationCoordinator)
    panel = ChatPanel(
      contentRect: CGRect(origin: .zero, size: Self.windowSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    super.init()

    panel.contentView = NSHostingView(
      rootView: ChatView(state: state) { [weak panel] in
        panel?.orderOut(nil)
      }
    )
    panel.delegate = self
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.isFloatingPanel = true
    panel.isReleasedWhenClosed = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.hidesOnDeactivate = false
    panel.level = .screenSaver
    panel.animationBehavior = .utilityWindow
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
  }

  func toggle(attachedTo mascotFrame: CGRect, on screen: NSScreen?) {
    if panel.isVisible {
      hide()
    } else {
      show(attachedTo: mascotFrame, on: screen)
    }
  }

  func show(attachedTo mascotFrame: CGRect, on screen: NSScreen?) {
    move(attachedTo: mascotFrame, on: screen)
    state.refreshAvailability()
    panel.makeKeyAndOrderFront(nil)
  }

  func move(attachedTo mascotFrame: CGRect, on screen: NSScreen?) {
    guard let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
    let origin = ChatPositionCalculator.origin(
      attachedTo: mascotFrame,
      bubbleSize: Self.windowSize,
      in: visibleFrame
    )
    panel.setFrameOrigin(origin)
  }

  func hide() {
    state.stopDictation()
    panel.orderOut(nil)
  }

  func windowDidResignKey(_ notification: Notification) {
    hide()
  }
}
