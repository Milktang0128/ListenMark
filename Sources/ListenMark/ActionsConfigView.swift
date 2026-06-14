import SwiftUI
import UniformTypeIdentifiers

/// Manage toolbar actions: reorder, enable/disable, edit prompts, and add up to
/// 4 custom actions with their own generation prompts (e.g. 拆解句法 / 记单词).
struct ActionsConfigView: View {
    @ObservedObject private var store = ActionStore.shared
    @State private var editing: EditTarget?
    @State private var draggingID: String?

    struct EditTarget: Identifiable {
        let id = UUID()
        var def: ActionDef
        var isNew: Bool
    }

    var body: some View {
        List {
            Section {
                ForEach(store.actions) { def in
                    row(def)
                        .onDrop(of: [.text],
                                delegate: ActionDropDelegate(targetID: def.id,
                                                             draggingID: $draggingID,
                                                             store: store))
                }
            } header: {
                Text(AppFlavor.text("朗读固定第一；拖动左侧把手调整其它技能；浮窗显示前 5 个启用技能，其余收在更多菜单", "Read stays first. Drag the handle to reorder other actions. The panel shows the first 5 enabled actions; the rest live in More."))
            }

            Section {
                Button {
                    editing = EditTarget(
                        def: ActionDef(id: "", name: AppFlavor.text("新技能", "New Action"), icon: "wand.and.stars",
                                       enabled: true, isBuiltin: false, needsLLM: true,
                                       prompt: AppFlavor.text("用简洁的简体中文，对下面的文本做……（在这里写你想要的处理方式）", "In concise natural English, process the selected text as follows...")),
                        isNew: true)
                } label: {
                    Label(AppFlavor.text("新增自定义技能（\(store.customCount)/\(ActionStore.maxCustom)）", "Add Custom Action (\(store.customCount)/\(ActionStore.maxCustom))"), systemImage: "plus.circle.fill")
                }
                .disabled(!store.canAddCustom)

                Button(AppFlavor.text("恢复默认技能", "Restore Default Actions"), role: .destructive) { store.resetToDefaults() }
            } footer: {
                Text(AppFlavor.text("技能快捷键会直接处理当前选中文本。自定义技能会调用大模型，按你的提示词生成内容并念出来。", "Action hotkeys process the current selection directly. Custom actions call the model with your prompt and read the result aloud."))
            }
        }
        .listStyle(.inset)
        .frame(minWidth: 480, minHeight: 520)
        .sheet(item: $editing) { target in
            ActionEditor(target: target,
                         onSave: { result in
                             if target.isNew {
                                 store.addCustom(result)
                             } else {
                                 store.update(result)
                             }
                             editing = nil
                         },
                         onCancel: { editing = nil })
        }
    }

    private func row(_ def: ActionDef) -> some View {
        HStack(spacing: 10) {
            dragHandle(def)
            Toggle("", isOn: Binding(get: { def.enabled }, set: { store.setEnabled(def.id, $0) }))
                .labelsHidden().controlSize(.small)
            Image(systemName: def.icon).frame(width: 22).foregroundStyle(.secondary)
            Text(def.name)
            if def.isBuiltin {
                Text(AppFlavor.text("内置", "Built-in")).font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            HotkeyRecorder(display: Binding(get: { def.hotKeyDisplay ?? AppFlavor.text("未设置", "Not Set") }, set: { _ in })) { code, mods, disp in
                store.setHotKey(def.id, code: Int(code), mods: carbonModifiers(mods), display: disp)
            }
            .frame(width: 122, height: 22)
            .help(AppFlavor.text("设置此技能的全局快捷键", "Set global hotkey for this action"))
            if def.hotKeyDisplay != nil {
                Button {
                    store.setHotKey(def.id, code: nil, mods: nil, display: nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help(AppFlavor.text("清除快捷键", "Clear hotkey"))
            }
            Button(AppFlavor.text("编辑", "Edit")) { editing = EditTarget(def: def, isNew: false) }
                .buttonStyle(.link)
            if !def.isBuiltin {
                Button { store.delete(def.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help(AppFlavor.text("删除", "Delete"))
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder private func dragHandle(_ def: ActionDef) -> some View {
        if def.id == "read" {
            Image(systemName: "pin.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 18)
                .help(AppFlavor.text("朗读固定第一，不参与排序", "Read stays first and cannot be reordered"))
        } else {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .help(AppFlavor.text("拖动排序", "Drag to reorder"))
                .onDrag {
                    draggingID = def.id
                    return NSItemProvider(object: def.id as NSString)
                }
        }
    }
}

private struct ActionDropDelegate: DropDelegate {
    let targetID: String
    @Binding var draggingID: String?
    let store: ActionStore

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != targetID else { return }
        store.move(draggingID, before: targetID)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct ActionEditor: View {
    @State var target: ActionsConfigView.EditTarget
    @State private var optimizingPrompt = false
    @State private var optimizeError: String?
    var onSave: (ActionDef) -> Void
    var onCancel: () -> Void

    private let icons = [
        "speaker.wave.2.fill", "lightbulb.fill", "globe", "list.bullet.rectangle.fill", "sparkles",
        "text.bubble", "character.book.closed", "book", "quote.bubble", "textformat",
        "brain.head.profile", "graduationcap.fill", "wand.and.stars", "questionmark.circle", "highlighter",
        "scroll", "character.cursor.ibeam", "bubble.left.and.text.bubble.right"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(target.isNew ? AppFlavor.text("新增自定义技能", "Add Custom Action") : AppFlavor.text("编辑技能", "Edit Action"))
                .font(.headline)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppFlavor.text("名称", "Name")).font(.caption).foregroundStyle(.secondary)
                    TextField(AppFlavor.text("如：拆解句法", "e.g. Sentence Structure"), text: $target.def.name).frame(width: 160)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppFlavor.text("图标", "Icon")).font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $target.def.icon) {
                        ForEach(icons, id: \.self) { ic in
                            Image(systemName: ic).tag(ic)
                        }
                    }
                    .labelsHidden().frame(width: 80)
                }
                Spacer()
                Image(systemName: target.def.icon).font(.system(size: 22)).foregroundStyle(Color.accentColor)
            }

            HStack(spacing: 10) {
                Text(AppFlavor.text("快捷键", "Hotkey")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                HotkeyRecorder(display: Binding(get: { target.def.hotKeyDisplay ?? AppFlavor.text("未设置", "Not Set") },
                                                set: { target.def.hotKeyDisplay = $0 })) { code, mods, disp in
                    target.def.hotKeyCode = Int(code)
                    target.def.hotKeyMods = carbonModifiers(mods)
                    target.def.hotKeyDisplay = disp
                }
                .frame(width: 146, height: 24)
                if target.def.hotKeyDisplay != nil {
                    Button(AppFlavor.text("清除", "Clear")) {
                        target.def.hotKeyCode = nil
                        target.def.hotKeyMods = nil
                        target.def.hotKeyDisplay = nil
                    }
                }
            }

            if target.def.needsLLM {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(AppFlavor.text("生成提示词（告诉模型怎么处理选中的文本）", "Generation prompt (tell the model how to process the selected text)"))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            Task { await optimizePrompt() }
                        } label: {
                            if optimizingPrompt {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(AppFlavor.text("AI 优化", "AI Optimize"), systemImage: "wand.and.stars")
                            }
                        }
                        .controlSize(.small)
                        .disabled(optimizingPrompt || target.def.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help(AppFlavor.text("用当前 AI 模型优化这个技能提示词", "Optimize this action prompt with the current AI model"))
                    }
                    TextEditor(text: $target.def.prompt)
                        .font(.system(size: 12))
                        .frame(height: 130)
                        .padding(6)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
                }
            }

            HStack {
                Spacer()
                Button(AppFlavor.text("取消", "Cancel")) { onCancel() }
                Button(target.isNew ? AppFlavor.text("添加", "Add") : AppFlavor.text("保存", "Save")) { onSave(finalDef()) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(target.def.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .alert(AppFlavor.text("AI 优化失败", "AI Optimization Failed"), isPresented: Binding(get: { optimizeError != nil },
                                              set: { if !$0 { optimizeError = nil } })) {
            Button(AppFlavor.text("好", "OK")) { optimizeError = nil }
        } message: {
            Text(optimizeError ?? "")
        }
    }

    private func finalDef() -> ActionDef {
        var d = target.def
        d.name = d.name.trimmingCharacters(in: .whitespaces)
        return d
    }

    @MainActor
    private func optimizePrompt() async {
        let name = target.def.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = target.def.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return }
        guard !Settings.llmAPIKey.isEmpty else {
            optimizeError = AppFlavor.text("请先在设置里填写 AI 接口 API Key。", "Add your AI API key in Settings first.")
            return
        }

        optimizingPrompt = true
        defer { optimizingPrompt = false }

        do {
            let optimized = try await LLMClient.complete(prompt: Self.promptOptimizerSystemPrompt,
                                                        text: """
                                                        \(AppFlavor.text("技能名称", "Action name"))：\(name.isEmpty ? AppFlavor.text("未命名技能", "Unnamed action") : name)

                                                        \(AppFlavor.text("当前提示词", "Current prompt"))：
                                                        \(current)
                                                        """)
            let cleaned = cleanOptimizedPrompt(optimized)
            guard !cleaned.isEmpty else {
                optimizeError = AppFlavor.text("模型没有返回可用的提示词。", "The model did not return a usable prompt.")
                return
            }
            target.def.prompt = cleaned
        } catch {
            optimizeError = Self.describe(error)
        }
    }

    private func cleanOptimizedPrompt(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var promptOptimizerSystemPrompt: String {
        AppFlavor.text(
            """
            你是「过耳不忘」的技能提示词优化器。你的任务是把用户现有的技能提示词改写得更清晰、稳定、适合处理被选中的文本。

            优化原则：
            保留原意，不新增用户没有要求的任务。
            明确模型应该如何处理「选中内容」。
            如果任务可能使用全文上下文，要说明全文上下文只作为理解选中内容的参考，除非任务本身要求概括全文。
            输出应适合后续语音朗读：要求模型返回自然口语化纯文本，不要 Markdown、表格、列表符号或多余客套。
            提示词要简洁但足够明确，通常一段话即可。

            只输出优化后的提示词本身，不要解释，不要加标题。
            """,
            """
            You are the ListenMark action prompt optimizer. Rewrite the user's existing prompt so it is clearer, more reliable, and well suited for processing selected text.

            Principles:
            Preserve the user's original intent and do not add new tasks.
            Make it explicit how the model should handle the selected text.
            If full-text context may be provided, say it is only reference material for understanding the selection unless the action explicitly asks for full-document summarization.
            The model's answer will be spoken aloud, so require natural plain text with no Markdown, tables, bullet symbols, or unnecessary pleasantries.
            Keep the prompt concise but specific, usually one paragraph.

            Output only the optimized prompt itself. Do not explain and do not add a title.
            """
        )
    }

    private static func describe(_ error: Error) -> String {
        if let e = error as? LLMError {
            switch e {
            case .noKey: return AppFlavor.text("请先在设置里填写 AI 接口 API Key。", "Add your AI API key in Settings first.")
            case .badURL: return AppFlavor.text("AI 接口地址无效。", "The AI endpoint URL is invalid.")
            case .http(let code, let msg): return AppFlavor.text("AI 请求失败：HTTP \(code) \(msg.prefix(120))", "AI request failed: HTTP \(code) \(msg.prefix(120))")
            case .badResponse: return AppFlavor.text("AI 响应解析失败。", "Could not parse the AI response.")
            }
        }
        return error.localizedDescription
    }
}
