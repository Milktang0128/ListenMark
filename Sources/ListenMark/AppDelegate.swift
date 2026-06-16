import AppKit
import SwiftUI
import ApplicationServices
import QuartzCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let panel = ActionPanel()

    private var outsideMonitor: Any?
    private var panelMotionMonitor: Any?
    private var panelDismissWorkItem: DispatchWorkItem?
    private var panelDismissAnchor: NSPoint?
    private var panelShownAt = Date.distantPast
    private var panelIsFadingOut = false
    private let panelAutoDismissDistance: CGFloat = 180
    private let panelAutoDismissInitialGrace: TimeInterval = 0.45
    private let panelAutoDismissDelay: TimeInterval = 0.36
    private var mouseUpMonitor: Any?
    private weak var triggerMenuItem: NSMenuItem?
    private var autoPopMouseDownLocation: NSPoint?
    private var autoPopDidDrag = false
    private var autoPopGeneration = 0
    private var autoPopMouseDownAppBundleID: String?
    private var lastAutoCopyFallbackAt = Date.distantPast

    private var archiveWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var servicesWindow: NSWindow?
    private var actionsWindow: NSWindow?
    private var reviewWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private weak var reviewMenuItem: NSMenuItem?

    private var currentText = ""
    private var currentContext = ""
    private var currentContextSource: SelectionGrabber.ContextSource?
    private var currentSource = ""
    private var currentSourceMetadata: SourceMetadata?
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
        _ = HistoryStore.shared
        _ = ActionStore.shared
        setupMainMenu()
        setupStatusItem()
        wirePanel()
        applyConfig()
        NotificationCenter.default.addObserver(self, selector: #selector(applyConfig),
                                               name: .gebwConfigChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openActions),
                                               name: .gebwOpenActions, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings),
                                               name: .gebwOpenSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openServices),
                                               name: .gebwOpenServices, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openHistory),
                                               name: .gebwOpenHistory, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivated(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        if let app = NSWorkspace.shared.frontmostApplication, !isBuiltInAutoPopProtected(app) {
            enableAX(app.processIdentifier)
        }
        if Settings.onboardingCompletedBuild == 0 {
            openOnboarding()
        } else {
            checkTrust()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            GitHubReleaseUpdater.shared.checkAutomaticallyIfNeeded()
        }
    }

    @objc private func appActivated(_ note: Notification) {
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            guard !isBuiltInAutoPopProtected(app) else { return }
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
        m.onPick = { [weak self] def in
            self?.syncInputTextFromPanel()
            self?.perform(def)
        }
        m.onInputChanged = { [weak self] text in
            self?.currentText = text
        }
        m.onReplay = { [weak self] in
            guard let self else { return }
            Speaker.shared.replay(self.currentResult.isEmpty ? self.currentText : self.currentResult)
        }
        m.onStop = { [weak self] in
            Speaker.shared.stop()
            self?.streamTask?.cancel()
        }
        m.onRetry = { [weak self] in
            self?.retryCurrentAction()
        }
        m.onArchive = { [weak self] in
            self?.archivePendingEntry(updatePanel: true)
        }
        m.onArchiveOriginal = { [weak self] in
            self?.archiveOriginalCopy()
        }
        m.onCopyOriginal = { [weak self] in
            guard let self else { return false }
            self.syncInputTextFromPanel()
            guard !self.currentText.isEmpty else { return false }
            self.copyToPasteboard(self.currentText)
            return true
        }
        m.onCopyResult = { [weak self] text in
            guard let self, !text.isEmpty else { return false }
            self.copyToPasteboard(text)
            return true
        }
        m.onCopyKeyboard = { [weak self] in
            self?.copyCurrentPanelText() ?? false
        }
        m.onCompare = { [weak self] in
            self?.startCompare()
        }
        m.onTogglePin = { [weak self] in
            self?.togglePanelPin()
        }
        m.onAutoSpeakChanged = { enabled in
            if !enabled {
                Speaker.shared.stop()
            }
        }
        m.onDisableForCurrentApp = { [weak self] in self?.disableAutoPopForCurrentApp() }
        m.onDisableGlobally = { [weak self] in self?.disableAutoPopGlobally() }
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
            NSLog("Dob · \(AppFlavor.text("弹出面板快捷键注册失败", "panel hotkey registration failed"))：\(Settings.hotKeyDisplay)")
        }
        if !HotkeyManager.shared.register(id: 2,
                                          keyCode: UInt32(Settings.ocrHotKeyCode),
                                          carbonModifiers: UInt32(Settings.ocrHotKeyMods),
                                          onFire: { [weak self] in
            self?.triggerScreenOCR()
        }) {
            NSLog("Dob · \(AppFlavor.text("屏幕 OCR 快捷键注册失败", "screen OCR hotkey registration failed"))：\(Settings.ocrHotKeyDisplay)")
        }
        if !HotkeyManager.shared.register(id: 3,
                                          keyCode: UInt32(Settings.silentOCRHotKeyCode),
                                          carbonModifiers: UInt32(Settings.silentOCRHotKeyMods),
                                          onFire: { [weak self] in
            self?.triggerSilentScreenOCR()
        }) {
            NSLog("Dob · \(AppFlavor.text("静默 OCR 快捷键注册失败", "silent OCR hotkey registration failed"))：\(Settings.silentOCRHotKeyDisplay)")
        }
        if !HotkeyManager.shared.register(id: 4,
                                          keyCode: UInt32(Settings.inputHotKeyCode),
                                          carbonModifiers: UInt32(Settings.inputHotKeyMods),
                                          onFire: { [weak self] in
            self?.triggerInputPanel()
        }) {
            NSLog("Dob · \(AppFlavor.text("输入面板快捷键注册失败", "input panel hotkey registration failed"))：\(Settings.inputHotKeyDisplay)")
        }
        registerActionHotKeys()
        triggerMenuItem?.title = "\(AppFlavor.text("处理选中文本", "Process Selection"))  \(Settings.hotKeyDisplay)"

        if let m = mouseUpMonitor { NSEvent.removeMonitor(m); mouseUpMonitor = nil }
        if Settings.autoPop {
            mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                self?.handleAutoPopMouseEvent(event)
            }
        }
        if panel.isVisible {
            refreshOutsideMonitor()
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
                NSLog("Dob · \(AppFlavor.text("技能快捷键注册失败", "action hotkey registration failed"))：\(action.name) \(action.hotKeyDisplay ?? "")")
            }
        }
    }

    private func handleAutoPopMouseEvent(_ event: NSEvent) {
        guard !isFrontmostAppAutoPopDisabled() else {
            autoPopMouseDownLocation = nil
            autoPopDidDrag = false
            autoPopMouseDownAppBundleID = nil
            clearAutoSelectionState()
            return
        }
        switch event.type {
        case .leftMouseDown:
            autoPopMouseDownLocation = event.locationInWindow
            autoPopDidDrag = false
            autoPopMouseDownAppBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        case .leftMouseDragged:
            guard let start = autoPopMouseDownLocation else {
                autoPopMouseDownLocation = event.locationInWindow
                autoPopMouseDownAppBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                return
            }
            if distance(from: start, to: event.locationInWindow) > 5 {
                autoPopDidDrag = true
            }
        case .leftMouseUp:
            guard !didAutoPopDragMoveToAnotherApp() else {
                autoPopMouseDownLocation = nil
                autoPopDidDrag = false
                autoPopMouseDownAppBundleID = nil
                clearAutoSelectionState()
                return
            }
            let moved = autoPopMouseDownLocation.map { distance(from: $0, to: event.locationInWindow) > 5 } ?? false
            let allowCopyFallback = autoPopDidDrag || moved || event.clickCount > 1
            autoPopMouseDownLocation = nil
            autoPopDidDrag = false
            autoPopMouseDownAppBundleID = nil
            handleSelectionMouseUp(allowCopyFallback: allowCopyFallback)
        default:
            break
        }
    }

    private func handleSelectionMouseUp(allowCopyFallback: Bool) {
        autoPopGeneration += 1
        let generation = autoPopGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self else { return }
            guard self.autoPopGeneration == generation else { return }
            guard !self.panel.isVisible else { return }
            let contextSource = SelectionGrabber.contextSource()
            if let text = SelectionGrabber.axSelectedText() {
                self.presentAutoSelection(text, contextSource: contextSource)
                return
            }

            guard Settings.autoPopCopyFallback,
                  allowCopyFallback,
                  self.canRunAutoCopyFallback() else {
                self.clearAutoSelectionState()
                return
            }

            self.lastAutoCopyFallbackAt = Date()
            SelectionGrabber.copySelectedTextAsync { [weak self] text in
                guard let self else { return }
                guard self.autoPopGeneration == generation else { return }
                guard !self.panel.isVisible else { return }
                guard let text, !text.isEmpty else {
                    self.clearAutoSelectionState()
                    return
                }
                self.presentAutoSelection(text, contextSource: contextSource)
            }
        }
    }

    private func presentAutoSelection(_ text: String, contextSource: SelectionGrabber.ContextSource) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            clearAutoSelectionState()
            return
        }
        guard clean != lastAutoText else { return }
        cancelActiveAction()
        lastAutoText = clean
        captureCurrentSource(contextSource: contextSource)
        currentText = clean
        currentContext = ""
        currentContextSource = contextSource
        currentContextUsed = false
        currentResult = ""
        pendingEntry = nil
        showPanel()
    }

    private func clearAutoSelectionState() {
        lastAutoText = ""
        currentContext = ""
        currentContextSource = nil
        currentSourceMetadata = nil
        currentContextUsed = false
    }

    private func captureCurrentSource(contextSource: SelectionGrabber.ContextSource?,
                                      fallbackName: String? = nil,
                                      allowBrowserScripting: Bool = false) {
        let metadata = SourceMetadataCollector.current(contextSource: contextSource,
                                                       fallbackName: fallbackName ?? currentSource,
                                                       allowBrowserScripting: allowBrowserScripting)
        currentSourceMetadata = metadata
        currentSource = metadata.appName
    }

    private func setManualSource(_ name: String) {
        currentSource = name
        currentSourceMetadata = SourceMetadata(appName: name)
    }

    private func refreshCurrentSourceForAction() {
        guard currentSource != AppFlavor.text("输入文本", "Input Text") else { return }
        guard currentContextSource != nil else { return }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier != AppFlavor.bundleIdentifier else { return }
        captureCurrentSource(contextSource: currentContextSource,
                             fallbackName: currentSource,
                             allowBrowserScripting: true)
    }

    private func canRunAutoCopyFallback() -> Bool {
        Date().timeIntervalSince(lastAutoCopyFallbackAt) > 0.7
    }

    private func distance(from start: NSPoint, to end: NSPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            if let image = NSImage(named: "DobStatusIcon") {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                btn.image = image
            } else {
                btn.image = NSImage(systemSymbolName: "ear", accessibilityDescription: AppFlavor.appName)
                btn.image?.isTemplate = true
            }
        }
        let menu = NSMenu()
        let trigger = NSMenuItem(title: AppFlavor.text("处理选中文本", "Process Selection"), action: #selector(triggerFromMenu), keyEquivalent: "")
        trigger.target = self
        menu.addItem(trigger)
        triggerMenuItem = trigger
        add(menu, AppFlavor.text("输入文本…", "Input Text…"), #selector(triggerInputFromMenu))
        add(menu, AppFlavor.text("屏幕 OCR…", "Screen OCR…"), #selector(triggerScreenOCRFromMenu))
        add(menu, AppFlavor.text("静默 OCR 复制…", "Silent OCR Copy…"), #selector(triggerSilentScreenOCRFromMenu))
        menu.addItem(.separator())
        let review = NSMenuItem(title: AppFlavor.text("今日回响…", "Review…"), action: #selector(openReview), keyEquivalent: "")
        review.target = self
        menu.addItem(review)
        reviewMenuItem = review
        add(menu, AppFlavor.text("打开档案…", "Open Archive…"), #selector(openArchive))
        add(menu, AppFlavor.text("历史记录…", "History…"), #selector(openHistory))
        add(menu, AppFlavor.text("编辑技能…", "Edit Actions…"), #selector(openActions))
        add(menu, AppFlavor.text("服务管理…", "Services…"), #selector(openServices))
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
    @objc private func triggerInputFromMenu() { triggerInputPanel() }
    @objc private func triggerScreenOCRFromMenu() { triggerScreenOCR() }
    @objc private func triggerSilentScreenOCRFromMenu() { triggerSilentScreenOCR() }

    private func triggerCapture() {
        triggerSelection(actionID: nil)
    }

    private func triggerAction(_ actionID: String) {
        triggerSelection(actionID: actionID)
    }

    private func triggerScreenOCR() {
        triggerScreenOCR(silent: false)
    }

    private func triggerSilentScreenOCR() {
        triggerScreenOCR(silent: true)
    }

    private func triggerScreenOCR(silent: Bool) {
        cancelActiveAction()
        let generation = actionGeneration
        captureCurrentSource(contextSource: SelectionGrabber.contextSource(),
                             fallbackName: AppFlavor.text("屏幕内容", "Screen Content"))
        ScreenOCR.shared.start { [weak self] text in
            guard let self else { return }
            guard self.actionGeneration == generation else { return }
            let clean = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !clean.isEmpty else {
                if silent {
                    return
                }
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

            if silent {
                self.copyToPasteboard(clean)
                self.recordHistory(action: AppFlavor.text("OCR", "OCR"), icon: "text.viewfinder",
                                   source: self.currentSource, original: clean, response: nil)
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
            if Settings.ocrAutoRunLastAction, let action = self.lastUsableAction() {
                self.perform(action, remember: false)
            } else {
                self.recordHistory(action: AppFlavor.text("OCR", "OCR"), icon: "text.viewfinder",
                                   source: self.currentSource, original: clean, response: nil)
                self.panel.model.phase = .captureNotice(source: AppFlavor.text("OCR", "OCR"), text: clean)
            }
        }
    }

    private func triggerInputPanel() {
        cancelActiveAction()
        setManualSource(AppFlavor.text("输入文本", "Input Text"))
        currentText = ""
        currentContext = ""
        currentContextSource = nil
        currentContextUsed = false
        currentResult = ""
        currentAction = nil
        pendingEntry = nil
        panel.model.inputText = ""
        showPanel(minWidth: 500, allowsKeyboardFocus: true)
        panel.model.phase = .input
    }

    private func triggerSelection(actionID: String?) {
        cancelActiveAction()
        let generation = actionGeneration
        let contextSource = SelectionGrabber.contextSource()
        captureCurrentSource(contextSource: contextSource)
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
                    self.panel.model.phase = .error(AppFlavor.text("没取到选中文本——先选中文字再触发", "No selected text found. Select text first, then trigger Dob."))
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

    private func showPanel(minWidth: CGFloat = 320, allowsKeyboardFocus: Bool = false) {
        panelIsFadingOut = false
        panel.showNearMouse(minWidth: minWidth, allowsKeyboardFocus: allowsKeyboardFocus)
        panel.model.canCompare = false
        panel.model.selectedCompareID = nil
        panel.model.disableAppName = currentDisableCandidate()?.appName
        panelShownAt = Date()
        panelDismissAnchor = NSEvent.mouseLocation
        refreshOutsideMonitor()
    }

    private func removeOutsideMonitor() {
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
        if let m = panelMotionMonitor { NSEvent.removeMonitor(m); panelMotionMonitor = nil }
        cancelPanelAutoDismiss()
    }

    private func refreshOutsideMonitor() {
        removeOutsideMonitor()
        guard !panel.model.pinned else { return }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.panel.model.pinned else { return }
            self.closePanel()
        }
        if Settings.autoDismissPanel {
            panelMotionMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
                self?.handlePanelPointerMotion()
            }
        }
    }

    private func togglePanelPin() {
        panel.model.pinned.toggle()
        refreshOutsideMonitor()
    }

    private func closePanel() {
        removeOutsideMonitor()
        cancelActiveAction(stopSpeech: false)
        panelIsFadingOut = false
        panel.model.pinned = false
        panel.releaseKeyboardFocus()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    private func handlePanelPointerMotion() {
        guard Settings.autoDismissPanel,
              panel.isVisible,
              panelCanAutoDismissForCurrentPhase,
              !panel.model.pinned,
              !panelIsFadingOut else { return }

        let point = NSEvent.mouseLocation
        if panelSafeFrame.contains(point) {
            panelDismissAnchor = point
            cancelPanelAutoDismiss()
            return
        }

        if Date().timeIntervalSince(panelShownAt) < panelAutoDismissInitialGrace {
            return
        }

        let anchor = panelDismissAnchor ?? point
        panelDismissAnchor = anchor
        guard distance(from: anchor, to: point) > panelAutoDismissDistance else {
            cancelPanelAutoDismiss()
            return
        }

        schedulePanelAutoDismiss()
    }

    private var panelSafeFrame: NSRect {
        let panelFrame = panel.frame.insetBy(dx: -34, dy: -30)
        let menuFrame = NSRect(x: panel.frame.maxX - 300,
                               y: panel.frame.minY - 520,
                               width: 620,
                               height: 560)
        return panelFrame.union(menuFrame)
    }

    private func schedulePanelAutoDismiss() {
        guard panelDismissWorkItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.panelDismissWorkItem = nil
            guard self.isPanelAutoDismissStillValid else { return }
            guard !self.panelSafeFrame.contains(NSEvent.mouseLocation) else {
                self.panelDismissAnchor = NSEvent.mouseLocation
                return
            }
            self.fadeOutPanel()
        }
        panelDismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + panelAutoDismissDelay, execute: item)
    }

    private var isPanelAutoDismissStillValid: Bool {
        Settings.autoDismissPanel && panel.isVisible && panelCanAutoDismissForCurrentPhase && !panel.model.pinned && !panelIsFadingOut
    }

    private var panelCanAutoDismissForCurrentPhase: Bool {
        switch panel.model.phase {
        case .idle, .captureNotice:
            return true
        case .input, .loading, .error, .compare, .result:
            return false
        }
    }

    private func cancelPanelAutoDismiss() {
        panelDismissWorkItem?.cancel()
        panelDismissWorkItem = nil
    }

    private func fadeOutPanel() {
        guard isPanelAutoDismissStillValid else { return }
        panelIsFadingOut = true
        removeOutsideMonitor()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.cancelActiveAction(stopSpeech: false)
            self.panel.model.pinned = false
            self.panel.releaseKeyboardFocus()
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            self.panelIsFadingOut = false
        }
    }

    private func isFrontmostAppAutoPopDisabled() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != AppFlavor.bundleIdentifier else { return false }
        return isAutoPopDisabled(for: app)
    }

    private func didAutoPopDragMoveToAnotherApp() -> Bool {
        guard let startedBundleID = autoPopMouseDownAppBundleID,
              let currentBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              currentBundleID != AppFlavor.bundleIdentifier else { return false }
        return currentBundleID != startedBundleID
    }

    private func isAutoPopDisabled(for app: NSRunningApplication) -> Bool {
        let bundleID = app.bundleIdentifier
        return Settings.isAutoPopDisabled(bundleID: bundleID) || isBuiltInAutoPopProtected(app)
    }

    private func isBuiltInAutoPopProtected(_ app: NSRunningApplication) -> Bool {
        let bundleID = app.bundleIdentifier?.lowercased() ?? ""
        let name = app.localizedName?.lowercased() ?? ""
        guard bundleID != AppFlavor.bundleIdentifier.lowercased() else { return false }

        if bundleID == "pl.maketheweb.cleanshotx" { return true }

        let protectedFragments = [
            "cleanshot", "screenshot", "screen-shot", "screen_shot",
            "shottr", "snipaste", "xnip", "monosnap", "screenfloat"
        ]
        if protectedFragments.contains(where: { bundleID.contains($0) || name.contains($0) }) {
            return true
        }

        let protectedNames = ["截屏", "截图", "屏幕快照"]
        return protectedNames.contains { name.contains($0) }
    }

    private func currentDisableCandidate() -> (bundleID: String, appName: String)? {
        guard let metadata = currentSourceMetadata,
              let bundleID = metadata.bundleIdentifier,
              !bundleID.isEmpty,
              bundleID != AppFlavor.bundleIdentifier else { return nil }
        return (bundleID, metadata.appName)
    }

    private func disableAutoPopForCurrentApp() {
        guard let candidate = currentDisableCandidate() else { return }
        Settings.disableAutoPop(bundleID: candidate.bundleID, appName: candidate.appName)
        closePanel()
    }

    private func disableAutoPopGlobally() {
        Settings.autoPop = false
        applyConfig()
        closePanel()
    }

    private func cancelActiveAction(stopSpeech: Bool = true) {
        actionGeneration += 1
        streamTask?.cancel()
        streamTask = nil
        if stopSpeech {
            Speaker.shared.stop()
        }
    }

    private func retryCurrentAction() {
        guard let action = currentAction else { return }
        perform(action, remember: false)
    }

    private func copyCurrentPanelText() -> Bool {
        let text: String
        switch panel.model.phase {
        case .compare(_, _, let results, _, _):
            text = formatCompareResults(results)
        case .result:
            text = currentResult.isEmpty ? currentText : currentResult
        case .captureNotice:
            text = currentText
        default:
            text = currentText
        }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        copyToPasteboard(clean)
        return true
    }

    // MARK: - Run an action

    private func perform(_ action: ActionDef, remember: Bool = true) {
        syncInputTextFromPanel()
        refreshCurrentSourceForAction()
        let text = currentText
        guard !text.isEmpty else { return }
        if remember {
            Settings.lastActionID = action.id
        }

        let provider = Settings.llmProvider(for: action)
        if action.needsLLM && provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            panel.model.phase = .error(AppFlavor.text("「\(action.name)」需要 API Key，请到「设置」填写 OpenAI 兼容接口配置", "\(action.name) needs an API key. Add your OpenAI-compatible API settings in Settings."))
            return
        }
        if action.needsLLM &&
            (provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
             provider.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            panel.model.phase = .error(AppFlavor.text("「\(action.name)」的模型服务未配置完整，请到「设置」检查 Base URL 和模型名", "\(action.name)'s model service is incomplete. Check Base URL and model in Settings."))
            return
        }

        cancelActiveAction()
        let generation = actionGeneration
        panel.model.active = action.id
        panel.model.canCompare = false
        panel.model.selectedCompareID = nil

        if !action.needsLLM {
            currentContextUsed = false
            Speaker.shared.speak(text)
            finishResult(action: action, source: currentSource, original: text, response: nil,
                         spoken: text, contextUsed: false, sourceMetadata: currentSourceMetadata)
            return
        }

        panel.model.phase = .loading(action.name)
        let source = currentSource
        let sourceMetadata = currentSourceMetadata
        streamTask = Task { [weak self] in
            guard let self else { return }
            let context = self.contextText(for: text)
            let request = self.requestPayload(for: action, selectedText: text,
                                              context: context, sourceMetadata: sourceMetadata)
            let shouldContinue = await MainActor.run {
                guard self.actionGeneration == generation else { return false }
                self.currentContext = context
                self.currentContextUsed = request.contextUsed
                return true
            }
            guard shouldContinue, !Task.isCancelled else { return }

            var full = ""
            do {
                for try await delta in LLMClient.stream(prompt: request.prompt, text: request.text, provider: provider) {
                    full += delta
                    let snapshot = LLMOutputSanitizer.visibleAnswer(from: full)
                    await MainActor.run {
                        guard self.actionGeneration == generation else { return }
                        // Text streams to the UI; speech waits for the full block so it
                        // reads as one coherent passage instead of choppy sentences.
                        self.panel.model.phase = .result(action: action.name, icon: action.icon,
                                                         text: snapshot, replay: false, archived: false,
                                                         compact: false, contextUsed: request.contextUsed)
                    }
                }
                let finalText = LLMOutputSanitizer.visibleAnswer(from: full)
                await MainActor.run {
                    guard self.actionGeneration == generation else { return }
                    if Settings.autoSpeakAI {
                        Speaker.shared.speak(finalText)
                    }
                    self.finishResult(action: action, source: source, original: text, response: finalText,
                                      spoken: finalText, contextUsed: request.contextUsed,
                                      sourceMetadata: sourceMetadata)
                }
            } catch is CancellationError {
                let finalText = LLMOutputSanitizer.visibleAnswer(from: full)
                await MainActor.run {
                    guard self.actionGeneration == generation else { return }
                    if finalText.isEmpty {
                        self.panel.model.phase = .idle
                    } else {
                        // User stopped mid-stream: keep the partial text, don't speak.
                        self.finishResult(action: action, source: source, original: text, response: finalText,
                                          spoken: finalText, contextUsed: request.contextUsed,
                                          sourceMetadata: sourceMetadata)
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

    private func startCompare() {
        syncInputTextFromPanel()
        refreshCurrentSourceForAction()
        let text = currentText
        guard let action = currentAction, action.needsLLM, !text.isEmpty else { return }
        let baseline = Settings.llmProvider(for: action)
        let providers = Settings.compareProviders(baseline: baseline)
        guard providers.count >= 2 else {
            panel.model.phase = .error(AppFlavor.text("请先在设置里启用至少一个备选比较模型", "Enable at least one alternate comparison model in Settings first."))
            return
        }

        let reusableBaselineText: String
        if case .result = panel.model.phase {
            reusableBaselineText = currentResult.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            reusableBaselineText = ""
        }
        let shouldReuseBaseline = !reusableBaselineText.isEmpty

        cancelActiveAction()
        let generation = actionGeneration
        let source = currentSource
        let sourceMetadata = currentSourceMetadata
        let context = contextText(for: text)
        let request = requestPayload(for: action, selectedText: text,
                                     context: context, sourceMetadata: sourceMetadata)
        currentContext = context
        currentContextUsed = request.contextUsed
        currentAction = action
        panel.model.active = action.id
        panel.model.canCompare = false
        panel.model.selectedCompareID = providers.first?.id

        let initialResults = providers.map { provider in
            if shouldReuseBaseline && provider.id == baseline.id {
                CompareModelResult(id: provider.id, label: provider.label, model: provider.model,
                                   text: reusableBaselineText, isLoading: false, error: nil)
            } else {
                CompareModelResult(id: provider.id, label: provider.label, model: provider.model,
                                   text: "", isLoading: true, error: nil)
            }
        }
        let providersToRun = providers.filter { !(shouldReuseBaseline && $0.id == baseline.id) }
        panel.model.phase = .compare(action: action.name, icon: "rectangle.split.3x1",
                                     results: initialResults, archived: false,
                                     contextUsed: request.contextUsed)

        streamTask = Task { [weak self] in
            guard let self else { return }
            var latest = initialResults
            await withTaskGroup(of: CompareModelResult.self) { group in
                for provider in providersToRun {
                    group.addTask {
                        await Self.runCompareCandidate(provider: provider,
                                                       prompt: request.prompt,
                                                       text: request.text)
                    }
                }

                for await result in group {
                    if Task.isCancelled { group.cancelAll(); break }
                    latest = latest.map { $0.id == result.id ? result : $0 }
                    let snapshot = latest
                    await MainActor.run {
                        guard self.actionGeneration == generation else { return }
                        self.panel.model.phase = .compare(action: action.name,
                                                         icon: "rectangle.split.3x1",
                                                         results: snapshot,
                                                         archived: false,
                                                         contextUsed: request.contextUsed)
                    }
                }
            }

            let finalResults = latest
            await MainActor.run {
                guard self.actionGeneration == generation, !Task.isCancelled else { return }
                self.finishCompareResult(action: action, source: source, original: text,
                                         results: finalResults, contextUsed: request.contextUsed,
                                         sourceMetadata: sourceMetadata)
            }
        }
    }

    private static func runCompareCandidate(provider: LLMProviderConfig, prompt: String, text: String) async -> CompareModelResult {
        let model = provider.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            return CompareModelResult(id: provider.id, label: provider.label, model: provider.model,
                                      text: "", isLoading: false,
                                      error: AppFlavor.text("未设置模型名", "Model is not set"))
        }
        do {
            let response = try await LLMClient.complete(prompt: prompt, text: text, provider: provider)
            return CompareModelResult(id: provider.id, label: provider.label, model: provider.model,
                                      text: response, isLoading: false, error: nil)
        } catch is CancellationError {
            return CompareModelResult(id: provider.id, label: provider.label, model: provider.model,
                                      text: "", isLoading: false,
                                      error: AppFlavor.text("已取消", "Cancelled"))
        } catch {
            return CompareModelResult(id: provider.id, label: provider.label, model: provider.model,
                                      text: "", isLoading: false,
                                      error: describe(error))
        }
    }

    private func finishCompareResult(action: ActionDef, source: String, original: String,
                                     results: [CompareModelResult], contextUsed: Bool,
                                     sourceMetadata: SourceMetadata?) {
        let combined = formatCompareResults(results)
        let comparison = comparisonRecord(from: results)
        currentResult = combined
        currentAction = action
        currentContextUsed = contextUsed
        panel.model.canCompare = action.needsLLM

        let entry = Entry(action: AppFlavor.text("比较 · \(action.name)", "Compare · \(action.name)"),
                          icon: "rectangle.split.3x1",
                          sourceApp: source,
                          sourceMetadata: sourceMetadata,
                          original: original,
                          response: combined,
                          responseModel: comparison.selectedID,
                          comparison: comparison,
                          contextUsed: contextUsed,
                          contextExcerpt: contextUsed ? contextExcerpt(from: currentContext, selectedText: original) : nil)
        recordHistory(action: entry.action, icon: entry.icon, source: source,
                      original: original, response: combined, comparison: comparison)

        let auto = Settings.autoArchive
        if auto {
            ArchiveStore.shared.add(entry)
            pendingEntry = nil
        } else {
            pendingEntry = entry
        }
        panel.model.phase = .compare(action: action.name, icon: "rectangle.split.3x1",
                                     results: results, archived: auto,
                                     contextUsed: contextUsed)
    }

    private func finishResult(action: ActionDef, source: String, original: String, response: String?,
                              spoken: String, contextUsed: Bool, sourceMetadata: SourceMetadata?) {
        currentResult = spoken
        currentAction = action
        currentContextUsed = contextUsed
        panel.model.canCompare = action.needsLLM
        let entry = Entry(action: action.name, icon: action.icon, sourceApp: source,
                          sourceMetadata: sourceMetadata,
                          original: original, response: response, contextUsed: contextUsed,
                          contextExcerpt: contextUsed ? contextExcerpt(from: currentContext, selectedText: original) : nil)
        recordHistory(action: action.name, icon: action.icon, source: source,
                      original: original, response: response)
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

    private func requestPayload(for action: ActionDef, selectedText: String,
                                context: String,
                                sourceMetadata: SourceMetadata?) -> (prompt: String, text: String, contextUsed: Bool) {
        guard Settings.useFullContext else { return (action.prompt, selectedText, false) }

        let cleanContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceBlock = sourceMetadata?.modelContextBlock
        let hasFullTextContext = !cleanContext.isEmpty && cleanContext != selectedText
        let hasReadableSourceContext = sourceMetadata?.hasReadableContext == true
        guard hasFullTextContext || sourceBlock != nil else { return (action.prompt, selectedText, false) }

        let prompt = action.prompt + "\n\n" + AppFlavor.text(
            "如果用户同时提供「来源信息」或「全文上下文」，请只把它们当作理解选中内容的参考；回答仍然围绕「选中内容」执行当前技能，不要改为概括整篇全文，除非当前技能明确要求概括。",
            "If the user provides source metadata or full-text context, use them only as reference for understanding the selected text. Keep the answer focused on the selected text and do not summarize the whole context unless the current action explicitly asks for that."
        )
        var zhBlocks = ["选中内容：\n\(selectedText)"]
        var enBlocks = ["Selected text:\n\(selectedText)"]
        if let sourceBlock {
            zhBlocks.append("来源信息：\n\(sourceBlock)")
            enBlocks.append("Source metadata:\n\(sourceBlock)")
        }
        if hasFullTextContext {
            zhBlocks.append("全文上下文：\n\(cleanContext)")
            enBlocks.append("Full-text context:\n\(cleanContext)")
        }
        let text = AppFlavor.text(
            zhBlocks.joined(separator: "\n\n"),
            enBlocks.joined(separator: "\n\n")
        )
        return (prompt, text, hasFullTextContext || hasReadableSourceContext)
    }

    private func contextText(for selectedText: String) -> String {
        guard Settings.useFullContext else { return "" }
        return SelectionGrabber.axContextText(for: selectedText, source: currentContextSource) ?? ""
    }

    private func contextExcerpt(from context: String, selectedText: String, radius: Int = 200) -> String? {
        let cleanContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanContext.isEmpty, !selected.isEmpty else { return nil }

        guard let range = cleanContext.range(of: selected, options: [.caseInsensitive, .diacriticInsensitive])
                ?? compactRange(of: selected, in: cleanContext) else { return nil }

        let start = cleanContext.index(range.lowerBound, offsetBy: -radius, limitedBy: cleanContext.startIndex) ?? cleanContext.startIndex
        let end = cleanContext.index(range.upperBound, offsetBy: radius, limitedBy: cleanContext.endIndex) ?? cleanContext.endIndex
        let before = cleanContext[start..<range.lowerBound]
        let match = cleanContext[range]
        let after = cleanContext[range.upperBound..<end]
        return "\(before)==\(match)==\(after)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func recordHistory(action: String, icon: String?, source: String, original: String,
                               response: String?, comparison: ComparisonRecord? = nil) {
        let cleanOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanResponse = response.map { LLMOutputSanitizer.visibleAnswer(from: $0) }
        guard !cleanOriginal.isEmpty || !(cleanResponse?.isEmpty ?? true) else { return }
        HistoryStore.shared.add(HistoryEntry(action: action, icon: icon, sourceApp: source,
                                             original: cleanOriginal,
                                             response: cleanResponse?.isEmpty == true ? nil : cleanResponse,
                                             comparison: comparison))
    }

    private func formatCompareResults(_ results: [CompareModelResult]) -> String {
        results.map { result in
            let statusText: String
            if let error = result.error {
                statusText = AppFlavor.text("出错：\(error)", "Error: \(error)")
            } else if result.isLoading {
                statusText = AppFlavor.text("等待结果…", "Waiting for result...")
            } else {
                statusText = result.text
            }
            return "\(result.label) · \(result.model)\n\(statusText)"
        }
        .joined(separator: "\n\n---\n\n")
    }

    private func comparisonRecord(from results: [CompareModelResult]) -> ComparisonRecord {
        let selectedID = panel.model.selectedCompareID ?? results.first?.id ?? "default"
        return ComparisonRecord(
            primaryID: results.first?.id ?? "default",
            selectedID: selectedID,
            results: results.map {
                ModelRunResult(id: $0.id,
                               label: $0.label,
                               model: $0.model,
                               status: $0.error == nil ? ($0.isLoading ? "loading" : "succeeded") : "failed",
                               response: $0.text.isEmpty ? nil : LLMOutputSanitizer.visibleAnswer(from: $0.text),
                               error: $0.error)
            }
        )
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

    private func syncInputTextFromPanel() {
        if panel.model.phase == .input {
            currentText = panel.model.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func lastUsableAction() -> ActionDef? {
        let id = Settings.lastActionID
        guard !id.isEmpty else { return nil }
        return ActionStore.shared.actions.first { $0.id == id && $0.enabled }
    }

    private func archiveOriginalCopy() {
        refreshCurrentSourceForAction()
        let entry = Entry(action: AppFlavor.text("摘录", "Clip"), icon: "doc.on.doc", sourceApp: currentSource,
                          sourceMetadata: currentSourceMetadata,
                          original: currentText, response: nil)
        ArchiveStore.shared.add(entry)
    }

    private func archivePendingEntry(updatePanel: Bool) {
        guard let entry = pendingEntry else { return }
        ArchiveStore.shared.add(entry)
        pendingEntry = nil
        guard updatePanel else { return }
        switch panel.model.phase {
        case .compare(let action, let icon, let results, _, let contextUsed):
            panel.model.phase = .compare(action: action, icon: icon, results: results,
                                         archived: true, contextUsed: contextUsed)
        default:
            guard let action = currentAction else { return }
            panel.model.phase = .result(action: action.name, icon: action.icon, text: currentResult,
                                        replay: true, archived: true, compact: !action.needsLLM,
                                        contextUsed: currentContextUsed)
        }
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

    @objc private func openHistory() {
        showWindow(&historyWindow, size: NSSize(width: 760, height: 560), title: AppFlavor.text("\(AppFlavor.appName) · 历史记录", "\(AppFlavor.appName) · History")) { HistoryView() }
    }

    @objc private func openSettings() {
        openSettingsPage(.preferences)
    }

    @objc private func openServices() {
        openSettingsPage(.services)
    }

    @objc private func openActions() {
        openSettingsPage(.actions)
    }

    private func openSettingsPage(_ page: SettingsPage) {
        let size = NSSize(width: 1100, height: 720)
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = AppFlavor.text("\(AppFlavor.appName) · 设置", "\(AppFlavor.appName) · Settings")
            w.center()
            w.isReleasedWhenClosed = false
            w.contentMinSize = NSSize(width: 980, height: 680)
            settingsWindow = w
        }
        settingsWindow?.contentViewController = NSHostingController(rootView: SettingsView(initialPage: page))
        settingsWindow?.setContentSize(size)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openReview() {
        showWindow(&reviewWindow, size: NSSize(width: 520, height: 600), title: AppFlavor.text("\(AppFlavor.appName) · 今日回响", "\(AppFlavor.appName) · Review")) { ReviewView() }
    }

    @objc private func openAbout() {
        showWindow(&aboutWindow, size: NSSize(width: 360, height: 300), title: AppFlavor.text("关于 \(AppFlavor.appName)", "About \(AppFlavor.appName)")) { AboutView() }
    }

    @objc private func openOnboarding() {
        let model = OnboardingModel(
            onOpenAX: { [weak self] in self?.openAXPrefs() },
            onOpenServices: { [weak self] in self?.openServices() },
            onTrustGranted: { [weak self] in
                guard let self else { return }
                self.applyConfig()   // re-arm capture once Accessibility is granted — no restart
                if let app = NSWorkspace.shared.frontmostApplication { self.enableAX(app.processIdentifier) }
            },
            onFinish: { [weak self] in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
            }
        )
        showWindow(&onboardingWindow, size: NSSize(width: 520, height: 560),
                   title: AppFlavor.text("欢迎使用 \(AppFlavor.appName)", "Welcome to \(AppFlavor.appName)")) {
            OnboardingView(model: model)
        }
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
            Dob 需要「辅助功能」权限，才能读取你在其它应用里选中的文本。

            请在 系统设置 › 隐私与安全性 › 辅助功能 中打开「Dob」，然后重新启动本应用。
            """,
            """
            Dob needs Accessibility permission to read selected text in other apps.

            Open System Settings › Privacy & Security › Accessibility, enable Dob, then restart the app.
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
