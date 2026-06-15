import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case preferences
    case services
    case actions
    case archive
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preferences: return AppFlavor.text("偏好", "Preferences")
        case .services: return AppFlavor.text("服务", "Services")
        case .actions: return AppFlavor.text("技能", "Actions")
        case .archive: return AppFlavor.text("留档", "Archive")
        case .about: return AppFlavor.text("关于", "About")
        }
    }

    var icon: String {
        switch self {
        case .preferences: return "slider.horizontal.3"
        case .services: return "server.rack"
        case .actions: return "wand.and.stars"
        case .archive: return "tray.and.arrow.down.fill"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @State private var page: SettingsPage
    @State private var loadedPages: Set<SettingsPage>
    @AppStorage("autoPop") private var autoPop = true
    @AppStorage("autoPopCopyFallback") private var autoPopCopyFallback = true
    @AppStorage("autoDismissPanel") private var autoDismissPanel = true
    @AppStorage("hkDisplay") private var hkDisplay = "⌥⌘R"
    @AppStorage("ocrHkDisplay") private var ocrHkDisplay = "⌃⇧O"
    @AppStorage("silentOcrHkDisplay") private var silentOcrHkDisplay = "⌃⇧C"
    @AppStorage("inputHkDisplay") private var inputHkDisplay = "⌃⇧I"
    @AppStorage("ocrAutoRunLastAction") private var ocrAutoRunLastAction = true

    @AppStorage("useFullContext") private var useFullContext = true
    @AppStorage("autoSpeakAI") private var autoSpeakAI = true
    @AppStorage("autoArchive") private var autoArchive = false
    @AppStorage("historyEnabled") private var historyEnabled = true
    @AppStorage("archiveFolder") private var archiveFolder = ""

    @State private var disabledAppsRevision = 0

    init(initialPage: SettingsPage = .preferences) {
        _page = State(initialValue: initialPage)
        _loadedPages = State(initialValue: [initialPage])
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 172)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 980, minHeight: 680)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppFlavor.appName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 6)
            ForEach(SettingsPage.allCases) { item in
                Button {
                    selectPage(item)
                } label: {
                    sidebarRow(item)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .background(.bar)
    }

    private func sidebarRow(_ item: SettingsPage) -> some View {
        Label(item.title, systemImage: item.icon)
            .font(.system(size: 13, weight: page == item ? .semibold : .regular))
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .padding(.horizontal, 10)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(page == item ? Color.accentColor.opacity(0.14) : Color.clear)
            }
            .foregroundStyle(page == item ? Color.accentColor : Color.primary)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func selectPage(_ item: SettingsPage) {
        guard item != page else { return }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            loadedPages.insert(item)
            page = item
        }
    }

    private var content: some View {
        ZStack {
            ForEach(SettingsPage.allCases) { item in
                if loadedPages.contains(item) {
                    pageContent(item)
                        .opacity(page == item ? 1 : 0)
                        .allowsHitTesting(page == item)
                        .accessibilityHidden(page != item)
                }
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    @ViewBuilder private func pageContent(_ item: SettingsPage) -> some View {
        switch item {
        case .preferences:
            preferencesPane
        case .services:
            ServicesView()
        case .actions:
            ActionsConfigView()
                .padding(10)
        case .archive:
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    archiveSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .about:
            AboutView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var preferencesPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                captureSection
                fallbackSection
                behaviorSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppFlavor.text("设置", "Settings"))
                .font(.system(size: 24, weight: .semibold))
            Text(AppFlavor.text("调整工具条、取词、输入、OCR 和朗读行为。",
                                "Adjust panel, capture, input, OCR, and speech behavior."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var captureSection: some View {
        SettingsSection(title: AppFlavor.text("触发与自动弹出", "Trigger and Auto-Pop"),
                        subtitle: AppFlavor.text("选择文字后是否显示工具条，以及取不到文字时是否尝试复制读取。",
                                                 "Choose when the panel appears and whether Dob can try copy-based capture.")) {
            SettingToggle(title: AppFlavor.text("划词后自动弹出", "Show after selection"),
                          subtitle: AppFlavor.text("选中文本后自动显示工具条。", "Show the panel automatically after selecting text."),
                          isOn: $autoPop) {
                NotificationCenter.default.post(name: .gebwConfigChanged, object: nil)
            }
            SettingToggle(title: AppFlavor.text("取不到文字时尝试复制读取", "Try copy-based capture"),
                          subtitle: AppFlavor.text("适合微信内置浏览器等难取词界面；会尽量恢复原剪贴板。",
                                                   "Helps in WebViews and hard-to-capture apps; the clipboard is restored when possible."),
                          isOn: $autoPopCopyFallback)
                .disabled(!autoPop)
            SettingToggle(title: AppFlavor.text("无操作自动消失", "Auto-hide when idle"),
                          subtitle: AppFlavor.text("工具条出现后，鼠标明显远离且未触及工具条时自动渐隐；固定窗口不受影响。",
                                                   "After the panel appears, fade it out when the pointer clearly moves away without entering it. Pinned windows are unaffected."),
                          isOn: $autoDismissPanel) {
                NotificationCenter.default.post(name: .gebwConfigChanged, object: nil)
            }
            disabledAppsList
            HotkeySetting(title: AppFlavor.text("弹出工具条", "Show panel"),
                          subtitle: AppFlavor.text("手动处理当前选中文本。", "Manually process the current selection."),
                          display: $hkDisplay) { code, mods, disp in
                Settings.hotKeyCode = Int(code)
                Settings.hotKeyMods = carbonModifiers(mods)
                Settings.hotKeyDisplay = disp
                hkDisplay = disp
                NotificationCenter.default.post(name: .gebwConfigChanged, object: nil)
            }
        }
    }

    private var disabledApps: [(bundleID: String, name: String)] {
        _ = disabledAppsRevision
        return Settings.disabledAutoPopAppsSorted
    }

    @ViewBuilder private var disabledAppsList: some View {
        let apps = disabledApps
        if !apps.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text(AppFlavor.text("已禁用自动弹出的应用", "Apps with Auto-Pop Disabled"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(apps, id: \.bundleID) { app in
                    HStack(spacing: 10) {
                        Image(systemName: "app")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Text(app.bundleID)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button(AppFlavor.text("恢复", "Enable")) {
                            Settings.enableAutoPop(bundleID: app.bundleID)
                            disabledAppsRevision += 1
                            NotificationCenter.default.post(name: .gebwConfigChanged, object: nil)
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var fallbackSection: some View {
        SettingsSection(title: AppFlavor.text("输入与 OCR", "Input and OCR"),
                        subtitle: AppFlavor.text("无法取词时，可以手动输入、框选识别，或直接复制 OCR 结果。",
                                                 "When capture fails, type manually, select a screen region, or copy OCR text directly.")) {
            HotkeySetting(title: AppFlavor.text("输入面板", "Input panel"),
                          subtitle: AppFlavor.text("打开工具条和文本框，可粘贴或输入任意内容再处理。",
                                                   "Open the toolbar with a text box, then paste or type any text."),
                          display: $inputHkDisplay) { code, mods, disp in
                Settings.inputHotKeyCode = Int(code)
                Settings.inputHotKeyMods = carbonModifiers(mods)
                Settings.inputHotKeyDisplay = disp
                inputHkDisplay = disp
                NotificationCenter.default.post(name: .gebwConfigChanged, object: nil)
            }
            HotkeySetting(title: AppFlavor.text("屏幕选框 OCR", "Screen selection OCR"),
                          subtitle: AppFlavor.text("框选屏幕区域识别文字，识别后打开工具条。",
                                                   "Select a screen region for OCR, then open the panel."),
                          display: $ocrHkDisplay) { code, mods, disp in
                Settings.ocrHotKeyCode = Int(code)
                Settings.ocrHotKeyMods = carbonModifiers(mods)
                Settings.ocrHotKeyDisplay = disp
                ocrHkDisplay = disp
                NotificationCenter.default.post(name: .gebwConfigChanged, object: nil)
            }
            SettingToggle(title: AppFlavor.text("OCR 后执行最近一次技能", "Run last action after OCR"),
                          subtitle: AppFlavor.text("适合连续 OCR 翻译、解释或朗读。", "Useful for repeated OCR translate, explain, or read flows."),
                          isOn: $ocrAutoRunLastAction)
            HotkeySetting(title: AppFlavor.text("静默 OCR 复制", "Silent OCR copy"),
                          subtitle: AppFlavor.text("框选后直接复制识别结果，不显示工具条。", "Copy recognized text directly without showing the panel."),
                          display: $silentOcrHkDisplay) { code, mods, disp in
                Settings.silentOCRHotKeyCode = Int(code)
                Settings.silentOCRHotKeyMods = carbonModifiers(mods)
                Settings.silentOCRHotKeyDisplay = disp
                silentOcrHkDisplay = disp
                NotificationCenter.default.post(name: .gebwConfigChanged, object: nil)
            }
        }
    }

    private var behaviorSection: some View {
        SettingsSection(title: AppFlavor.text("结果行为", "Result Behavior"),
                        subtitle: AppFlavor.text("选择 AI 回答是否带上下文，以及生成后是否读出来。",
                                                 "Choose whether AI uses context and whether results are spoken aloud.")) {
            SettingToggle(title: AppFlavor.text("默认使用全文上下文", "Use full-text context by default"),
                          subtitle: AppFlavor.text("能拿到全文时，把选中内容和上下文一起交给模型；拿不到时自动回退。",
                                                   "When available, send both selection and surrounding context to the model; otherwise fall back."),
                          isOn: $useFullContext)
            SettingToggle(title: AppFlavor.text("AI 技能完成后自动朗读", "Auto-read AI results"),
                          subtitle: AppFlavor.text("关闭后，解释、翻译、提炼等结果默认只显示不朗读；朗读技能不受影响。",
                                                   "When off, Explain, Translate, and similar results show without speaking. Read is unaffected."),
                          isOn: $autoSpeakAI)
        }
    }

    private var archiveSection: some View {
        SettingsSection(title: AppFlavor.text("留档与历史", "Archive and History"),
                        subtitle: AppFlavor.text("留档用于长期复习；历史用于临时回看。",
                                                 "Archive is for review; History is for quick lookup.")) {
            archiveSubsectionHeader(icon: "tray.and.arrow.down.fill",
                                    title: AppFlavor.text("主动留档", "Archive"),
                                    subtitle: AppFlavor.text("进入 Markdown 档案和今日回响，适合长期复习。",
                                                             "Saved into Markdown archive and Review, for long-term recall."))
            SettingToggle(title: AppFlavor.text("自动留档每次动作", "Auto-save every action"),
                          subtitle: AppFlavor.text("关闭后，只在你点击「留档」时保存。", "When off, Dob saves only when you click Save."),
                          isOn: $autoArchive)
            archiveLocationControls
            Divider()
            archiveSubsectionHeader(icon: "clock.arrow.circlepath",
                                    title: AppFlavor.text("静默历史", "Silent History"),
                                    subtitle: AppFlavor.text("只保留最近 500 条临时记录，不进入档案，也不参与今日回响。",
                                                             "Keeps only the latest 500 lightweight records. It does not enter Archive or Review."))
            SettingToggle(title: AppFlavor.text("记录最近 500 条历史", "Keep latest 500 history items"),
                          subtitle: AppFlavor.text("保存原文、结果、动作和来源；不保存全文上下文。",
                                                   "Stores source text, result, action, and app. Full-text context is not stored."),
                          isOn: $historyEnabled)
            Button {
                NotificationCenter.default.post(name: .gebwOpenHistory, object: nil)
            } label: {
                Label(AppFlavor.text("打开历史记录", "Open History"), systemImage: "clock.arrow.circlepath")
            }
            .controlSize(.small)
        }
    }

    private var archiveLocationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppFlavor.text("Markdown 留存位置", "Markdown archive location"))
                .font(.system(size: 13, weight: .semibold))
            HStack {
                Text(archiveFolder.isEmpty ? AppFlavor.text("默认：应用支持目录", "Default: Application Support") : archiveFolder)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(AppFlavor.text("选择…", "Choose…")) { pickFolder() }
            }
            HStack {
                Button(AppFlavor.text("在访达中显示", "Show in Finder")) {
                    NSWorkspace.shared.open(ArchiveStore.shared.revealFolder)
                }
                if !archiveFolder.isEmpty {
                    Button(AppFlavor.text("用默认", "Use Default")) {
                        archiveFolder = ""
                        ArchiveStore.shared.relocate()
                    }
                }
            }
        }
    }

    private func archiveSubsectionHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = AppFlavor.text("选择", "Choose")
        if panel.runModal() == .OK, let url = panel.url {
            archiveFolder = url.path
            ArchiveStore.shared.relocate()
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                content
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.035)))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
    }
}

private struct SettingToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var onChange: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .onChange(of: isOn) { _, _ in onChange?() }
        }
    }
}

private struct HotkeySetting: View {
    let title: String
    let subtitle: String
    @Binding var display: String
    var onRecord: (UInt16, NSEvent.ModifierFlags, String) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            HotkeyRecorder(display: $display, onRecord: onRecord)
                .frame(width: 176, height: 22)
        }
    }
}
