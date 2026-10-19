import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import SottoCore

enum InsertResult: Equatable, Sendable {
    case inserted
    case kept(TakeProblem)
    case cancelled
}

@MainActor
final class TextInserter {
    /// Host of the focused window URL, with a leading "www." removed. Nil when there is no URL. Never a path or query.
    private(set) var lastDomain: String?
    private var clipboardRestoreTask: Task<Void, Never>?
    /// The last successful insertion: the field, the whole text typed, the UTF-16 cursor location just
    /// before typing (nil when the field didn't say) and when. Also stands in for fields that hide their text.
    private(set) var lastInsertion: (element: AXUIElement, text: String, offset: Int?, date: Date)?
    /// The cursor location `textBeforeCursor` last read, for the insertion that follows it.
    private var cursorBefore: (element: AXUIElement, location: Int)?

    func captureFocus() -> FocusSnapshot {
        let secureInput = IsSecureEventInputEnabled()
        guard let element = focusedElement(), let pid = processID(element), pid != 0 else {
            lastDomain = nil
            return FocusSnapshot(pid: 0, bundleID: nil, selectedTextSettable: false,
                                 isSecureField: false, secureInput: secureInput)
        }
        var settable = DarwinBoolean(false)
        let canSet = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString,
                                                  &settable) == .success && settable.boolValue
        let secure = attribute(element, kAXSubroleAttribute) as? String == "AXSecureTextField"
        lastDomain = domain(element)
        return FocusSnapshot(pid: pid, bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
                             selectedTextSettable: canSet, isSecureField: secure, secureInput: secureInput)
    }

    /// The last few characters before the cursor in the focused field: empty at the start of a field,
    /// nil when the app does not say. A field that hides its text falls back to Sotto's own last
    /// insertion there, if it was recent.
    func textBeforeCursor(bundleID: String?) -> String? {
        cursorBefore = nil
        guard let element = focusedElement() else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.25)
        // A terminal's selection is in the scrollback, not at the prompt.
        if !AppIdentity.isTerminal(bundleID ?? ""), let location = selectionLocation(element) {
            cursorBefore = (element, location)
            if let text = axTextBeforeCursor(element, at: location) { return text }
        }
        if (attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue == 0 { return "" }
        guard let recent = lastInsertion, CFEqual(recent.element, element),
              Date().timeIntervalSince(recent.date) < 180 else { return nil }
        return String(recent.text.suffix(32))
    }

    /// The whole text of a field Sotto typed into. Nil for secure fields, values over 100,000 characters,
    /// and fields that are gone or don't expose their text.
    func fieldText(of element: AXUIElement) -> String? {
        AXUIElementSetMessagingTimeout(element, 0.25)
        guard attribute(element, kAXSubroleAttribute) as? String != "AXSecureTextField" else { return nil }
        if let count = (attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue,
           count > 100_000 { return nil }
        guard let text = attribute(element, kAXValueAttribute) as? String,
              (text as NSString).length <= 100_000 else { return nil }
        return text
    }

    func insert(_ text: String, captured: FocusSnapshot,
                isAllowed: () -> Bool = { true }) async -> InsertResult {
        let cursor = cursorBefore
        cursorBefore = nil
        let result = await deliver(text, captured: captured, isAllowed: isAllowed)
        if result == .inserted, let element = focusedElement() {
            let offset = cursor.flatMap { CFEqual($0.element, element) ? $0.location : nil }
            lastInsertion = (element, text, offset, Date())
        }
        return result
    }

    private func deliver(_ text: String, captured: FocusSnapshot,
                         isAllowed: () -> Bool) async -> InsertResult {
        guard isAllowed() else { return .cancelled }
        // Recheck after each suspension: another caller may have borrowed the clipboard meanwhile.
        while let task = clipboardRestoreTask {
            await task.value
            guard isAllowed() else { return .cancelled }
        }
        let element = focusedElement()
        let nowPID = element.flatMap { processID($0) } ?? 0
        let route = InsertPlanner.route(captured: captured, nowPID: nowPID)
        switch route {
        case .refuse(let failure):
            switch failure {
            case .noFocus: return .kept(.noTextField)
            case .secureField, .secureInput: return .kept(.passwordField)
            case .focusChanged: return .kept(.focusMoved)
            }
        case .accessibility:
            guard let element else {
                return .kept(AXIsProcessTrusted() ? .couldNotType : .accessibilityOff)
            }
            if writeSelectedText(text, to: element) { return .inserted }
            guard !captured.secureInput, !captured.isSecureField,
                  !IsSecureEventInputEnabled() else { return .kept(.couldNotType) }
            return paste(text, captured: captured, element: element,
                         restoreNanoseconds: AppIdentity.pasteRestoreNanoseconds(bundleID: captured.bundleID),
                         accessibilityAttempted: true)
        case .unicode:
            guard !captured.secureInput, !IsSecureEventInputEnabled() else {
                return .kept(.passwordField)
            }
            guard CGPreflightPostEventAccess() else { return .kept(.accessibilityOff) }
            guard let source = CGEventSource(stateID: .privateState) else { return .kept(.couldNotType) }
            let units = Array(text.utf16)
            var offset = 0
            while offset < units.count {
                var end = min(offset + 20, units.count)
                if end < units.count, (0xD800...0xDBFF).contains(units[end - 1]) { end -= 1 }
                guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                    return .kept(.couldNotType)
                }
                let chunk = Array(units[offset..<end])
                chunk.withUnsafeBufferPointer { buffer in
                    if let base = buffer.baseAddress {
                        down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                    }
                }
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
                offset = end
            }
            return .inserted
        case .paste(let restoreNanoseconds):
            return paste(text, captured: captured, element: element,
                         restoreNanoseconds: restoreNanoseconds, accessibilityAttempted: false)
        }
    }

    private func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(),
                                           kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value else { return nil }
        return axElement(value)
    }

    private func axElement(_ value: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // Core Foundation AX objects do not reliably support Swift conditional casts.
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func processID(_ element: AXUIElement) -> Int32? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    /// The UTF-16 location where the selection starts, which is where typing goes.
    private func selectionLocation(_ element: AXUIElement) -> Int? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var selection = CFRange()
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cfRange, &selection),
              selection.location >= 0, selection.location != kCFNotFound else { return nil }
        return selection.location
    }

    private func axTextBeforeCursor(_ element: AXUIElement, at location: Int) -> String? {
        if location == 0 { return "" }
        let length = min(location, 32)
        var range = CFRange(location: location - length, length: length)
        if let rangeValue = AXValueCreate(.cfRange, &range) {
            var string: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                          rangeValue, &string) == .success,
               let string = string as? String, !string.isEmpty {
                return string
            }
        }
        guard let whole = attribute(element, kAXValueAttribute) as? String,
              location <= (whole as NSString).length else { return nil }
        return (whole as NSString).substring(with: NSRange(location: range.location, length: range.length))
    }

    private func domain(_ element: AXUIElement) -> String? {
        guard let value = attribute(element, kAXWindowAttribute), let window = axElement(value) else { return nil }
        for name in [kAXURLAttribute, kAXDocumentAttribute] {
            guard let value = attribute(window, name) else { continue }
            let url: URL?
            if let bridged = value as? URL {
                url = bridged
            } else if let string = value as? String {
                url = URL(string: string)
            } else {
                url = nil
            }
            if let host = url?.host, !host.isEmpty {
                return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            }
        }
        return nil
    }

    private func writeSelectedText(_ text: String, to element: AXUIElement) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        AXUIElementSetMessagingTimeout(element, 1.0)
        let previousCount = (attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue
        let previousSelection = attribute(element, kAXSelectedTextAttribute) as? String
        let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        guard result == .success else { return false }
        if let selection = attribute(element, kAXSelectedTextAttribute) as? String, selection == text {
            return true
        }
        if let previousCount, let previousSelection,
           let count = (attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue {
            return count == previousCount - (previousSelection as NSString).length + (text as NSString).length
        }
        return false
    }

    private func paste(_ text: String, captured: FocusSnapshot, element: AXUIElement?,
                       restoreNanoseconds: UInt64, accessibilityAttempted: Bool) -> InsertResult {
        guard !captured.secureInput, !captured.isSecureField, !IsSecureEventInputEnabled() else {
            return .kept(.passwordField)
        }
        guard !AppIdentity.isTerminal(captured.bundleID ?? "") else { return .kept(.couldNotType) }
        guard CGPreflightPostEventAccess() else {
            if captured.selectedTextSettable, let element {
                if !accessibilityAttempted, writeSelectedText(text, to: element) { return .inserted }
                return .kept(AXIsProcessTrusted() ? .couldNotType : .accessibilityOff)
            }
            return .kept(.accessibilityOff)
        }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            return .kept(.couldNotType)
        }
        let previousSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        selectABCKeyboard()
        defer { if let previousSource { TISSelectInputSource(previousSource) } }
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
        }
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            restoreClipboard(saved)
            return .kept(.couldNotType)
        }
        let writtenCount = pasteboard.changeCount
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        clipboardRestoreTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: restoreNanoseconds)
            if NSPasteboard.general.changeCount == writtenCount {
                self.restoreClipboard(saved)
            }
            self.clipboardRestoreTask = nil
        }
        return .inserted
    }

    private func selectABCKeyboard() {
        let filter = [kTISPropertyInputSourceID as String: "com.apple.keylayout.ABC"] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue(),
              CFArrayGetCount(sources) > 0,
              let pointer = CFArrayGetValueAtIndex(sources, 0) else { return }
        let abc = unsafeBitCast(pointer, to: TISInputSource.self)
        TISSelectInputSource(abc)
    }

    private func restoreClipboard(_ saved: [[(NSPasteboard.PasteboardType, Data)]]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let items = saved.map { representations in
            let item = NSPasteboardItem()
            for (type, data) in representations { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
