import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A button that, when clicked, records the next modifier+key combo.
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var display: String
    var onRecord: (UInt16, NSEvent.ModifierFlags, String) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let b = RecorderButton()
        b.onRecord = onRecord
        b.title = display
        return b
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        if !nsView.recording { nsView.title = display }
    }
}

final class RecorderButton: NSButton {
    var onRecord: ((UInt16, NSEvent.ModifierFlags, String) -> Void)?
    var recording = false
    private var monitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(begin)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func begin() {
        recording = true
        title = "按下新快捷键…"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.capture(e)
            return nil
        }
    }

    private func capture(_ e: NSEvent) {
        let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !mods.isEmpty else { NSSound.beep(); return } // require a modifier
        let chars = (e.charactersIgnoringModifiers ?? "").uppercased()
        let disp = Self.symbols(mods) + chars
        title = disp
        stop()
        onRecord?(e.keyCode, mods, disp)
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    static func symbols(_ m: NSEvent.ModifierFlags) -> String {
        var s = ""
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option) { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        return s
    }
}

/// NSEvent modifier flags → Carbon modifier mask for RegisterEventHotKey.
func carbonModifiers(_ f: NSEvent.ModifierFlags) -> Int {
    var m = 0
    if f.contains(.command) { m |= cmdKey }
    if f.contains(.option) { m |= optionKey }
    if f.contains(.control) { m |= controlKey }
    if f.contains(.shift) { m |= shiftKey }
    return m
}
