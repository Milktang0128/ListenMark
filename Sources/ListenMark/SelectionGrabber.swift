import AppKit
import ApplicationServices

/// Reads the current selection. Tries the Accessibility API first (direct,
/// no clipboard side-effect); falls back to synthesizing ⌘C and reading the
/// pasteboard for apps that don't expose AX selected text. Both paths need
/// Accessibility permission.
enum SelectionGrabber {

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Coax Chromium/Electron apps (Claude, VS Code, 飞书…) into exposing their
    /// accessibility tree so AXSelectedText works for auto-pop.
    static func enableAccessibility(for pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Direct read via the focused UI element's AXSelectedText. Cheap; used for
    /// auto-pop on every mouse-up.
    static func axSelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return nil }
        let element = focused as! AXUIElement
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
              let s = value as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func grabAsync(allowCopyFallback: Bool = true, _ completion: @escaping (String?) -> Void) {
        if let ax = axSelectedText() { completion(ax); return }
        guard allowCopyFallback else { completion(nil); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let text = copyGrab()
            DispatchQueue.main.async { completion(text) }
        }
    }

    private static func copyGrab() -> String? {
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)
        let before = pb.changeCount

        sendCopy()

        var captured: String?
        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline {
            if pb.changeCount != before {
                captured = pb.string(forType: .string)
                break
            }
            usleep(15_000)
        }

        if let previous {
            pb.clearContents()
            pb.setString(previous, forType: .string)
        }
        return captured?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sendCopy() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let cKey: CGKeyCode = 0x08 // ANSI 'C'
        let down = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
