import SwiftUI

enum ActionPanelLayout {
    static let visibleActionLimit = 5
}

/// Drives the floating panel. The toolbar is data-driven from ActionStore;
/// the row is a fixed slim height and never grows — results appear in a capped
/// card below it (and 朗读 stays compact).
final class PanelModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading(String)                                                              // action name
        case result(action: String, icon: String, text: String, replay: Bool,
                    archived: Bool, compact: Bool, contextUsed: Bool)
        case error(String)
    }

    @Published var phase: Phase = .idle
    @Published var active: String?      // active action id (drives the accent)
    @Published var contentWidth: CGFloat = 320   // measured to fit the enabled skills

    var onPick: ((ActionDef) -> Void)?
    var onReplay: (() -> Void)?
    var onStop: (() -> Void)?
    var onArchive: (() -> Void)?
    var onArchiveOriginal: (() -> Void)?
    var onCopyOriginal: (() -> Bool)?
    var onCopyResult: ((String) -> Bool)?
    var onAutoSpeakChanged: ((Bool) -> Void)?
    var onClose: (() -> Void)?
    var onOpenArchive: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenActions: (() -> Void)?
    var onOpenReview: (() -> Void)?
}

struct ActionPanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject private var store = ActionStore.shared
    @State private var showOriginalCopyBubble = false
    @State private var showResultCopyBubble = false
    @State private var originalCopyArchived = false
    @State private var resultCopyArchived = false
    @State private var originalCopyToken = UUID()
    @State private var resultCopyToken = UUID()
    @AppStorage("autoSpeakAI") private var autoSpeakAI = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            if model.phase != .idle {
                Divider().opacity(0.5)
                resultArea
            }
            Spacer(minLength: 0)
        }
        .frame(width: model.contentWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .animation(.easeOut(duration: 0.16), value: model.phase)
    }

    // MARK: Slim toolbar

    private var toolbar: some View {
        HStack(spacing: 2) {
            GripView()
            ForEach(visibleActions) { def in
                ActionItem(def: def, active: model.active == def.id) { model.onPick?(def) }
            }
            Divider().frame(height: 18).padding(.horizontal, 2)
            Button {
                if model.onCopyOriginal?() == true {
                    presentOriginalCopyBubble()
                }
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help(AppFlavor.text("复制原文", "Copy Original"))
            .popover(isPresented: $showOriginalCopyBubble, arrowEdge: .bottom) {
                CopyArchiveBubble(archived: originalCopyArchived) {
                    model.onArchiveOriginal?()
                    originalCopyArchived = true
                    dismissOriginalCopyBubble(after: 0.65)
                }
            }

            Menu {
                if !overflowActions.isEmpty {
                    Section(AppFlavor.text("更多技能", "More Actions")) {
                        ForEach(overflowActions) { def in
                            Button {
                                model.onPick?(def)
                            } label: {
                                Label(def.name, systemImage: def.icon)
                            }
                        }
                    }
                    Divider()
                }
                Button(AppFlavor.text("今日回响…", "Review…")) { model.onOpenReview?() }
                Button(AppFlavor.text("编辑技能…", "Edit Actions…")) { model.onOpenActions?() }
                Button(AppFlavor.text("打开档案…", "Open Archive…")) { model.onOpenArchive?() }
                Button(AppFlavor.text("设置…", "Settings…")) { model.onOpenSettings?() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 34)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button { model.onClose?() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 22, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(AppFlavor.text("关闭", "Close"))
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
    }

    private var visibleActions: [ActionDef] {
        Array(store.enabled.prefix(ActionPanelLayout.visibleActionLimit))
    }

    private var overflowActions: [ActionDef] {
        Array(store.enabled.dropFirst(ActionPanelLayout.visibleActionLimit))
    }

    // MARK: Result card

    @ViewBuilder private var resultArea: some View {
        switch model.phase {
        case .idle:
            EmptyView()

        case .loading(let label):
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text(AppFlavor.text("正在\(label)…", "\(label) in progress...")).font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                autoSpeakToggle
            }
            .padding(.horizontal, 14).padding(.vertical, 13)

        case .result(let action, let icon, let text, let replay, let archived, let compact, let contextUsed):
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: archived ? "checkmark.seal.fill" : icon)
                        .font(.system(size: 11))
                        .foregroundStyle(archived ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    Text(action)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if contextUsed {
                        Label(AppFlavor.text("已附带上下文", "Context included"), systemImage: "doc.text.magnifyingglass")
                            .font(.system(size: 10, weight: .medium))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    Spacer()
                    if archived {
                        Text(AppFlavor.text("已留档", "Saved")).font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }

                if !compact {
                    ScrollView {
                        Text(text)
                            .font(.system(size: 13))
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 64)
                    .padding(9)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))

                    autoSpeakToggle
                }

                controls(text: text, replay: replay, archived: archived)
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 12)

        case .error(let msg):
            HStack(spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13)).foregroundStyle(.orange)
                Text(msg).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
        }
    }

    private func controls(text: String, replay: Bool, archived: Bool) -> some View {
        HStack(spacing: 7) {
            if replay {
                Button { model.onReplay?() } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .help(AppFlavor.text("重听", "Replay"))
            }
            Button { model.onStop?() } label: { Image(systemName: "stop.fill") }
                .buttonStyle(.bordered)
                .help(AppFlavor.text("停止", "Stop"))
            Button {
                if model.onCopyResult?(text) == true {
                    presentResultCopyBubble()
                }
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .help(AppFlavor.text("复制结果", "Copy Result"))
            .popover(isPresented: $showResultCopyBubble, arrowEdge: .bottom) {
                CopyArchiveBubble(archived: archived || resultCopyArchived,
                                  canArchive: replay && !archived && !resultCopyArchived) {
                    model.onArchive?()
                    resultCopyArchived = true
                    dismissResultCopyBubble(after: 0.65)
                }
            }
            if replay && !archived {
                Button { model.onArchive?() } label: { Label(AppFlavor.text("留档", "Save"), systemImage: "tray.and.arrow.down.fill") }
                    .buttonStyle(.bordered).tint(.accentColor)
            }
            Spacer()
            Button { model.onClose?() } label: { Image(systemName: "xmark") }
                .buttonStyle(.bordered).help(AppFlavor.text("关闭", "Close"))
        }
        .controlSize(.small)
        .buttonBorderShape(.capsule)
    }

    private var autoSpeakToggle: some View {
        Toggle(isOn: Binding(get: { autoSpeakAI }, set: { enabled in
            autoSpeakAI = enabled
            model.onAutoSpeakChanged?(enabled)
        })) {
            Text(AppFlavor.text("自动朗读", "Auto Read"))
                .font(.system(size: 11))
        }
        .toggleStyle(.checkbox)
        .help(AppFlavor.text("生成完成后自动朗读 AI 结果", "Read AI results automatically when generation completes"))
        .fixedSize()
    }

    private func presentOriginalCopyBubble() {
        originalCopyArchived = false
        showOriginalCopyBubble = true
        dismissOriginalCopyBubble(after: 3)
    }

    private func presentResultCopyBubble() {
        resultCopyArchived = false
        showResultCopyBubble = true
        dismissResultCopyBubble(after: 3)
    }

    private func dismissOriginalCopyBubble(after delay: TimeInterval) {
        let token = UUID()
        originalCopyToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if originalCopyToken == token {
                showOriginalCopyBubble = false
            }
        }
    }

    private func dismissResultCopyBubble(after delay: TimeInterval) {
        let token = UUID()
        resultCopyToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if resultCopyToken == token {
                showResultCopyBubble = false
            }
        }
    }
}

// MARK: - Pieces

private struct CopyArchiveBubble: View {
    let archived: Bool
    var canArchive = true
    let onArchive: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Label(AppFlavor.text("已复制", "Copied"), systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if archived {
                Text(AppFlavor.text("已留档", "Saved"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if canArchive {
                Divider().frame(height: 18)
                Button {
                    onArchive()
                } label: {
                    Label(AppFlavor.text("留档", "Save"), systemImage: "tray.and.arrow.down.fill")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .fixedSize()
    }
}

private struct ActionItem: View {
    let def: ActionDef
    let active: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: def.icon)
                    .font(.system(size: 13, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 14)
                Text(def.name).font(.system(size: 12)).lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .foregroundStyle(active ? Color.accentColor : Color.primary)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var fill: Color {
        if active { return Color.accentColor.opacity(0.14) }
        if hover { return Color.primary.opacity(0.08) }
        return .clear
    }
}

private struct GripView: View {
    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 3) {
                    Circle().frame(width: 2.5, height: 2.5)
                    Circle().frame(width: 2.5, height: 2.5)
                }
            }
        }
        .foregroundStyle(.tertiary)
        .frame(width: 14, height: 40)
    }
}
