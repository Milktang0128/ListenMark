import SwiftUI

/// Manage toolbar actions: reorder, enable/disable, edit prompts, and add up to
/// 4 custom actions with their own generation prompts (e.g. 拆解句法 / 记单词).
struct ActionsConfigView: View {
    @ObservedObject private var store = ActionStore.shared
    @State private var editing: EditTarget?

    struct EditTarget: Identifiable {
        let id = UUID()
        var def: ActionDef
        var isNew: Bool
    }

    var body: some View {
        List {
            Section {
                ForEach(store.actions) { def in row(def) }
                    .onMove { store.move(from: $0, to: $1) }
            } header: {
                Text("用 ↑↓ 调序（也可拖动）· 开关启用 · 可改名/改提示词；自定义技能可删除")
            }

            Section {
                Button {
                    editing = EditTarget(
                        def: ActionDef(id: "", name: "新技能", icon: "wand.and.stars",
                                       enabled: true, isBuiltin: false, needsLLM: true,
                                       prompt: "用简洁的简体中文，对下面的文本做……（在这里写你想要的处理方式）"),
                        isNew: true)
                } label: {
                    Label("新增自定义技能（\(store.customCount)/\(ActionStore.maxCustom)）", systemImage: "plus.circle.fill")
                }
                .disabled(!store.canAddCustom)

                Button("恢复默认技能", role: .destructive) { store.resetToDefaults() }
            } footer: {
                Text("自定义技能会调用大模型，按你的提示词生成内容并念出来——比如「拆解这句话的句法结构」「找出生词并解释」。")
            }
        }
        .listStyle(.inset)
        .frame(minWidth: 480, minHeight: 520)
        .sheet(item: $editing) { target in
            ActionEditor(target: target,
                         onSave: { result in
                             if target.isNew {
                                 store.addCustom(name: result.name, icon: result.icon, prompt: result.prompt)
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
            Toggle("", isOn: Binding(get: { def.enabled }, set: { store.setEnabled(def.id, $0) }))
                .labelsHidden().controlSize(.small)
            Image(systemName: def.icon).frame(width: 22).foregroundStyle(.secondary)
            Text(def.name)
            if def.isBuiltin {
                Text("内置").font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("编辑") { editing = EditTarget(def: def, isNew: false) }
                .buttonStyle(.link)
            if !def.isBuiltin {
                Button { store.delete(def.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("删除")
            }
            VStack(spacing: 1) {
                Button { store.moveUp(def.id) } label: { Image(systemName: "chevron.up") }
                    .disabled(def.id == store.actions.first?.id)
                Button { store.moveDown(def.id) } label: { Image(systemName: "chevron.down") }
                    .disabled(def.id == store.actions.last?.id)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .help("调整顺序")
        }
        .padding(.vertical, 3)
    }
}

private struct ActionEditor: View {
    @State var target: ActionsConfigView.EditTarget
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
            Text(target.isNew ? "新增自定义技能" : "编辑技能")
                .font(.headline)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("名称").font(.caption).foregroundStyle(.secondary)
                    TextField("如：拆解句法", text: $target.def.name).frame(width: 160)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("图标").font(.caption).foregroundStyle(.secondary)
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

            if target.def.needsLLM {
                VStack(alignment: .leading, spacing: 4) {
                    Text("生成提示词（告诉模型怎么处理选中的文本）").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $target.def.prompt)
                        .font(.system(size: 12))
                        .frame(height: 130)
                        .padding(6)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
                }
            }

            HStack {
                Spacer()
                Button("取消") { onCancel() }
                Button(target.isNew ? "添加" : "保存") { onSave(finalDef()) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(target.def.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func finalDef() -> ActionDef {
        var d = target.def
        d.name = d.name.trimmingCharacters(in: .whitespaces)
        return d
    }
}
