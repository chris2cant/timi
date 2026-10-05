import AppKit
import ApplicationServices
import Carbon
import os

private let log = Logger(subsystem: "io.github.chris2cant.Timi", category: "insertion")

struct FocusedTextContext: Sendable {
  let surroundingText: String
  let acceptsText: Bool
  let isSecure: Bool
}

@MainActor
final class TextInsertionService {
  func focusedContext() -> FocusedTextContext {
    guard !IsSecureEventInputEnabled(), let element = focusedElement() else {
      return FocusedTextContext(surroundingText: "", acceptsText: false, isSecure: true)
    }

    return focusedContext(for: element)
  }

  private func focusedContext(for element: AXUIElement) -> FocusedTextContext {
    let role = stringAttribute(kAXRoleAttribute, from: element) ?? ""
    let subrole = stringAttribute(kAXSubroleAttribute, from: element) ?? ""
    let secure = subrole == kAXSecureTextFieldSubrole as String
    let textRoles = [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String]
    let acceptsText = !secure && (textRoles.contains(role) || isValueSettable(on: element))
    return FocusedTextContext(
      surroundingText: acceptsText ? cursorContext(from: element) : "",
      acceptsText: acceptsText,
      isSecure: secure
    )
  }

  func insertOrCopy(_ text: String) async -> DictationInsertionResult {
    log.notice("insert: secureInput=\(IsSecureEventInputEnabled()) trusted=\(AXIsProcessTrusted())")
    guard !IsSecureEventInputEnabled(), AXIsProcessTrusted() else {
      copy(text)
      return .copied
    }
    // Chrome/Electron n'exposent souvent pas de champ texte via l'accessibilité :
    // on ne bloque donc le collage que pour un champ explicitement sécurisé.
    let target = focusedElement()
    if let target, focusedContext(for: target).isSecure {
      copy(text)
      return .copied
    }

    let pasteboard = NSPasteboard.general
    let backup = PasteboardBackup(pasteboard: pasteboard)
    let valueBeforePaste = target.flatMap { stringAttribute(kAXValueAttribute, from: $0) }
    copy(text)

    log.notice("insert: target=\(target != nil) posting paste")
    await waitForModifierRelease()
    guard postPasteShortcut() else {
      return .copied
    }

    try? await Task.sleep(for: .milliseconds(350))
    let currentTarget = focusedElement()
    let valueAfterPaste = currentTarget.flatMap {
      stringAttribute(kAXValueAttribute, from: $0)
    }
    let targetIsUnchanged = target.flatMap { target in
      currentTarget.map { CFEqual(target, $0) }
    } ?? false
    let pasteWasConfirmed = targetIsUnchanged
      && valueAfterPaste != nil
      && valueAfterPaste != valueBeforePaste
    if pasteWasConfirmed {
      backup.restore(to: pasteboard)
      return .pasted
    }
    return .copied
  }

  static func requestAccessibilityIfNeeded() {
    guard !AXIsProcessTrusted() else { return }
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
  }

  private func focusedElement() -> AXUIElement? {
    let system = AXUIElementCreateSystemWide()
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
      system,
      kAXFocusedUIElementAttribute as CFString,
      &value
    ) == .success else { return nil }
    return (value as! AXUIElement)
  }

  private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
      return nil
    }
    return value as? String
  }

  private func isValueSettable(on element: AXUIElement) -> Bool {
    var settable = DarwinBoolean(false)
    return AXUIElementIsAttributeSettable(
      element,
      kAXValueAttribute as CFString,
      &settable
    ) == .success && settable.boolValue
  }

  private func cursorContext(from element: AXUIElement) -> String {
    guard let value = stringAttribute(kAXValueAttribute, from: element), !value.isEmpty else {
      return ""
    }
    var rangeValue: CFTypeRef?
    var location = value.utf16.count
    if AXUIElementCopyAttributeValue(
      element,
      kAXSelectedTextRangeAttribute as CFString,
      &rangeValue
    ) == .success,
       let rangeValue,
       CFGetTypeID(rangeValue) == AXValueGetTypeID() {
      var range = CFRange()
      if AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) {
        location = range.location
      }
    }

    let units = Array(value.utf16)
    let start = max(0, min(location - 250, units.count))
    let end = max(start, min(location + 250, units.count))
    return String(decoding: units[start..<end], as: UTF16.self)
  }

  private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  /// Control (raccourci Control+Espace) encore enfoncé transformerait Cmd+V en Ctrl+Cmd+V.
  private func waitForModifierRelease() async {
    let blocking: CGEventFlags = [.maskControl, .maskAlternate, .maskShift]
    for _ in 0..<20 {
      let flags = CGEventSource.flagsState(.combinedSessionState)
      if flags.isDisjoint(with: blocking) { return }
      try? await Task.sleep(for: .milliseconds(50))
    }
  }

  private func postPasteShortcut() -> Bool {
    guard let source = CGEventSource(stateID: .combinedSessionState),
          let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
      return false
    }
    down.flags = .maskCommand
    up.flags = .maskCommand
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    return true
  }
}

private struct PasteboardBackup {
  private let items: [[NSPasteboard.PasteboardType: Data]]

  init(pasteboard: NSPasteboard) {
    items = (pasteboard.pasteboardItems ?? []).map { item in
      Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
        item.data(forType: type).map { (type, $0) }
      })
    }
  }

  func restore(to pasteboard: NSPasteboard) {
    pasteboard.clearContents()
    let restoredItems = items.map { values in
      let item = NSPasteboardItem()
      for (type, data) in values {
        item.setData(data, forType: type)
      }
      return item
    }
    if !restoredItems.isEmpty {
      pasteboard.writeObjects(restoredItems)
    }
  }
}
