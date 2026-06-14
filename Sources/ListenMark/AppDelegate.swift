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
    private weak var reviewMenuItem: NSMenuItem?

    private var currentText = ""
    private var currentSource = ""
    private var currentResult = ""
    private var currentAction: ActionDef?
    private var pendingEntry: Entry?
    private var lastAutoText = ""
    private var streamTask: Task<Void, Never>?
    private var enabledPIDs = Set<pid_t>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = ArchiveStore.shared
        setupMainMenu()
        setupStatusItem()
        wirePanel()
        HotkeyManager.shared.onFire = { [weak self] in self?.triggerCapture() }
        applyConfig()
        NotificationCenter.default.addObserver(self, selector: #selector(applyConfig),
                                               name: .gebwConfigChanged, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivated(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier { enableAX(pid) }
        checkTrust()
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
            Speaker.shared.speak(self.currentResult.isEmpty ? self.currentText : self.currentResult)
        }
        m.onStop = { [weak self] in
            Speaker.shared.stop()
            self?.streamTask?.cancel()
        }
        m.onArchive = { [weak self] in
            guard let self, let entry = self.pendingEntry else { return }
            ArchiveStore.shared.add(entry)
            self.pendingEntry = nil
            if let a = self.currentAction {
                self.panel.model.phase = .result(action: a.name, icon: a.icon, text: self.currentResult,
                                                 replay: true, archived: true, compact: !a.needsLLM)
            }
        }
        m.onCopyOriginal = { [weak self] in
            guard let self, !self.currentText.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(self.currentText, forType: .string)
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
        appMenu.addItem(withTitle: "隐藏 ListenMark", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 ListenMark", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: Selector(("selectAll:")), keyEquivalent: "a")
        editItem.submenu = editMenu
        NSApp.mainMenu = mainMenu
    }

    // MARK: - Config (hotkey + auto-pop)

    @objc private func applyConfig() {
        HotkeyManager.shared.register(keyCode: UInt32(Settings.hotKeyCode),
                                      carbonModifiers: UInt32(Settings.hotKeyMods))
        triggerMenuItem?.title = "处理选中文本  \(Settings.hotKeyDisplay)"

        if let m = mouseUpMonitor { NSEvent.removeMonitor(m); mouseUpMonitor = nil }
        if Settings.autoPop {
            mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                self?.handleSelectionMouseUp()
            }
        }
    }

    private func handleSelectionMouseUp() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self else { return }
            guard let text = SelectionGrabber.axSelectedText() else { self.lastAutoText = ""; return }
            guard text != self.lastAutoText else { return }
            self.lastAutoText = text
            self.currentSource = NSWorkspace.shared.frontmostApplication?.localizedName ?? "未知来源"
            self.currentText = text
            self.currentResult = ""
            self.pendingEntry = nil
            self.showPanel()
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "ear", accessibilityDescription: "ListenMark")
            btn.image?.isTemplate = true
        }
        let menu = NSMenu()
        let trigger = NSMenuItem(title: "处理选中文本", action: #selector(triggerFromMenu), keyEquivalent: "")
        trigger.target = self
        menu.addItem(trigger)
        triggerMenuItem = trigger
        menu.addItem(.separator())
        let review = NSMenuItem(title: "今日回响…", action: #selector(openReview), keyEquivalent: "")
        review.target = self
        menu.addItem(review)
        reviewMenuItem = review
        add(menu, "打开档案…", #selector(openArchive))
        add(menu, "编辑技能…", #selector(openActions))
        add(menu, "设置…", #selector(openSettings))
        menu.addItem(.separator())
        add(menu, "辅助功能权限设置…", #selector(openAXPrefs))
        add(menu, "打开档案文件夹", #selector(openArchiveFolder))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 ListenMark", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
    }

    // Refresh the 今日回响 due-count badge each time the menu opens (passive nudge).
    func menuNeedsUpdate(_ menu: NSMenu) {
        let n = ArchiveStore.shared.dueCount
        reviewMenuItem?.title = n > 0 ? "今日回响（\(n)）…" : "今日回响…"
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    // MARK: - Trigger

    @objc private func triggerFromMenu() { triggerCapture() }

    private func triggerCapture() {
        currentSource = NSWorkspace.shared.frontmostApplication?.localizedName ?? "未知来源"
        SelectionGrabber.grabAsync { [weak self] text in
            guard let self else { return }
            guard let text, !text.isEmpty else {
                self.currentText = ""
                self.showPanel()
                if SelectionGrabber.isTrusted {
                    self.panel.model.phase = .error("没取到选中文本——先选中文字再触发")
                } else {
                    self.panel.model.phase = .error("需要「辅助功能」权限才能取词（菜单 › 辅助功能权限设置）")
                }
                return
            }
            self.currentText = text
            self.lastAutoText = text
            self.currentResult = ""
            self.pendingEntry = nil
            self.showPanel()
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
        panel.orderOut(nil)
    }

    // MARK: - Run an action

    private func perform(_ action: ActionDef) {
        let text = currentText
        guard !text.isEmpty else { return }
        panel.model.active = action.id

        if action.needsLLM && Settings.deepseekKey.isEmpty {
            panel.model.phase = .error("「\(action.name)」需要 DeepSeek API Key，请到「设置」填写")
            return
        }

        if !action.needsLLM {
            Speaker.shared.speak(text)
            finishResult(action: action, source: currentSource, original: text, response: nil, spoken: text)
            return
        }

        panel.model.phase = .loading(action.name)
        let source = currentSource
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            var full = ""
            do {
                for try await delta in LLMClient.stream(prompt: action.prompt, text: text) {
                    full += delta
                    let snapshot = full
                    guard let self else { return }
                    await MainActor.run {
                        // Text streams to the UI; speech waits for the full block so it
                        // reads as one coherent passage instead of choppy sentences.
                        self.panel.model.phase = .result(action: action.name, icon: action.icon,
                                                         text: snapshot, replay: false, archived: false, compact: false)
                    }
                }
                guard let self else { return }
                let finalText = full
                await MainActor.run {
                    Speaker.shared.speak(finalText)
                    self.finishResult(action: action, source: source, original: text, response: finalText, spoken: finalText)
                }
            } catch is CancellationError {
                guard let self else { return }
                let finalText = full
                await MainActor.run {
                    if finalText.isEmpty {
                        self.panel.model.phase = .idle
                    } else {
                        // User stopped mid-stream: keep the partial text, don't speak.
                        self.finishResult(action: action, source: source, original: text, response: finalText, spoken: finalText)
                    }
                }
            } catch {
                guard let self else { return }
                await MainActor.run {
                    self.panel.model.phase = .error("出错：\(Self.describe(error))")
                }
            }
        }
    }

    private func finishResult(action: ActionDef, source: String, original: String, response: String?, spoken: String) {
        currentResult = spoken
        currentAction = action
        let entry = Entry(action: action.name, icon: action.icon, sourceApp: source, original: original, response: response)
        let auto = Settings.autoArchive
        if auto {
            ArchiveStore.shared.add(entry)
            pendingEntry = nil
        } else {
            pendingEntry = entry
        }
        panel.model.phase = .result(action: action.name, icon: action.icon, text: spoken,
                                    replay: true, archived: auto, compact: !action.needsLLM)
    }

    private static func describe(_ error: Error) -> String {
        if let e = error as? LLMError {
            switch e {
            case .noKey: return "未设置 DeepSeek API Key"
            case .http(let code, let msg): return "HTTP \(code) \(msg.prefix(120))"
            case .badResponse: return "响应解析失败"
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
        showWindow(&archiveWindow, size: NSSize(width: 880, height: 580), title: "ListenMark · 档案") { ArchiveView() }
    }

    @objc private func openSettings() {
        showWindow(&settingsWindow, size: NSSize(width: 470, height: 640), title: "ListenMark · 设置") { SettingsView() }
    }

    @objc private func openActions() {
        showWindow(&actionsWindow, size: NSSize(width: 520, height: 560), title: "ListenMark · 编辑技能") { ActionsConfigView() }
    }

    @objc private func openReview() {
        showWindow(&reviewWindow, size: NSSize(width: 520, height: 600), title: "ListenMark · 今日回响") { ReviewView() }
    }

    @objc private func openAXPrefs() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openArchiveFolder() {
        NSWorkspace.shared.open(ArchiveStore.shared.revealFolder)
    }

    private func checkTrust() {
        if SelectionGrabber.isTrusted { return }
        let alert = NSAlert()
        alert.messageText = "需要「辅助功能」权限"
        alert.informativeText = """
        ListenMark 需要「辅助功能」权限，才能读取你在其它应用里选中的文本。

        请在 系统设置 › 隐私与安全性 › 辅助功能 中打开 ListenMark，然后重新启动本应用。
        """
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openAXPrefs()
        }
    }
}
