import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox

/// Floating, non-activating popup near the cursor. The toolbar row is a fixed
/// slim height; the panel only grows downward (anchored at its top edge) to a
/// capped result card — and 朗读 stays compact.
final class ActionPanel: NSPanel {
    let model = PanelModel()

    private var cancellable: AnyCancellable?
    private var conversationCancellable: AnyCancellable?
    private var keyMonitor: Any?
    private let minPanelWidth: CGFloat = 320
    private let barHeight: CGFloat = 40
    private var currentWidth: CGFloat = 320
    private var keyboardFocusAllowed = false

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 40),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let host = NSHostingView(rootView: ActionPanelView(model: model))
        host.autoresizingMask = [.width, .height]
        host.frame = NSRect(x: 0, y: 0, width: minPanelWidth, height: barHeight)
        contentView = host

        cancellable = model.$phase
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in self?.resize(for: phase) }

        // Conversation history / follow-up affordance grow & shrink without
        // changing `phase`, so resize on those edits too (the live answer already
        // comes through `$phase`). These are too many publishers for a
        // CombineLatest (4-element cap), so merge each into a single Void signal.
        let resizeTriggers: [AnyPublisher<Void, Never>] = [
            model.$priorTurns.map { $0.count }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            model.$isConversing.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            model.$canFollowUp.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            model.$followUpMode.map { _ in () }.eraseToAnyPublisher(),
            model.$isAwaitingReply.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
        ]
        conversationCancellable = Publishers.MergeMany(resizeTriggers)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.resize(for: self.model.phase)
            }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.isVisible, event.window === self || self.isKeyWindow else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    override var canBecomeKey: Bool { keyboardFocusAllowed }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            requestKeyboardFocus()
        default:
            break
        }
        super.sendEvent(event)
    }

    func requestKeyboardFocus() {
        keyboardFocusAllowed = true
        makeKey()
    }

    func releaseKeyboardFocus() {
        keyboardFocusAllowed = false
    }

    private func height(for phase: PanelModel.Phase) -> CGFloat {
        switch phase {
        case .idle: return barHeight
        case .input: return barHeight + 164
        case .dialogueInput: return barHeight + 150
        case .captureNotice: return barHeight + 58
        case .loading: return barHeight + 48
        case .error: return barHeight + 56
        case .compare(_, _, let results, _, _):
            return ActionCompareLayout.panelHeight(for: results, panelWidth: currentWidth, barHeight: barHeight)
        case .result(_, _, let text, _, _, let compact, _):
            if model.isConversing {
                return ActionResultLayout.conversationPanelHeight(priorTurns: model.priorTurns,
                                                                  currentText: text,
                                                                  panelWidth: currentWidth,
                                                                  barHeight: barHeight,
                                                                  followUpVisible: model.canFollowUp && model.followUpMode == .expanded,
                                                                  awaitingReply: model.isAwaitingReply)
            }
            if compact { return barHeight + 66 }
            let base = ActionResultLayout.panelHeight(for: text, panelWidth: currentWidth, barHeight: barHeight)
            let followUpVisible = model.canFollowUp && model.followUpMode == .expanded
            return followUpVisible ? base + ActionResultLayout.followUpBarHeight + 8 : base
        }
    }

    /// Re-run the size/position pass for the current phase. Used by `restorePanel`
    /// so a brought-back session re-clamps to the (possibly changed) screen even
    /// though its phase value didn't change (`$phase.removeDuplicates` would
    /// otherwise swallow it).
    func reapplyLayout() {
        resize(for: model.phase)
    }

    private func resize(for phase: PanelModel.Phase) {
        let w = width(for: phase)
        let h = height(for: phase)
        var f = frame
        let top = f.maxY
        f.size.height = h
        f.size.width = w
        f.origin.y = top - h
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(f) }) ?? NSScreen.main {
            let vf = screen.visibleFrame
            if f.maxX > vf.maxX { f.origin.x = vf.maxX - f.width - 8 }
            if f.minX < vf.minX { f.origin.x = vf.minX + 8 }
            if f.minY < vf.minY { f.origin.y = vf.minY + 8 }
            if f.maxY > vf.maxY { f.origin.y = vf.maxY - f.height - 8 }
        }
        currentWidth = w
        model.contentWidth = w
        setFrame(f, display: true, animate: true)
    }

    private func width(for phase: PanelModel.Phase) -> CGFloat {
        switch phase {
        case .compare:
            return max(currentWidth, 640)
        default:
            return currentWidth
        }
    }

    /// Toolbar width measured from the visible skills' labels. Extra enabled
    /// skills stay in the overflow menu, so the panel does not keep growing.
    private func computeWidth() -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12)
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        var w: CGFloat = 16 + 14   // toolbar h-padding (8+8) + grip
        var childCount = 1
        for def in ActionStore.shared.enabled.prefix(ActionPanelLayout.visibleActionLimit) {
            let labelW = (def.name as NSString).size(withAttributes: [.font: font]).width
            let measuredIconW = NSImage(systemSymbolName: def.icon, accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg)?.size.width ?? 14
            let iconW = min(ceil(measuredIconW), 14)
            // ActionItem = hpad(16) + icon + spacing(5) + label.
            w += 16 + iconW + 5 + ceil(labelW)
            childCount += 1
        }
        w += 5 + 26 + 26 + 26 + 22 + 22   // divider + search/link + copy + ··· menu + pin + × close
        childCount += 6
        w += CGFloat(max(childCount - 1, 0)) * 2
        return max(minPanelWidth, ceil(w))
    }

    func showNearMouse(minWidth: CGFloat = 320, allowsKeyboardFocus: Bool = false) {
        alphaValue = 1
        model.phase = .idle
        model.active = nil
        keyboardFocusAllowed = allowsKeyboardFocus
        currentWidth = max(computeWidth(), minWidth)
        model.contentWidth = currentWidth
        model.pinned = false
        let size = NSSize(width: currentWidth, height: barHeight)
        setContentSize(size)

        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: mouse.x + 10, y: mouse.y - 12 - size.height)
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            if origin.x + size.width > vf.maxX { origin.x = vf.maxX - size.width - 8 }
            if origin.x < vf.minX { origin.x = vf.minX + 8 }
            // Leave headroom for the tallest result card below — including a
            // full multi-turn conversation, which is the tallest state.
            let maxExpansion = ActionResultLayout.maxConversationPanelHeight(barHeight: barHeight) - barHeight
            if origin.y - maxExpansion < vf.minY { origin.y = mouse.y + 18 }
        }
        setFrameOrigin(origin)
        if allowsKeyboardFocus {
            makeKeyAndOrderFront(nil)
        }
        orderFrontRegardless()
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let keyCode = Int(event.keyCode)

        if keyCode == kVK_Escape {
            // In the 对话 instruction box, Esc cancels back to the toolbar.
            if case .dialogueInput = model.phase {
                model.onDialogueCancel?()
                return true
            }
            // Sticky 对话 has no single-turn result to fall back to, so its first
            // Esc hides-and-preserves the thread (restorable) instead of exiting.
            if model.isConversing, model.isStickyConversation {
                model.onHidePreserve?()
                return true
            }
            // An empty, expanded follow-up box on a non-sticky thread collapses
            // back to the 「追问」button rather than exiting the conversation.
            if model.isConversing, !model.isStickyConversation,
               model.followUpMode == .expanded,
               model.followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                model.followUpMode = .collapsed
                releaseKeyboardFocus()
                makeFirstResponder(nil)
                return true
            }
            // Two-stage exit while conversing: first Esc leaves the conversation
            // (back to a single-turn result), a second Esc closes the panel.
            if model.isConversing {
                model.onExitConversation?()
                return true
            }
            model.onClose?()
            return true
        }
        if command, keyCode == kVK_ANSI_P {
            model.onTogglePin?()
            return true
        }
        if command, keyCode == kVK_ANSI_Comma {
            model.onOpenSettings?()
            return true
        }

        if case .input = model.phase {
            return false
        }
        // 对话 instruction box: defer all remaining keys to the text view.
        if case .dialogueInput = model.phase {
            return false
        }

        // When the follow-up field is focused, let native editing keys reach it
        // (selection copy/paste/cut/select-all) instead of the panel shortcuts.
        if isFollowUpFieldFocused, command,
           keyCode == kVK_ANSI_C || keyCode == kVK_ANSI_A ||
           keyCode == kVK_ANSI_V || keyCode == kVK_ANSI_X {
            return false
        }

        if command, keyCode == kVK_ANSI_R {
            model.onRetry?()
            return true
        }
        if command, keyCode == kVK_ANSI_S {
            model.onArchive?()
            return true
        }
        if command, keyCode == kVK_ANSI_C {
            return model.onCopyKeyboard?() ?? false
        }
        if command, keyCode == kVK_ANSI_Equal || keyCode == kVK_ANSI_KeypadPlus {
            Settings.panelTextSizeDelta += 1
            return true
        }
        if command, keyCode == kVK_ANSI_Minus || keyCode == kVK_ANSI_KeypadMinus {
            Settings.panelTextSizeDelta -= 1
            return true
        }
        // ⌘1–5 switch toolbar skills — disabled mid-conversation so the user
        // doesn't accidentally start a new action over the thread.
        if command, !model.isConversing, let index = actionIndex(for: keyCode) {
            let actions = ActionStore.shared.enabled
            guard actions.indices.contains(index) else { return false }
            model.onPick?(actions[index])
            return true
        }
        return false
    }

    /// Whether the first responder is an editable NSTextView (the follow-up /
    /// dialogue input field), so panel keyboard shortcuts should defer to it.
    private var isFollowUpFieldFocused: Bool {
        (firstResponder as? NSTextView)?.isEditable == true
    }

    private func actionIndex(for keyCode: Int) -> Int? {
        switch keyCode {
        case kVK_ANSI_1: return 0
        case kVK_ANSI_2: return 1
        case kVK_ANSI_3: return 2
        case kVK_ANSI_4: return 3
        case kVK_ANSI_5: return 4
        default: return nil
        }
    }
}
