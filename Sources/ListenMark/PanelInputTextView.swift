import AppKit
import SwiftUI

struct PanelInputTextView: NSViewRepresentable {
    @Binding var text: String
    var focusRequest: Int
    var onSubmit: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.string = text
        textView.delegate = context.coordinator

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            let range = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(range.location, (text as NSString).length), length: 0))
        }

        guard focusRequest > 0, focusRequest != context.coordinator.lastFocusRequest else { return }
        context.coordinator.lastFocusRequest = focusRequest
        context.coordinator.requestFocus()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PanelInputTextView
        weak var textView: NSTextView?
        var lastFocusRequest = 0

        init(parent: PanelInputTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        /// Return submits (when an onSubmit is wired); Shift+Return inserts a
        /// newline; Esc cancels. With no handlers wired, behaviour is unchanged.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                guard let onSubmit = parent.onSubmit else { return false }
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { return false }
                onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                guard let onCancel = parent.onCancel else { return false }
                onCancel()
                return true
            default:
                return false
            }
        }

        func requestFocus(attemptsRemaining: Int = 8) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                guard let self, let textView = self.textView else { return }
                guard let window = textView.window else {
                    if attemptsRemaining > 0 {
                        self.requestFocus(attemptsRemaining: attemptsRemaining - 1)
                    }
                    return
                }
                if let panel = window as? ActionPanel {
                    panel.requestKeyboardFocus()
                } else {
                    window.makeKeyAndOrderFront(nil)
                }
                window.makeFirstResponder(textView)
            }
        }
    }
}
