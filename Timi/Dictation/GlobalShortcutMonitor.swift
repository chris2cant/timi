import AppKit
import Carbon
import Combine

enum ShortcutAction: Equatable, Sendable {
  case beginHold
  case endHold
  case toggle
}

struct HybridShortcutState: Sendable {
  private(set) var keyIsDown = false
  private(set) var holdStarted = false

  mutating func keyDown(isRepeat: Bool) -> Bool {
    guard !isRepeat, !keyIsDown else { return false }
    keyIsDown = true
    holdStarted = false
    return true
  }

  mutating func holdThresholdReached() -> ShortcutAction? {
    guard keyIsDown, !holdStarted else { return nil }
    holdStarted = true
    return .beginHold
  }

  mutating func keyUp() -> ShortcutAction? {
    guard keyIsDown else { return nil }
    keyIsDown = false
    if holdStarted {
      holdStarted = false
      return .endHold
    }
    return .toggle
  }
}

@MainActor
final class GlobalShortcutMonitor: ObservableObject {
  enum Status: Equatable {
    case inactive
    case active
    case permissionRequired
    case conflict

    var title: String {
      switch self {
      case .inactive: "Initialisation du raccourci…"
      case .active: "Raccourci global actif"
      case .permissionRequired: "Autorisation de surveillance requise"
      case .conflict: "Raccourci réservé par macOS"
      }
    }
  }

  var onAction: ((ShortcutAction) -> Void)?
  var shortcut: DictationShortcut = .controlSpace {
    didSet {
      guard shortcut != oldValue, isStarted else { return }
      restart()
    }
  }
  @Published private(set) var status: Status = .inactive

  var permissionMissing: Bool { status == .permissionRequired }

  nonisolated(unsafe) private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  nonisolated(unsafe) private var hotKey: EventHotKeyRef?
  nonisolated(unsafe) private var hotKeyHandler: EventHandlerRef?
  private var state = HybridShortcutState()
  private var holdTask: Task<Void, Never>?
  private var permissionRetryTask: Task<Void, Never>?
  private var canSuppressEvents = false
  private var isStarted = false

  deinit {
    holdTask?.cancel()
    permissionRetryTask?.cancel()
    if let hotKey { UnregisterEventHotKey(hotKey) }
    if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
  }

  func start() {
    isStarted = true
    if hotKey == nil, installSystemHotKey() {
      status = .active
      permissionRetryTask?.cancel()
      permissionRetryTask = nil
      removeEventTap()
      return
    }

    if eventTap != nil {
      if !canSuppressEvents, AXIsProcessTrusted() {
        removeEventTap()
        installEventTap(options: .defaultTap)
      }
      status = canSuppressEvents ? .active : .permissionRequired
      return
    }
    guard CGPreflightListenEventAccess() else {
      status = .permissionRequired
      _ = CGRequestListenEventAccess()
      beginPermissionRetry()
      return
    }

    let options: CGEventTapOptions = AXIsProcessTrusted() ? .defaultTap : .listenOnly
    installEventTap(options: options)
    if eventTap == nil, options == .defaultTap {
      installEventTap(options: .listenOnly)
    }
    if eventTap == nil {
      status = .conflict
    } else {
      status = canSuppressEvents ? .active : .permissionRequired
    }
    beginPermissionRetry()
  }

  func requestPermission() {
    _ = CGRequestListenEventAccess()
    TextInsertionService.requestAccessibilityIfNeeded()
    beginPermissionRetry()
  }

  private func restart() {
    holdTask?.cancel()
    holdTask = nil
    state = HybridShortcutState()
    removeSystemHotKey()
    removeEventTap()
    status = .inactive
    start()
  }

  private func installSystemHotKey() -> Bool {
    if hotKeyHandler == nil {
      var eventTypes = [
        EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
        EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
      ]
      let pointer = Unmanaged.passUnretained(self).toOpaque()
      let handlerStatus = InstallEventHandler(
        GetApplicationEventTarget(),
        Self.systemHotKeyHandler,
        eventTypes.count,
        &eventTypes,
        pointer,
        &hotKeyHandler
      )
      guard handlerStatus == noErr else { return false }
    }

    var reference: EventHotKeyRef?
    let identifier = EventHotKeyID(signature: 0x54494D49, id: 1) // "TIMI"
    let registrationStatus = RegisterEventHotKey(
      UInt32(kVK_Space),
      shortcut.carbonModifiers,
      identifier,
      GetApplicationEventTarget(),
      0,
      &reference
    )
    guard registrationStatus == noErr, let reference else { return false }
    hotKey = reference
    return true
  }

  private func removeSystemHotKey() {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    hotKey = nil
  }

  private nonisolated static let systemHotKeyHandler: EventHandlerUPP = {
    _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    let kind = GetEventKind(event)
    let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
      monitor.handleSystemHotKey(kind: kind)
    }
    return noErr
  }

  private func handleSystemHotKey(kind: UInt32) {
    if kind == UInt32(kEventHotKeyPressed) {
      beginPress(isRepeat: false)
    } else if kind == UInt32(kEventHotKeyReleased) {
      endPress()
    }
  }

  private func beginPress(isRepeat: Bool) {
    guard state.keyDown(isRepeat: isRepeat) else { return }
    holdTask?.cancel()
    holdTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(280))
      guard !Task.isCancelled, let self,
            let action = self.state.holdThresholdReached() else { return }
      self.onAction?(action)
    }
  }

  private func endPress() {
    guard state.keyIsDown else { return }
    holdTask?.cancel()
    holdTask = nil
    if let action = state.keyUp() { onAction?(action) }
  }

  private func installEventTap(options: CGEventTapOptions) {
    let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
    let pointer = Unmanaged.passUnretained(self).toOpaque()
    guard let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: options,
      eventsOfInterest: CGEventMask(mask),
      callback: { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(refcon).takeUnretainedValue()
        return monitor.handle(type: type, event: event)
      },
      userInfo: pointer
    ) else {
      return
    }

    eventTap = tap
    canSuppressEvents = options == .defaultTap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
  }

  private func beginPermissionRetry() {
    guard permissionRetryTask == nil else { return }
    permissionRetryTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, let self else { return }
        self.start()
        if self.eventTap != nil, self.canSuppressEvents {
          self.permissionRetryTask = nil
          return
        }
      }
    }
  }

  private func removeEventTap() {
    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
    }
    runLoopSource = nil
    eventTap = nil
    canSuppressEvents = false
  }

  private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
      return Unmanaged.passUnretained(event)
    }

    let isSpace = event.getIntegerValueField(.keyboardEventKeycode) == 49
    let modifierMask: CGEventFlags = [
      .maskControl, .maskShift, .maskAlternate, .maskCommand, .maskSecondaryFn
    ]
    guard isSpace else { return Unmanaged.passUnretained(event) }

    if type == .keyUp, state.keyIsDown {
      endPress()
      return canSuppressEvents ? nil : Unmanaged.passUnretained(event)
    }

    let matchesModifiers = event.flags.intersection(modifierMask) == shortcut.eventFlags
    guard matchesModifiers else { return Unmanaged.passUnretained(event) }

    if type == .keyDown {
      let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
      beginPress(isRepeat: isRepeat)
    }
    return canSuppressEvents ? nil : Unmanaged.passUnretained(event)
  }
}

private extension DictationShortcut {
  var carbonModifiers: UInt32 {
    switch self {
    case .controlSpace: UInt32(controlKey)
    case .controlOptionSpace: UInt32(controlKey | optionKey)
    case .commandShiftSpace: UInt32(cmdKey | shiftKey)
    }
  }
}
