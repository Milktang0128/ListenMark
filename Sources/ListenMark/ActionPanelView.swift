import SwiftUI

/// Drives the floating panel. The toolbar is data-driven from ActionStore;
/// the row is a fixed slim height and never grows — results appear in a capped
/// card below it (and 朗读 stays compact).
final class PanelModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading(String)                                                              // action name
        case result(action: String, icon: String, text: String, replay: Bool, archived: Bool, compact: Bool)
        case error(String)
    }

    @Published var phase: Phase = .idle
    @Published var active: String?      // active action id (drives the accent)
    @Published var contentWidth: CGFloat = 380   // measured to fit the enabled skills

    var onPick: ((ActionDef) -> Void)?
    var onReplay: (() -> Void)?
    var onStop: (() -> Void)?
    var onArchive: (() -> Void)?
    var onCopyOriginal: (() -> Void)?
    var onClose: (() -> Void)?
    var onOpenArchive: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenActions: (() -> Void)?
    var onOpenReview: (() -> Void)?
}

struct ActionPanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject private var store = ActionStore.shared

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
            ForEach(store.enabled) { def in
                ActionItem(def: def, active: model.active == def.id) { model.onPick?(def) }
            }
            Divider().frame(height: 18).padding(.horizontal, 2)
            Menu {
                Button("复制原文") { model.onCopyOriginal?() }
                Divider()
                Button("今日回响…") { model.onOpenReview?() }
                Button("编辑技能…") { model.onOpenActions?() }
                Button("打开档案…") { model.onOpenArchive?() }
                Button("设置…") { model.onOpenSettings?() }
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
            .help("关闭")
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
    }

    // MARK: Result card

    @ViewBuilder private var resultArea: some View {
        switch model.phase {
        case .idle:
            EmptyView()

        case .loading(let label):
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text("正在\(label)…").font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 13)

        case .result(let action, let icon, let text, let replay, let archived, let compact):
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: archived ? "checkmark.seal.fill" : icon)
                        .font(.system(size: 11))
                        .foregroundStyle(archived ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    Text(action).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if archived {
                        Text("已留档").font(.system(size: 10)).foregroundStyle(.tertiary)
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
                Button { model.onReplay?() } label: { Label("重听", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
            }
            Button { model.onStop?() } label: { Label("停止", systemImage: "stop.fill") }
                .buttonStyle(.bordered)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.bordered).help("复制结果")
            if replay && !archived {
                Button { model.onArchive?() } label: { Label("留档", systemImage: "tray.and.arrow.down.fill") }
                    .buttonStyle(.bordered).tint(.accentColor)
            }
            Spacer()
            Button { model.onClose?() } label: { Image(systemName: "xmark") }
                .buttonStyle(.bordered).help("关闭")
        }
        .controlSize(.small)
        .buttonBorderShape(.capsule)
    }
}

// MARK: - Pieces

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
                Text(def.name).font(.system(size: 12)).lineLimit(1)
            }
            .padding(.horizontal, 9)
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
