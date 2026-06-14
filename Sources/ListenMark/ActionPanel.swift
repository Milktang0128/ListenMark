import AppKit
import SwiftUI
import Combine

/// Floating, non-activating popup near the cursor. The toolbar row is a fixed
/// slim height; the panel only grows downward (anchored at its top edge) to a
/// capped result card — and 朗读 stays compact.
final class ActionPanel: NSPanel {
    let model = PanelModel()

    private var cancellable: AnyCancellable?
    private let panelWidth: CGFloat = 380
    private let barHeight: CGFloat = 40
    private var currentWidth: CGFloat = 380

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 40),
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
        host.frame = NSRect(x: 0, y: 0, width: panelWidth, height: barHeight)
        contentView = host

        cancellable = model.$phase
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in self?.resize(for: phase) }
    }

    override var canBecomeKey: Bool { true }

    private func height(for phase: PanelModel.Phase) -> CGFloat {
        switch phase {
        case .idle: return barHeight
        case .loading: return barHeight + 48
        case .error: return barHeight + 56
        case .result(_, _, _, _, _, let compact):
            return compact ? barHeight + 66 : barHeight + 158
        }
    }

    private func resize(for phase: PanelModel.Phase) {
        let h = height(for: phase)
        var f = frame
        let top = f.maxY
        f.size.height = h
        f.size.width = currentWidth
        f.origin.y = top - h
        setFrame(f, display: true, animate: true)
    }

    /// Toolbar width measured from the enabled skills' labels, so nothing gets
    /// squeezed/truncated regardless of how many skills are on.
    private func computeWidth() -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12)
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        var w: CGFloat = 16 + 14   // toolbar h-padding (8+8) + grip
        for def in ActionStore.shared.enabled {
            let labelW = (def.name as NSString).size(withAttributes: [.font: font]).width
            let iconW = NSImage(systemSymbolName: def.icon, accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg)?.size.width ?? 18
            // ActionItem = hpad(18) + icon + spacing(5) + label ; + hstack gap(2)
            w += 18 + ceil(iconW) + 5 + ceil(labelW) + 2
        }
        w += 5 + 26 + 22 + 8   // divider + ··· menu + × close + gaps
        return max(panelWidth, ceil(w) + 4)
    }

    func showNearMouse() {
        model.phase = .idle
        model.active = nil
        currentWidth = computeWidth()
        model.contentWidth = currentWidth
        let size = NSSize(width: currentWidth, height: barHeight)
        setContentSize(size)

        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: mouse.x + 10, y: mouse.y - 12 - size.height)
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            if origin.x + size.width > vf.maxX { origin.x = vf.maxX - size.width - 8 }
            if origin.x < vf.minX { origin.x = vf.minX + 8 }
            // leave headroom for the tallest result card below
            if origin.y - 158 < vf.minY { origin.y = mouse.y + 18 }
        }
        setFrameOrigin(origin)
        orderFrontRegardless()
    }
}
