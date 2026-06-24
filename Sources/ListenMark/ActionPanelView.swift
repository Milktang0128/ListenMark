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

    // MARK: Conversation (multi-turn) layout

    static let conversationViewportMaxHeight: CGFloat = 260
    static let followUpBarHeight: CGFloat = 52

    /// Measured height of the scrollable history-turns area, capped at 260px.
    static func conversationViewportHeight(for turns: [ConversationTurn], panelWidth: CGFloat) -> CGFloat {
        guard !turns.isEmpty else { return 0 }
        let width = max(160, panelWidth - outerHorizontalPadding - cardHorizontalPadding - 22)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = textLineSpacing
        var total: CGFloat = 0
        for turn in turns {
            let rect = (turn.text as NSString).boundingRect(
                with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [
                    .font: NSFont.systemFont(ofSize: textFontSize),
                    .paragraphStyle: paragraph
                ]
            )
            // bubble v-padding (12) + spacing between bubbles (6).
            total += ceil(rect.height) + 12 + 6
        }
        return min(total, conversationViewportMaxHeight)
    }

    /// Panel height while a conversation is on screen: the regular result card
    /// plus the history viewport and the follow-up bar.
    /// Height of the inline "正在回答…" placeholder bubble (bubble v-padding +
    /// spacing) reserved while a follow-up answer hasn't started streaming.
    static let awaitingReplyBubbleHeight: CGFloat = 34

    static func conversationPanelHeight(priorTurns: [ConversationTurn], currentText: String,
                                        panelWidth: CGFloat, barHeight: CGFloat,
                                        awaitingReply: Bool = false) -> CGFloat {
        let history = conversationViewportHeight(for: priorTurns, panelWidth: panelWidth)
        let historyBlock = history > 0 ? history + 8 : 0   // + gap below the history area
        let awaitingBlock = awaitingReply ? awaitingReplyBubbleHeight + 9 : 0
        return panelHeight(for: currentText, panelWidth: panelWidth, barHeight: barHeight)
            + historyBlock + awaitingBlock + followUpBarHeight + 8
    }

    /// Worst-case conversation panel height — used to reserve drop-down headroom.
    static func maxConversationPanelHeight(barHeight: CGFloat) -> CGFloat {
        maxPanelHeight(barHeight: barHeight) + conversationViewportMaxHeight + 8 + followUpBarHeight + 8
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
        case dialogueInput(selectedText: String)   // 对话: type an instruction over the selection
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
    @Published var webActionMode: SelectionWebAction.Mode?

    // Conversation (对话 / 追问) state — deliberately OUTSIDE the Phase enum so the
    // result card's switch, height calc, and phase-diffed animation are untouched.
    @Published var priorTurns: [ConversationTurn] = []   // history turns above the live answer
    @Published var followUpText: String = ""             // follow-up input, separate from inputText
    @Published var isConversing: Bool = false            // drives guards + hides Compare
    @Published var conversationAtTurnLimit: Bool = false // disables the follow-up bar when hit
    @Published var canFollowUp: Bool = false             // a needsLLM result shows the follow-up bar
    @Published var isAwaitingReply: Bool = false         // user turn submitted, assistant answer not yet streaming
    @Published var dialogueInstruction: String = ""      // 对话 turn-0 instruction; NEVER synced to currentText
    var onFollowUpSubmit: ((String) -> Void)?
    var onExitConversation: (() -> Void)?
    var onDialogueSubmit: ((String) -> Void)?
    var onDialogueCancel: (() -> Void)?

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
    var onWebAction: (() -> Bool)?
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
    @State private var followUpFocusRequest = 0
    @AppStorage("autoSpeakAI") private var autoSpeakAI = true
    @AppStorage("panelTextSizeDelta") private var panelTextSizeDelta = 0

    private var resultFontSize: CGFloat { CGFloat(13 + panelTextSizeDelta) }

    private func needsInputFocus(_ phase: PanelModel.Phase) -> Bool {
        switch phase {
        case .input, .dialogueInput: return true
        default: return false
        }
    }

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
            if needsInputFocus(model.phase) {
                inputFocusRequest += 1
            }
        }
        .onChange(of: model.phase) { _, phase in
            if needsInputFocus(phase) {
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
            if let mode = model.webActionMode {
                Button {
                    _ = model.onWebAction?()
                } label: {
                    Image(systemName: mode == .link ? "arrow.up.right.square" : "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(mode == .link ? AppFlavor.text("打开链接", "Open Link") : AppFlavor.text("搜索原文", "Search Selection"))
            }
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

        case .dialogueInput(let selectedText):
            VStack(alignment: .leading, spacing: 8) {
                Label(AppFlavor.text("基于这段内容展开对话", "Start a conversation about this"), systemImage: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                ZStack(alignment: .topLeading) {
                    PanelInputTextView(text: dialogueBinding,
                                       focusRequest: inputFocusRequest,
                                       onSubmit: { model.onDialogueSubmit?(model.dialogueInstruction) },
                                       onCancel: { model.onDialogueCancel?() })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if model.dialogueInstruction.isEmpty {
                        Text(AppFlavor.text("基于这段内容展开对话…例如「换个说法」「举个例子」", "Start a conversation about this… e.g. 'rephrase', 'give an example'"))
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 1)
                            .padding(.leading, 1)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 78)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))

                Text(selectedText.isEmpty
                     ? AppFlavor.text("回车发送，留空回车取消。", "Press Return to send, or Return on an empty line to cancel.")
                     : AppFlavor.text("已选中 \(selectedText.count) 字，回车发送。", "\(selectedText.count) characters selected. Press Return to send."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)

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

                if !model.priorTurns.isEmpty {
                    conversationHistoryView
                }

                if model.isAwaitingReply {
                    awaitingReplyBubble
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

                if model.canFollowUp {
                    followUpBar
                }
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
                playbackButton
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
            if replay && model.canCompare && !model.isConversing {
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

    private var playbackButton: some View {
        Button {
            handlePlaybackButton()
        } label: {
            Image(systemName: playbackButtonIcon)
        }
        .buttonStyle(.borderedProminent)
        .disabled(speaker.isPreparing)
        .help(playbackButtonHelp)
    }

    private func handlePlaybackButton() {
        if speaker.isPlaying {
            Speaker.shared.pause()
        } else if speaker.isPaused {
            Speaker.shared.resume()
        } else if !speaker.isPreparing {
            model.onReplay?()
        }
    }

    private var playbackButtonIcon: String {
        if speaker.isPlaying { return "pause.fill" }
        if speaker.isPaused { return "play.fill" }
        if speaker.isPreparing { return "hourglass" }
        return "play.fill"
    }

    private var playbackButtonHelp: String {
        if speaker.isPlaying { return AppFlavor.text("暂停", "Pause") }
        if speaker.isPaused { return AppFlavor.text("继续", "Resume") }
        if speaker.isPreparing { return AppFlavor.text("正在生成语音，可用停止取消", "Preparing speech. Use Stop to cancel.") }
        return AppFlavor.text("从头重听", "Replay from Start")
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

    // MARK: Conversation (multi-turn) UI

    private var conversationHistoryView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.priorTurns) { turn in
                        conversationBubble(turn)
                            .id(turn.id)
                    }
                    Color.clear.frame(height: 1).id(conversationBottomAnchor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: ActionResultLayout.conversationViewportHeight(for: model.priorTurns,
                                                                         panelWidth: model.contentWidth))
            .onChange(of: model.priorTurns.count) { _, _ in
                proxy.scrollTo(conversationBottomAnchor, anchor: .bottom)
            }
        }
    }

    private let conversationBottomAnchor = "conversation-bottom"

    private func conversationBubble(_ turn: ConversationTurn) -> some View {
        let isUser = turn.role == .user
        return HStack(spacing: 0) {
            if isUser { Spacer(minLength: 24) }
            Text(turn.text)
                .font(.system(size: 13))
                .lineSpacing(2)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isUser ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.045))
                )
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 24) }
        }
    }

    /// Left-aligned assistant placeholder shown after a follow-up is submitted but
    /// before the answer starts streaming, so the user sees a "responding" state.
    private var awaitingReplyBubble: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text(AppFlavor.text("正在回答…", "Responding…"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.primary.opacity(0.045))
            )
            Spacer(minLength: 24)
        }
    }

    private var followUpBar: some View {
        HStack(spacing: 7) {
            ZStack(alignment: .topLeading) {
                PanelInputTextView(text: followUpBinding,
                                   focusRequest: followUpFocusRequest,
                                   contentInset: NSSize(width: 5, height: 8),
                                   onSubmit: { submitFollowUp() },
                                   onCancel: { model.onExitConversation?() })
                    .frame(height: 34)
                if model.followUpText.isEmpty {
                    Text(model.conversationAtTurnLimit
                         ? AppFlavor.text("已达对话轮数上限，请留档或重新开始", "Turn limit reached — save or start over")
                         : AppFlavor.text("继续追问…", "Ask a follow-up…"))
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))
            .opacity(model.conversationAtTurnLimit ? 0.5 : 1)

            Button { submitFollowUp() } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(model.conversationAtTurnLimit ||
                      model.followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help(AppFlavor.text("发送", "Send"))
        }
        .onAppear { followUpFocusRequest += 1 }
    }

    private func submitFollowUp() {
        let text = model.followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !model.conversationAtTurnLimit else { return }
        model.onFollowUpSubmit?(text)
    }

    private var followUpBinding: Binding<String> {
        Binding(
            get: { model.followUpText },
            set: { model.followUpText = $0 }
        )
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

    /// 对话 turn-0 instruction. Deliberately does NOT touch `inputText` /
    /// `onInputChanged`, so the typed instruction never leaks into `currentText`
    /// (which still holds the selected text).
    private var dialogueBinding: Binding<String> {
        Binding(
            get: { model.dialogueInstruction },
            set: { model.dialogueInstruction = $0 }
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
