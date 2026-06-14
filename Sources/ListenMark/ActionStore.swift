import Foundation
import Combine

/// The configurable set of toolbar actions: built-ins + up to 4 custom actions,
/// reorderable, toggleable, with editable prompts. Persisted in UserDefaults.
final class ActionStore: ObservableObject {
    static let shared = ActionStore()
    static let maxCustom = 4

    @Published private(set) var actions: [ActionDef] = []
    private let key = "actionsConfig.v1"

    static let builtins: [ActionDef] = [
        ActionDef(id: "read", name: "朗读", icon: "speaker.wave.2.fill",
                  enabled: true, isBuiltin: true, needsLLM: false, prompt: ""),
        ActionDef(id: "explain", name: "解释", icon: "lightbulb.fill",
                  enabled: true, isBuiltin: true, needsLLM: true,
                  prompt: "用简洁、口语化的简体中文解释下面这段文本的意思，三到五句话，直接给结论，不要客套，不要逐字复述原文。"),
        ActionDef(id: "translate", name: "翻译", icon: "globe",
                  enabled: true, isBuiltin: true, needsLLM: true,
                  prompt: "如果下面的文本是中文，就把它翻译成自然地道的英文；否则翻译成自然流畅的简体中文。只输出译文本身，不要解释或前后缀。"),
        ActionDef(id: "summarize", name: "提炼", icon: "list.bullet.rectangle.fill",
                  enabled: true, isBuiltin: true, needsLLM: true,
                  prompt: "用一句简体中文概括下面文本的核心要点，直接给结论。"),
        ActionDef(id: "background", name: "背景", icon: "sparkles",
                  enabled: true, isBuiltin: true, needsLLM: true,
                  prompt: "为下面这段文本补充必要的背景知识，简体中文，三到四句，便于听懂，不要逐字复述原文。"),
        // Preset plays — shipped but OFF by default; enable in 动作按钮.
        ActionDef(id: "mnemonic", name: "助记", icon: "brain.head.profile",
                  enabled: false, isBuiltin: true, needsLLM: true,
                  prompt: "为下面这段文本设计一个好记的助记法，帮我快速记住它的核心。可以灵活使用谐音、联想、口诀、首字记忆、画面感的比喻等方式。用简体中文：先用一句话点明「要记住什么」，再给出助记法，简洁、生动、适合朗读，不要复述原文。"),
        ActionDef(id: "closeread", name: "精读", icon: "character.book.closed",
                  enabled: false, isBuiltin: true, needsLLM: true,
                  prompt: "下面是一段英文。用简体中文帮我精读，分两部分：① 句式拆解——先点出句子主干（主语+谓语+宾语），再说明各从句、短语和修饰成分是怎么挂接的，让我听懂这句话的结构；② 重点词——挑出 2 到 4 个较难或关键的单词/短语，给出中文释义、读音提示，并说明它在本句里的作用。口语化、条理清楚、适合朗读，不要逐字翻译整句。")
    ]

    init() { load() }

    func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([ActionDef].self, from: data),
           !saved.isEmpty {
            // Append any newly-added built-ins not present in the saved config.
            var result = saved
            let ids = Set(saved.map { $0.id })
            for b in ActionStore.builtins where !ids.contains(b.id) { result.append(b) }
            actions = result
        } else {
            actions = ActionStore.builtins
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(actions) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }

    var enabled: [ActionDef] { actions.filter { $0.enabled } }
    var customCount: Int { actions.filter { !$0.isBuiltin }.count }
    var canAddCustom: Bool { customCount < ActionStore.maxCustom }

    func move(from: IndexSet, to: Int) {
        actions.move(fromOffsets: from, toOffset: to)
        save()
    }

    func moveUp(_ id: String) {
        guard let i = actions.firstIndex(where: { $0.id == id }), i > 0 else { return }
        actions.swapAt(i, i - 1)
        save()
    }

    func moveDown(_ id: String) {
        guard let i = actions.firstIndex(where: { $0.id == id }), i < actions.count - 1 else { return }
        actions.swapAt(i, i + 1)
        save()
    }

    func setEnabled(_ id: String, _ on: Bool) {
        guard let i = actions.firstIndex(where: { $0.id == id }) else { return }
        actions[i].enabled = on
        save()
    }

    func update(_ def: ActionDef) {
        guard let i = actions.firstIndex(where: { $0.id == def.id }) else { return }
        actions[i] = def
        save()
    }

    @discardableResult
    func addCustom(name: String, icon: String, prompt: String) -> Bool {
        guard canAddCustom else { return false }
        actions.append(ActionDef(id: UUID().uuidString, name: name, icon: icon,
                                 enabled: true, isBuiltin: false, needsLLM: true, prompt: prompt))
        save()
        return true
    }

    func delete(_ id: String) {
        actions.removeAll { $0.id == id && !$0.isBuiltin }
        save()
    }

    func resetToDefaults() {
        actions = ActionStore.builtins
        save()
    }
}
