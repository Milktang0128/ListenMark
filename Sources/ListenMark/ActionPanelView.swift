import AppKit
import SwiftUI

enum ActionPanelLayout {
    static let visibleActionLimit = 5
}

enum ActionResultLayout {
    static let textViewportMinHeight: CGFloat = 42
    static let textViewportMaxHeight: CGFloat = 190

    private static let outerHorizontalPadding: CGFloat = 28
    private static let cardHorizontalPadding: CGFloat = 18
    private static let cardVerticalPadding: CGFloat = 18
    private static let textFontSize: CGFloat = 13
    private static let textLineSpacing: CGFloat = 2

    static func textViewportHeight(for text: String, panelWidth: CGFloat) -> CGFloat {
        let width = max(180, panelWidth - outerHorizontalPadding - cardHorizontalPadding)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = textLineSpacing
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: NSFont.systemFont(ofSize: textFontSize),
                .paragraphStyle: paragraph
            ]
        )
        let measured = ceil(rect.height) + 2
        return min(max(measured, textViewportMinHeight), textViewportMaxHeight)
    }

    static func panelHeight(for text: String, panelWidth: CGFloat, barHeight: CGFloat) -> CGFloat {
        let headerHeight: CGFloat = 18
        let toggleHeight: CGFloat = 18
        let controlsHeight: CGFloat = 28
        let outerVerticalPadding: CGFloat = 22
        let verticalSpacing: CGFloat = 27
        let textCardHeight = textViewportHeight(for: text, panelWidth: panelWidth) + cardVerticalPadding
        return barHeight + outerVerticalPadding + headerHeight + textCardHeight + toggleHeight + controlsHeight + verticalSpacing
    }

    static func maxPanelHeight(barHeight: CGFloat) -> CGFloat {
        panelHeight(for: String(repeating: "Dob ", count: 800), panelWidth: 320, barHeight: barHeight)
    }
}

enum ActionCompareLayout {
    static let viewportMaxHeight: CGFloat = 430

    private static let outerHorizontalPadding: CGFloat = 28
    private static let cardHorizontalPadding: CGFloat = 18
    private static let cardVerticalPadding: CGFloat = 18
    private static let rowSpacing: CGFloat = 8
    private static let textLineSpacing: CGFloat = 2

    static func viewportHeight(for results: [CompareModelResult], panelWidth: CGFloat) -> CGFloat {
        let cardTotal = results.map { cardHeight(for: $0, panelWidth: panelWidth) }.reduce(0, +)
        let spacing = CGFloat(max(results.count - 1, 0)) * rowSpacing
        return min(max(cardTotal + spacing, 160), viewportMaxHeight)
    }

    static func panelHeight(for results: [CompareModelResult], panelWidth: CGFloat, barHeight: CGFloat) -> CGFloat {
        let headerHeight: CGFloat = 18
        let controlsHeight: CGFloat = 28
        let outerVerticalPadding: CGFloat = 31
        let verticalSpacing: CGFloat = 18
        return barHeight + headerHeight + viewportHeight(for: results, panelWidth: panelWidth) + controlsHeight + outerVerticalPadding + verticalSpacing
    }

    private static func cardHeight(for result: CompareModelResult, panelWidth: CGFloat) -> CGFloat {
        let textHeight: CGFloat
        if result.isLoading || result.error != nil || result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textHeight = 34
        } else {
            textHeight = measuredTextHeight(result.text, panelWidth: panelWidth)
        }
        return 22 + textHeight + cardVerticalPadding
    }

    private static func measuredTextHeight(_ text: String, panelWidth: CGFloat) -> CGFloat {
        let width = max(220, panelWidth - outerHorizontalPadding - cardHorizontalPadding)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = textLineSpacing
        let fontSize = CGFloat(13 + Settings.panelTextSizeDelta)
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .paragraphStyle: paragraph
            ]
        )
        return min(max(ceil(rect.height) + 2, 42), 138)
    }
}

/// Drives the floating panel. The toolbar is data-driven from ActionStore;
/// the row is a fixed slim height and never grows — results appear in a capped
/// card below it (and 朗读 stays compact).
final class PanelModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case input
        case captureNotice(source: String, text: String)
        case loading(String)                                                              // action name
        case result(action: String, icon: String, text: String, replay: Bool,
                    archived: Bool, compact: Bool, contextUsed: Bool)
        case compare(action: String, icon: String, results: [CompareModelResult],
                     archived: Bool, contextUsed: Bool)
        case error(String)
    }

    @Published var phase: Phase = .idle
    @Published var active: String?      // active action id (drives the accent)
    @Published var contentWidth: CGFloat = 320   // measured to fit the enabled skills
    @Published var inputText: String = ""
    @Published var pinned = false
    @Published var canCompare = false
    @Published var selectedCompareID: String?
    @Published var disableAppName: String?

    var onPick: ((ActionDef) -> Void)?
    var onInputChanged: ((String) -> Void)?
    var onReplay: (() -> Void)?
    var onStop: (() -> Void)?
    var onRetry: (() -> Void)?
    var onArchive: (() -> Void)?
    var onArchiveOriginal: (() -> Void)?
    var onCopyOriginal: (() -> Bool)?
    var onCopyResult: ((String) -> Bool)?
    var onCopyKeyboard: (() -> Bool)?
    var onCompare: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var onAutoSpeakChanged: ((Bool) -> Void)?
    var onDisableForCurrentApp: (() -> Void)?
    var onDisableGlobally: (() -> Void)?
    var onClose: (() -> Void)?
    var onOpenArchive: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenActions: (() -> Void)?
    var onOpenReview: (() -> Void)?
}

struct ActionPanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject private var store = ActionStore.shared
    @ObservedObject private var speaker = Speaker.shared
    @State private var showOriginalCopyBubble = false
    @State private var showResultCopyBubble = false
    @State private var originalCopyArchived = false
    @State private var resultCopyArchived = false
    @State private var originalCopyToken = UUID()
    @State private var resultCopyToken = UUID()
    @State private var inputFocusRequest = 0
    @AppStorage("autoSpeakAI") private var autoSpeakAI = true
    @AppStorage("panelTextSizeDelta") private var panelTextSizeDelta = 0

    private var resultFontSize: CGFloat { CGFloat(13 + panelTextSizeDelta) }

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
        .onAppear {
            if model.phase == .input {
                inputFocusRequest += 1
            }
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .input {
                inputFocusRequest += 1
            }
        }
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
                Divider()
                Menu {
                    Button {
                        model.onDisableForCurrentApp?()
                    } label: {
                        Label(AppFlavor.text("在此应用中禁用", "Disable in This App"), systemImage: "app")
                    }
                    .disabled(model.disableAppName == nil)
                    Button {
                        model.onDisableGlobally?()
                    } label: {
                        Label(AppFlavor.text("全局禁用", "Disable Globally"), systemImage: "globe")
                    }
                } label: {
                    Label(AppFlavor.text("禁用", "Disable"), systemImage: "nosign")
                }
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

            Button { model.onTogglePin?() } label: {
                Image(systemName: model.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(model.pinned ? Color.accentColor : Color.secondary)
                    .frame(width: 22, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.pinned ? AppFlavor.text("取消固定窗口", "Unpin Window") : AppFlavor.text("固定窗口", "Pin Window"))

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

        case .input:
            VStack(alignment: .leading, spacing: 8) {
                Label(AppFlavor.text("输入内容", "Input text"), systemImage: "keyboard")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                ZStack(alignment: .topLeading) {
                    PanelInputTextView(text: inputBinding, focusRequest: inputFocusRequest)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if model.inputText.isEmpty {
                        Text(AppFlavor.text("粘贴或输入任意内容，然后选择一个技能处理", "Paste or type any text, then choose an action"))
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 1)
                            .padding(.leading, 1)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 92)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))

                Text(AppFlavor.text("可直接朗读，也可翻译、解释、审校或使用自定义技能。", "Read it directly, or translate, explain, proofread, or use a custom action."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)

        case .captureNotice(let source, let text):
            HStack(spacing: 9) {
                Image(systemName: "viewfinder.rectangular")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppFlavor.text("\(source) 已识别", "\(source) recognized"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(AppFlavor.text("已取得 \(text.count) 字，选择一个技能继续", "\(text.count) characters captured. Choose an action to continue."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(0.035))

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
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(action)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    contextStatusPill(contextUsed: contextUsed)
                    speechStatusPill
                    Spacer()
                    if archived {
                        archiveStatusLabel
                    }
                }

                if !compact {
                    ScrollView {
                        Text(text)
                            .font(.system(size: resultFontSize))
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: ActionResultLayout.textViewportHeight(for: text, panelWidth: model.contentWidth))
                    .padding(9)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))

                    autoSpeakToggle
                }

                controls(text: text, replay: replay, archived: archived)
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 12)

        case .compare(let action, let icon, let results, let archived, let contextUsed):
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(AppFlavor.text("比较 · \(action)", "Compare · \(action)"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    contextStatusPill(contextUsed: contextUsed)
                    Spacer()
                    if archived {
                        archiveStatusLabel
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(results) { result in
                            compareResultCard(result)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: ActionCompareLayout.viewportHeight(for: results, panelWidth: model.contentWidth))

                compareControls(text: compareCombinedText(results), archived: archived)
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
            if replay && model.canCompare {
                Button { model.onCompare?() } label: {
                    Image(systemName: "rectangle.split.3x1")
                }
                .buttonStyle(.bordered)
                .help(AppFlavor.text("比较模型结果", "Compare Models"))
            }
            Spacer()
            Button { model.onClose?() } label: { Image(systemName: "xmark") }
                .buttonStyle(.bordered).help(AppFlavor.text("关闭", "Close"))
        }
        .controlSize(.small)
        .buttonBorderShape(.capsule)
    }

    private func compareControls(text: String, archived: Bool) -> some View {
        HStack(spacing: 7) {
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
            .help(AppFlavor.text("复制全部比较结果", "Copy All Compare Results"))
            .popover(isPresented: $showResultCopyBubble, arrowEdge: .bottom) {
                CopyArchiveBubble(archived: archived || resultCopyArchived,
                                  canArchive: !archived && !resultCopyArchived) {
                    model.onArchive?()
                    resultCopyArchived = true
                    dismissResultCopyBubble(after: 0.65)
                }
            }
            if !archived {
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

    @ViewBuilder private var speechStatusPill: some View {
        if case .preparing(let provider) = speaker.status {
            Label(AppFlavor.text("正在生成语音", "Preparing speech"), systemImage: "waveform")
                .font(.system(size: 10, weight: .medium))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(0.10)))
                .help(AppFlavor.text("正在通过 \(provider) 生成语音，稍后会自动播放。",
                                     "Generating speech with \(provider). Playback will start shortly."))
        }
    }

    @ViewBuilder private func contextStatusPill(contextUsed: Bool) -> some View {
        if contextUsed {
            Label(AppFlavor.text("已附带上下文", "Context included"), systemImage: "doc.text.magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
    }

    private var archiveStatusLabel: some View {
        Label(AppFlavor.text("已留档", "Saved"), systemImage: "checkmark.seal.fill")
            .font(.system(size: 10, weight: .medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.green)
            .fixedSize()
    }

    private var inputBinding: Binding<String> {
        Binding(
            get: { model.inputText },
            set: { value in
                model.inputText = value
                model.onInputChanged?(value)
            }
        )
    }

    private func compareResultCard(_ result: CompareModelResult) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(result.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(result.model)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if result.isLoading {
                    ProgressView().controlSize(.small)
                } else if result.error != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }

            if let error = result.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(result.text.isEmpty ? AppFlavor.text("等待结果…", "Waiting for result...") : result.text)
                    .font(.system(size: resultFontSize))
                    .lineSpacing(2)
                    .foregroundStyle(result.text.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.5)
        }
    }

    private func compareCombinedText(_ results: [CompareModelResult]) -> String {
        results.map { result in
            let body = result.error.map { AppFlavor.text("出错：\($0)", "Error: \($0)") }
                ?? (result.text.isEmpty ? AppFlavor.text("等待结果…", "Waiting for result...") : result.text)
            return "\(result.label) · \(result.model)\n\(body)"
        }
        .joined(separator: "\n\n---\n\n")
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
