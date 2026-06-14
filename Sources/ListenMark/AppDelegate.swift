import AppKit
import SwiftUI
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let panel = ActionPanel()

    private var outsideMonitor: Any?
    private var mouseUpMonitor: Any?
    private weak var triggerMenuItem: NSMenuItem?

    private var archiveWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var actionsWindow: NSWindow?
    private var reviewWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private weak var reviewMenuItem: NSMenuItem?

    private var currentText = ""
    private var currentContext = ""
    private var currentContextSource: SelectionGrabber.ContextSource?
    private var currentSource = ""
    private var currentResult = ""
    private var currentAction: ActionDef?
    private var currentContextUsed = false
    private var pendingEntry: Entry?
    private var lastAutoText = ""
    private var streamTask: Task<Void, Never>?
    private var actionGeneration = 0
    private var enabledPIDs = Set<pid_t>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = ArchiveStore.shared
        _ = ActionStore.shared
        setupMainMenu()
        setupStatusItem()
        wirePanel()
        applyConfig()
        NotificationCenter.default.addObserver(self, selector: #selector(applyConfig),
                                               name: .gebwConfigChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openActions),
                                               name: .gebwOpenActions, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivated(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier { enableAX(pid) }
        checkTrust()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            GitHubReleaseUpdater.shared.checkAutomaticallyIfNeeded()
        }
    }

    @objc private func appActivated(_ note: Notification) {
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            enableAX(app.processIdentifier)
        }
    }

    private func enableAX(_ pid: pid_t) {
        guard !enabledPIDs.contains(pid) else { return }
        enabledPIDs.insert(pid)
        SelectionGrabber.enableAccessibility(for: pid)
    }

    private func wirePanel() {
        let m = panel.model
        m.onPick = { [weak self] def in self?.perform(def) }
        m.onReplay = { [weak self] in
            guard let self else { return }
            Speaker.shared.replay(self.currentResult.isEmpty ? self.currentText : self.currentResult)
        }
        m.onStop = { [weak self] in
            Speaker.shared.stop()
            self?.streamTask?.cancel()
        }
        m.onArchive = { [weak self] in
            self?.archivePendingEntry(updatePanel: true)
        }
        m.onArchiveOriginal = { [weak self] in
            self?.archiveOriginalCopy()
        }
        m.onCopyOriginal = { [weak self] in
            guard let self, !self.currentText.isEmpty else { return false }
            self.copyToPasteboard(self.currentText)
            return true
        }
        m.onCopyResult = { [weak self] text in
            guard let self, !text.isEmpty else { return false }
            self.copyToPasteboard(text)
            return true
        }
        m.onAutoSpeakChanged = { enabled in
            if !enabled {
                Speaker.shared.stop()
            }
        }
        m.onClose = { [weak self] in self?.closePanel() }
        m.onOpenArchive = { [weak self] in self?.openArchive() }
        m.onOpenSettings = { [weak self] in self?.openSettings() }
        m.onOpenActions = { [weak self] in self?.openActions() }
        m.onOpenReview = { [weak self] in self?.openReview() }
    }

    // MARK: - Main menu (enables ⌘C/⌘V/⌘X/⌘A in text fields)

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        let aboutItem = NSMenuItem(title: AppFlavor.text("关于 \(AppFlavor.appName)", "About \(AppFlavor.appName)"),
                                   action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: AppFlavor.text("隐藏 \(AppFlavor.appName)", "Hide \(AppFlavor.appName)"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: AppFlavor.text("退出 \(AppFlavor.appName)", "Quit \(AppFlavor.appName)"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: AppFlavor.text("编辑", "Edit"))
        editMenu.addItem(withTitle: AppFlavor.text("撤销", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: AppFlavor.text("重做", "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: AppFlavor.text("剪切", "Cut"), action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: AppFlavor.text("复制", "Copy"), action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: AppFlavor.text("粘贴", "Paste"), action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: AppFlavor.text("全选", "Select All"), action: Selector(("selectAll:")), keyEquivalent: "a")
        editItem.submenu = editMenu
        NSApp.mainMenu = mainMenu
    }

    // MARK: - Config (hotkey + auto-pop)

    @objc private func applyConfig() {
        HotkeyManager.shared.unregisterAll()
        if !HotkeyManager.shared.register(id: 1,
                                          keyCode: UInt32(Settings.hotKeyCode),
                                          carbonModifiers: UInt32(Settings.hotKeyMods),
                                          onFire: { [weak self] in
            self?.triggerCapture()
        }) {
            NSLog("ListenMark · \(AppFlavor.text("弹出面板快捷键注册失败", "panel hotkey registration failed"))：\(Settings.hotKeyDisplay)")
        }
        if !HotkeyManager.shared.register(id: 2,
                                          keyCode: UInt32(Settings.ocrHotKeyCode),
                                          carbonModifiers: UInt32(Settings.ocrHotKeyMods),
                                          onFire: { [weak self] in
            self?.triggerScreenOCR()
        }) {
            NSLog("ListenMark · \(AppFlavor.text("屏幕 OCR 快捷键注册失败", "screen OCR hotkey registration failed"))：\(Settings.ocrHotKeyDisplay)")
        }
        registerActionHotKeys()
        triggerMenuItem?.title = "\(AppFlavor.text("处理选中文本", "Process Selection"))  \(Settings.hotKeyDisplay)"

        if let m = mouseUpMonitor { NSEvent.removeMonitor(m); mouseUpMonitor = nil }
        if Settings.autoPop {
            mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                self?.handleSelectionMouseUp()
            }
        }
    }

    private func registerActionHotKeys() {
        for (index, action) in ActionStore.shared.actions.enumerated() {
            guard action.enabled,
                  let keyCode = action.hotKeyCode,
                  let mods = action.hotKeyMods else { continue }
            if !HotkeyManager.shared.register(id: UInt32(1_000 + index),
                                              keyCode: UInt32(keyCode),
                                              carbonModifiers: UInt32(mods),
                                              onFire: { [weak self] in
                self?.triggerAction(action.id)
            }) {
                NSLog("ListenMark · \(AppFlavor.text("技能快捷键注册失败", "action hotkey registration failed"))：\(action.name) \(action.hotKeyDisplay ?? "")")
            }
        }
    }

    private func handleSelectionMouseUp() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self else { return }
            guard !self.panel.isVisible else { return }
            let contextSource = SelectionGrabber.contextSource()
            guard let text = SelectionGrabber.axSelectedText() else {
                self.lastAutoText = ""
                self.currentContext = ""
                self.currentContextSource = nil
                self.currentContextUsed = false
                return
            }
            guard text != self.lastAutoText else { return }
            self.cancelActiveAction()
            self.lastAutoText = text
            self.currentSource = NSWorkspace.shared.frontmostApplication?.localizedName ?? AppFlavor.text("未知来源", "Unknown Source")
            self.currentText = text
            self.currentContext = ""
            self.currentContextSource = contextSource
            self.currentContextUsed = false
            self.currentResult = ""
            self.pendingEntry = nil
            self.showPanel()
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "ear", accessibilityDescription: AppFlavor.appName)
            btn.image?.isTemplate = true
        }
        let menu = NSMenu()
        let trigger = NSMenuItem(title: AppFlavor.text("处理选中文本", "Process Selection"), action: #selector(triggerFromMenu), keyEquivalent: "")
        trigger.target = self
        menu.addItem(trigger)
        triggerMenuItem = trigger
        menu.addItem(.separator())
        let review = NSMenuItem(title: AppFlavor.text("今日回响…", "Review…"), action: #selector(openReview), keyEquivalent: "")
        review.target = self
        menu.addItem(review)
        reviewMenuItem = review
        add(menu, AppFlavor.text("打开档案…", "Open Archive…"), #selector(openArchive))
        add(menu, AppFlavor.text("编辑技能…", "Edit Actions…"), #selector(openActions))
        add(menu, AppFlavor.text("设置…", "Settings…"), #selector(openSettings))
        add(menu, AppFlavor.text("检查更新…", "Check for Updates…"), #selector(checkForUpdates))
        add(menu, AppFlavor.text("关于 \(AppFlavor.appName)…", "About \(AppFlavor.appName)…"), #selector(openAbout))
        menu.addItem(.separator())
        add(menu, AppFlavor.text("辅助功能权限设置…", "Accessibility Settings…"), #selector(openAXPrefs))
        add(menu, AppFlavor.text("打开档案文件夹", "Open Archive Folder"), #selector(openArchiveFolder))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: AppFlavor.text("退出 \(AppFlavor.appName)", "Quit \(AppFlavor.appName)"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
    }

    // Refresh the 今日回响 due-count badge each time the menu opens (passive nudge).
    func menuNeedsUpdate(_ menu: NSMenu) {
        let n = ArchiveStore.shared.dueCount
        reviewMenuItem?.title = n > 0 ? AppFlavor.text("今日回响（\(n)）…", "Review (\(n))…") : AppFlavor.text("今日回响…", "Review…")
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    // MARK: - Trigger

    @objc private func triggerFromMenu() { triggerCapture() }

    private func triggerCapture() {
        triggerSelection(actionID: nil)
    }

    private func triggerAction(_ actionID: String) {
        triggerSelection(actionID: actionID)
    }

    private func triggerScreenOCR() {
        cancelActiveAction()
        let generation = actionGeneration
        currentSource = AppFlavor.text("屏幕 OCR", "Screen OCR")
        ScreenOCR.shared.start { [weak self] text in
            guard let self else { return }
            guard self.actionGeneration == generation else { return }
            let clean = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !clean.isEmpty else {
                self.currentText = ""
                self.currentContext = ""
                self.currentContextSource = nil
                self.currentContextUsed = false
                self.currentResult = ""
                self.pendingEntry = nil
                self.showPanel()
                self.panel.model.phase = .error(AppFlavor.text("没有识别到文字——可能需要屏幕录制权限，或框选区域没有清晰文字", "No text was recognized. Screen Recording permission may be missing, or the selected area may not contain clear text."))
                return
            }

            self.currentText = clean
            self.currentContext = ""
            self.currentContextSource = nil
            self.currentContextUsed = false
            self.currentResult = ""
            self.pendingEntry = nil
            self.lastAutoText = clean
            self.showPanel()
        }
    }

    private func triggerSelection(actionID: String?) {
        cancelActiveAction()
        let generation = actionGeneration
        currentSource = NSWorkspace.shared.frontmostApplication?.localizedName ?? AppFlavor.text("未知来源", "Unknown Source")
        let contextSource = SelectionGrabber.contextSource()
        SelectionGrabber.grabAsync { [weak self] text in
            guard let self else { return }
            guard self.actionGeneration == generation else { return }
            guard let text, !text.isEmpty else {
                self.currentText = ""
                self.currentContext = ""
                self.currentContextSource = nil
                self.currentContextUsed = false
                self.showPanel()
                if SelectionGrabber.isTrusted {
                    self.panel.model.phase = .error(AppFlavor.text("没取到选中文本——先选中文字再触发", "No selected text found. Select text first, then trigger ListenMark."))
                } else {
                    self.panel.model.phase = .error(AppFlavor.text("需要「辅助功能」权限才能取词（菜单 › 辅助功能权限设置）", "Accessibility permission is required to read selected text. Use the menu item Accessibility Settings."))
                }
                return
            }
            self.currentText = text
            self.currentContext = ""
            self.currentContextSource = contextSource
            self.currentContextUsed = false
            self.lastAutoText = text
            self.currentResult = ""
            self.pendingEntry = nil
            self.showPanel()
            if let actionID {
                guard let action = ActionStore.shared.actions.first(where: { $0.id == actionID }) else {
                    self.panel.model.phase = .error(AppFlavor.text("这个技能不存在或已被删除", "This action no longer exists."))
                    return
                }
                self.perform(action)
            }
        }
    }

    // MARK: - Panel lifecycle

    private func showPanel() {
        panel.showNearMouse()
        removeOutsideMonitor()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func removeOutsideMonitor() {
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
    }

    private func closePanel() {
        removeOutsideMonitor()
        cancelActiveAction()
        panel.orderOut(nil)
    }

    private func cancelActiveAction() {
        actionGeneration += 1
        streamTask?.cancel()
        streamTask = nil
        Speaker.shared.stop()
    }

    // MARK: - Run an action

    private func perform(_ action: ActionDef) {
        let text = currentText
        guard !text.isEmpty else { return }
        cancelActiveAction()
        let generation = actionGeneration
        panel.model.active = action.id

        if action.needsLLM && Settings.llmAPIKey.isEmpty {
            panel.model.phase = .error(AppFlavor.text("「\(action.name)」需要 API Key，请到「设置」填写 OpenAI 兼容接口配置", "\(action.name) needs an API key. Add your OpenAI-compatible API settings in Settings."))
            return
        }

        if !action.needsLLM {
            currentContextUsed = false
            Speaker.shared.speak(text)
            finishResult(action: action, source: currentSource, original: text, response: nil,
                         spoken: text, contextUsed: false)
            return
        }

        panel.model.phase = .loading(action.name)
        let source = currentSource
        streamTask = Task { [weak self] in
            guard let self else { return }
            let context = self.contextText(for: text)
            let request = self.requestPayload(for: action, selectedText: text, context: context)
            let shouldContinue = await MainActor.run {
                guard self.actionGeneration == generation else { return false }
                self.currentContext = context
                self.currentContextUsed = request.contextUsed
                return true
            }
            guard shouldContinue, !Task.isCancelled else { return }

            var full = ""
            do {
                for try await delta in LLMClient.stream(prompt: request.prompt, text: request.text) {
                    full += delta
                    let snapshot = full
                    await MainActor.run {
                        guard self.actionGeneration == generation else { return }
                        // Text streams to the UI; speech waits for the full block so it
                        // reads as one coherent passage instead of choppy sentences.
                        self.panel.model.phase = .result(action: action.name, icon: action.icon,
                                                         text: snapshot, replay: false, archived: false,
                                                         compact: false, contextUsed: request.contextUsed)
                    }
                }
                let finalText = full
                await MainActor.run {
                    guard self.actionGeneration == generation else { return }
                    if Settings.autoSpeakAI {
                        Speaker.shared.speak(finalText)
                    }
                    self.finishResult(action: action, source: source, original: text, response: finalText,
                                      spoken: finalText, contextUsed: request.contextUsed)
                }
            } catch is CancellationError {
                let finalText = full
                await MainActor.run {
                    guard self.actionGeneration == generation else { return }
                    if finalText.isEmpty {
                        self.panel.model.phase = .idle
                    } else {
                        // User stopped mid-stream: keep the partial text, don't speak.
                        self.finishResult(action: action, source: source, original: text, response: finalText,
                                          spoken: finalText, contextUsed: request.contextUsed)
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.actionGeneration == generation else { return }
                    self.panel.model.phase = .error(AppFlavor.text("出错：\(Self.describe(error))", "Error: \(Self.describe(error))"))
                }
            }
        }
    }

    private func finishResult(action: ActionDef, source: String, original: String, response: String?,
                              spoken: String, contextUsed: Bool) {
        currentResult = spoken
        currentAction = action
        currentContextUsed = contextUsed
        let entry = Entry(action: action.name, icon: action.icon, sourceApp: source,
                          original: original, response: response, contextUsed: contextUsed,
                          contextExcerpt: contextUsed ? contextExcerpt(from: currentContext, selectedText: original) : nil)
        let auto = Settings.autoArchive
        if auto {
            ArchiveStore.shared.add(entry)
            pendingEntry = nil
        } else {
            pendingEntry = entry
        }
        panel.model.phase = .result(action: action.name, icon: action.icon, text: spoken,
                                    replay: true, archived: auto, compact: !action.needsLLM,
                                    contextUsed: contextUsed)
    }

    private func requestPayload(for action: ActionDef, selectedText: String, context: String) -> (prompt: String, text: String, contextUsed: Bool) {
        guard Settings.useFullContext else { return (action.prompt, selectedText, false) }

        let cleanContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanContext.isEmpty, cleanContext != selectedText else { return (action.prompt, selectedText, false) }

        let prompt = action.prompt + "\n\n" + AppFlavor.text(
            "如果用户同时提供「全文上下文」，请只把它当作理解选中内容的上下文；回答仍然围绕「选中内容」执行当前技能，不要改为概括整篇全文，除非当前技能明确要求概括。",
            "If the user provides full-text context, use it only as context for understanding the selected text. Keep the answer focused on the selected text and do not summarize the whole context unless the current action explicitly asks for that."
        )
        let text = AppFlavor.text(
            """
            选中内容：
            \(selectedText)

            全文上下文：
            \(cleanContext)
            """,
            """
            Selected text:
            \(selectedText)

            Full-text context:
            \(cleanContext)
            """
        )
        return (prompt, text, true)
    }

    private func contextText(for selectedText: String) -> String {
        guard Settings.useFullContext else { return "" }
        return SelectionGrabber.axContextText(for: selectedText, source: currentContextSource) ?? ""
    }

    private func contextExcerpt(from context: String, selectedText: String, radius: Int = 200) -> String? {
        let cleanContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanContext.isEmpty, !selected.isEmpty else { return nil }

        let markerStart = AppFlavor.text("【选中内容开始】", "[Selection begins]")
        let markerEnd = AppFlavor.text("【选中内容结束】", "[Selection ends]")
        guard let range = cleanContext.range(of: selected, options: [.caseInsensitive, .diacriticInsensitive])
                ?? compactRange(of: selected, in: cleanContext) else { return nil }

        let start = cleanContext.index(range.lowerBound, offsetBy: -radius, limitedBy: cleanContext.startIndex) ?? cleanContext.startIndex
        let end = cleanContext.index(range.upperBound, offsetBy: radius, limitedBy: cleanContext.endIndex) ?? cleanContext.endIndex
        let before = cleanContext[start..<range.lowerBound]
        let match = cleanContext[range]
        let after = cleanContext[range.upperBound..<end]
        return "\(before)\(markerStart)\(match)\(markerEnd)\(after)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func compactRange(of selected: String, in context: String) -> Range<String.Index>? {
        let selectedCompact = compactForContextMatch(selected)
        guard selectedCompact.count >= 6 else { return nil }

        var compact = ""
        var indexMap: [String.Index] = []
        for index in context.indices {
            let character = context[index]
            guard !String(character).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            compact.append(contentsOf: String(character).lowercased())
            indexMap.append(index)
        }

        guard let compactRange = compact.range(of: selectedCompact) else { return nil }
        let lowerOffset = compact.distance(from: compact.startIndex, to: compactRange.lowerBound)
        let upperOffset = compact.distance(from: compact.startIndex, to: compactRange.upperBound) - 1
        guard indexMap.indices.contains(lowerOffset), indexMap.indices.contains(upperOffset) else { return nil }

        let lower = indexMap[lowerOffset]
        let upper = context.index(after: indexMap[upperOffset])
        return lower..<upper
    }

    private func compactForContextMatch(_ text: String) -> String {
        let scalars = text.lowercased().unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func archiveOriginalCopy() {
        let entry = Entry(action: AppFlavor.text("摘录", "Clip"), icon: "doc.on.doc", sourceApp: currentSource,
                          original: currentText, response: nil)
        ArchiveStore.shared.add(entry)
    }

    private func archivePendingEntry(updatePanel: Bool) {
        guard let entry = pendingEntry else { return }
        ArchiveStore.shared.add(entry)
        pendingEntry = nil
        guard updatePanel, let action = currentAction else { return }
        panel.model.phase = .result(action: action.name, icon: action.icon, text: currentResult,
                                    replay: true, archived: true, compact: !action.needsLLM,
                                    contextUsed: currentContextUsed)
    }

    private static func describe(_ error: Error) -> String {
        if let e = error as? LLMError {
            switch e {
            case .noKey: return AppFlavor.text("未设置 API Key", "API key is missing")
            case .badURL: return AppFlavor.text("AI 接口地址无效", "AI endpoint URL is invalid")
            case .http(let code, let msg): return "HTTP \(code) \(msg.prefix(120))"
            case .badResponse: return AppFlavor.text("响应解析失败", "Could not parse the response")
            }
        }
        return error.localizedDescription
    }

    // MARK: - Windows

    private func showWindow(_ window: inout NSWindow?, size: NSSize, title: String, @ViewBuilder content: () -> some View) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = title
            w.center()
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: content())
            w.setContentSize(size)
            w.contentMinSize = NSSize(width: 360, height: 320)
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openArchive() {
        showWindow(&archiveWindow, size: NSSize(width: 880, height: 580), title: AppFlavor.text("\(AppFlavor.appName) · 档案", "\(AppFlavor.appName) · Archive")) { ArchiveView() }
    }

    @objc private func openSettings() {
        showWindow(&settingsWindow, size: NSSize(width: 470, height: 640), title: AppFlavor.text("\(AppFlavor.appName) · 设置", "\(AppFlavor.appName) · Settings")) { SettingsView() }
    }

    @objc private func openActions() {
        showWindow(&actionsWindow, size: NSSize(width: 520, height: 560), title: AppFlavor.text("\(AppFlavor.appName) · 编辑技能", "\(AppFlavor.appName) · Edit Actions")) { ActionsConfigView() }
    }

    @objc private func openReview() {
        showWindow(&reviewWindow, size: NSSize(width: 520, height: 600), title: AppFlavor.text("\(AppFlavor.appName) · 今日回响", "\(AppFlavor.appName) · Review")) { ReviewView() }
    }

    @objc private func openAbout() {
        showWindow(&aboutWindow, size: NSSize(width: 360, height: 300), title: AppFlavor.text("关于 \(AppFlavor.appName)", "About \(AppFlavor.appName)")) { AboutView() }
    }

    @objc private func openAXPrefs() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor @objc private func checkForUpdates() {
        GitHubReleaseUpdater.shared.checkNow()
    }

    @objc private func openArchiveFolder() {
        NSWorkspace.shared.open(ArchiveStore.shared.revealFolder)
    }

    private func checkTrust() {
        if SelectionGrabber.isTrusted { return }
        let alert = NSAlert()
        alert.messageText = AppFlavor.text("需要「辅助功能」权限", "Accessibility Permission Required")
        alert.informativeText = AppFlavor.text(
            """
            过耳不忘需要「辅助功能」权限，才能读取你在其它应用里选中的文本。

            请在 系统设置 › 隐私与安全性 › 辅助功能 中打开「过耳不忘」，然后重新启动本应用。
            """,
            """
            ListenMark needs Accessibility permission to read selected text in other apps.

            Open System Settings › Privacy & Security › Accessibility, enable ListenMark, then restart the app.
            """
        )
        alert.addButton(withTitle: AppFlavor.text("打开设置", "Open Settings"))
        alert.addButton(withTitle: AppFlavor.text("稍后", "Later"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openAXPrefs()
        }
    }
}
