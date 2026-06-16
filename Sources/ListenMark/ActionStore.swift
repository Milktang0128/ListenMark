import Foundation
import Combine
import Carbon.HIToolbox

/// The configurable set of toolbar actions: built-ins + up to 4 custom actions,
/// reorderable, toggleable, with editable prompts. Persisted in UserDefaults.
final class ActionStore: ObservableObject {
    static let shared = ActionStore()
    static let maxCustom = 4

    @Published private(set) var actions: [ActionDef] = []
    private let key = "actionsConfig.v2"
    private let legacyKey = "actionsConfig.v1"
    private let defaultHotkeysKey = "actionsConfig.defaultHotkeys.v3"
    private let defaultPromptsKey = "actionsConfig.defaultPrompts.v5"
    private let backgroundDefaultOffKey = "actionsConfig.backgroundDefaultOff.v1"

    private static var optimizedPrompts: [String: String] {
        if AppFlavor.uiLanguageIsEnglish {
            return [
                "explain": "Explain the selected text in clear, natural English. Start with one sentence that states the core meaning, then add the key terms, implied background, or sentence relationships needed to understand it. Keep it concise, three to five spoken sentences, and do not simply paraphrase the original.",
                "translate": "Translate the selected text into natural English. If it is already English, rewrite it in clearer natural English while preserving meaning, tone, names, product names, and technical terms. Use any provided full-text context only to resolve references and terminology. Output only the translation or rewrite, with no explanation or prefix.",
                "summarize": "Summarize the selected text in English. Give one clear takeaway first, then one or two short sentences with the most important reason, condition, or implication. Keep it under three spoken sentences and avoid listing minor details.",
                "background": "Give the concise background needed to understand the selected text: what it refers to, why it matters, and any relevant concept, person, event, or situation. Keep it three to five natural spoken sentences, focused on the selection rather than an encyclopedia-style overview.",
                "insight": "Use the selected text and any available context to surface a deeper insight: hidden values, worldview, tension, or philosophical implication. Give one sharp insight first, then explain the textual basis in two or three concise sentences. Avoid motivational clichés and stay grounded in the text.",
                "blindspot": "Focus on the selected text and use context only when needed. Identify two to three important blind spots it may be missing. For each, explain why it matters and give one actionable follow-up question or check. Be constructive, not contrarian for its own sake.",
                "proofread": "Treat the selected text as a draft and directly output the proofread revision. Fix typos, awkward phrasing, clarity, flow, redundancy, tone, overly absolute or sensitive wording, and factual caution while preserving the author's intent, structure, and voice. Do not rewrite it into a different piece. Output only the revised text; add at most one brief final note only if a factual risk cannot be verified.",
                "mnemonic": "Create a memorable mnemonic for the selected text. First state what needs to be remembered, then give one vivid association, phrase, sound cue, image, or acronym, and briefly explain how it helps recall the original idea. Use natural English, three to five spoken sentences.",
                "closeread": "Do a close reading of the selected sentence or passage in English. Start with the main structure and overall meaning, then explain how clauses, phrases, or modifiers connect, and finally call out two to four key words or phrases and their role. Keep it spoken and concise; do not produce a word-by-word translation."
            ]
        }
        return [
            "explain": "用简体中文解释选中内容。先用一句话说清它的核心意思，再补充关键术语、隐含背景或句子关系，让人听完能真正理解。三到五句，口语化，直接给结论，不要逐字复述原文。",
            "translate": "根据选中内容的语言自动翻译：中文译成自然地道的英文，其他语言译成自然流畅的简体中文。结合上下文判断语气、指代和专业术语，保留必要的人名、产品名和专有名词。只输出译文，不要解释、注释或前后缀。",
            "summarize": "用简体中文提炼选中内容的核心要点。先给一句明确结论，再用一到两句补充关键原因、条件或影响。总共不超过三句，适合快速听懂，不要罗列细节或复述原文。",
            "background": "围绕选中内容补充必要背景知识，说明它是什么、为什么重要，以及需要知道的相关概念、人物、事件或场景。三到五句，简洁口语化，帮助用户听懂当前文本，不要展开成百科介绍，也不要逐字复述原文。",
            "insight": "结合选中内容和可用上下文，发掘它更深层的意涵：隐含价值、世界观、张力或哲学问题。先用一句话给出洞见，再用两到三句说明文本依据。不要泛泛鸡汤，不要脱离文本。",
            "blindspot": "聚焦选中内容，必要时参考全文上下文。指出它最可能忽略的二到三个重要盲点；每点说明为什么重要，并给一个可执行的补问或检查动作。保持建设性，不要为了挑错而挑错。",
            "proofread": "把选中内容当作正在写的草稿，基于可用上下文直接输出审校后的修订版本。重点处理错别字、病句、冗余、逻辑衔接、语气分寸、敏感或绝对化表述和事实谨慎；保留作者原意、结构和风格，不要改写成另一篇。只输出修订后的正文；除非存在无法确认的事实风险，才在末尾用一句话简短标注。",
            "mnemonic": "为选中内容设计一个容易记住的助记法。先用一句话点明要记住的核心，再给出一个生动的联想、口诀、谐音、画面或首字记忆法，最后简单说明怎么用它回忆原意。简体中文，三到五句，适合朗读。",
            "closeread": "下面通常是一段英文。用简体中文做精读：先点出句子主干和整体意思，再说明从句、短语或修饰成分如何连接，最后挑出二到四个关键词或短语解释含义和在句中的作用。口语化、条理清楚、适合朗读，不要逐字翻译整句。"
        ]
    }

    private static let previousDefaultPrompts: [String: Set<String>] = [
        "explain": ["用简洁、口语化的简体中文解释下面这段文本的意思，三到五句话，直接给结论，不要客套，不要逐字复述原文。"],
        "translate": ["如果下面的文本是中文，就把它翻译成自然地道的英文；否则翻译成自然流畅的简体中文。只输出译文本身，不要解释或前后缀。"],
        "summarize": ["用一句简体中文概括下面文本的核心要点，直接给结论。"],
        "background": [
            "为下面这段文本补充必要的背景知识，简体中文，三到四句，便于听懂，不要逐字复述原文。",
            "为下面的选中内容补充必要的背景知识，简体中文，三到四句，便于听懂，不要逐字复述原文。如果同时提供全文上下文，只把它当作理解选中内容的依据，不要概括整篇全文。"
        ],
        "proofread": [
            "把选中内容当作正在写的草稿，基于可用上下文做发布前审校：清晰度、逻辑跳跃、语气、冗余、错别字、不顺句、敏感或绝对化表述、事实谨慎。只列关键问题和最小修改建议；需要时给一版保留作者风格的修改稿。",
            "Treat the selected text as a draft and use any available context to judge intent. Check clarity, logic gaps, tone, wordiness, awkward phrasing, typos, sensitive or absolute claims, and factual caution. List only key issues and minimal edit suggestions; when useful, provide a revised version that preserves the author's voice."
        ],
        "mnemonic": ["为下面这段文本设计一个好记的助记法，帮我快速记住它的核心。可以灵活使用谐音、联想、口诀、首字记忆、画面感的比喻等方式。用简体中文：先用一句话点明「要记住什么」，再给出助记法，简洁、生动、适合朗读，不要复述原文。"],
        "closeread": ["下面是一段英文。用简体中文帮我精读，分两部分：① 句式拆解——先点出句子主干（主语+谓语+宾语），再说明各从句、短语和修饰成分是怎么挂接的，让我听懂这句话的结构；② 重点词——挑出 2 到 4 个较难或关键的单词/短语，给出中文释义、读音提示，并说明它在本句里的作用。口语化、条理清楚、适合朗读，不要逐字翻译整句。"]
    ]

    static var builtins: [ActionDef] {
        [
        ActionDef(id: "read", name: AppFlavor.text("朗读", "Read"), icon: "speaker.wave.2.fill",
                  enabled: true, isBuiltin: true, needsLLM: false, prompt: "",
                  hotKeyCode: 15, hotKeyMods: controlKey | shiftKey, hotKeyDisplay: "⌃⇧R"),
        ActionDef(id: "explain", name: AppFlavor.text("解释", "Explain"), icon: "lightbulb.fill",
                  enabled: true, isBuiltin: true, needsLLM: true,
                  prompt: optimizedPrompts["explain"]!,
                  hotKeyCode: kVK_ANSI_E, hotKeyMods: controlKey | shiftKey, hotKeyDisplay: "⌃⇧E"),
        ActionDef(id: "translate", name: AppFlavor.text("翻译", "Translate"), icon: "globe",
                  enabled: true, isBuiltin: true, needsLLM: true,
                  prompt: optimizedPrompts["translate"]!,
                  hotKeyCode: kVK_ANSI_T, hotKeyMods: controlKey | shiftKey, hotKeyDisplay: "⌃⇧T"),
        ActionDef(id: "summarize", name: AppFlavor.text("提炼", "Summarize"), icon: "list.bullet.rectangle.fill",
                  enabled: true, isBuiltin: true, needsLLM: true,
                  prompt: optimizedPrompts["summarize"]!),
        ActionDef(id: "background", name: AppFlavor.text("背景", "Context"), icon: "sparkles",
                  enabled: false, isBuiltin: true, needsLLM: true,
                  prompt: optimizedPrompts["background"]!),
        // Preset plays — shipped but OFF by default; enable in 动作按钮.
        ActionDef(id: "insight", name: AppFlavor.text("洞见", "Insight"), icon: "eye.fill",
                  enabled: false, isBuiltin: true, needsLLM: true,
                  prompt: optimizedPrompts["insight"]!),
        ActionDef(id: "blindspot", name: AppFlavor.text("盲点", "Blind Spots"), icon: "eye.slash.fill",
                  enabled: false, isBuiltin: true, needsLLM: true,
                  prompt: optimizedPrompts["blindspot"]!),
        ActionDef(id: "proofread", name: AppFlavor.text("审校", "Proofread"), icon: "checkmark.seal.fill",
                  enabled: false, isBuiltin: true, needsLLM: true,
                  prompt: optimizedPrompts["proofread"]!),
        ActionDef(id: "mnemonic", name: AppFlavor.text("助记", "Mnemonic"), icon: "brain.head.profile",
                  enabled: false, isBuiltin: true, needsLLM: true,
                  prompt: optimizedPrompts["mnemonic"]!),
        ActionDef(id: "closeread", name: AppFlavor.text("精读", "Close Read"), icon: "character.book.closed",
                  enabled: false, isBuiltin: true, needsLLM: true,
                  prompt: optimizedPrompts["closeread"]!)
        ]
    }

    init() { load() }

    func load() {
        let defaults = UserDefaults.standard
        let data = defaults.data(forKey: key) ?? defaults.data(forKey: legacyKey)
        let shouldApplyDefaultHotKeys = defaults.object(forKey: defaultHotkeysKey) == nil
        let shouldApplyDefaultPrompts = defaults.object(forKey: defaultPromptsKey) == nil
        let shouldApplyBackgroundDefaultOff = defaults.object(forKey: backgroundDefaultOffKey) == nil
        if let data,
           let saved = try? JSONDecoder().decode([ActionDef].self, from: data),
           !saved.isEmpty {
            // Append any newly-added built-ins not present in the saved config.
            var result = saved
            let ids = Set(saved.map { $0.id })
            for b in ActionStore.builtins where !ids.contains(b.id) { result.append(b) }
            actions = normalized(result,
                                 applyNewDefaults: defaults.data(forKey: key) == nil,
                                 applyDefaultHotKeys: shouldApplyDefaultHotKeys,
                                 applyDefaultPrompts: shouldApplyDefaultPrompts,
                                 shouldDisableDefaultBackground: shouldApplyBackgroundDefaultOff)
        } else {
            actions = ActionStore.builtins
        }
        if shouldApplyDefaultHotKeys || shouldApplyDefaultPrompts || shouldApplyBackgroundDefaultOff {
            defaults.set(true, forKey: defaultHotkeysKey)
            defaults.set(true, forKey: defaultPromptsKey)
            defaults.set(true, forKey: backgroundDefaultOffKey)
            persist()
        }
    }

    private func save() {
        actions = normalized(actions, applyNewDefaults: false)
        persist()
        NotificationCenter.default.post(name: .gebwConfigChanged, object: nil)
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(actions) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }

    var enabled: [ActionDef] { actions.filter { $0.enabled } }
    var customCount: Int { actions.filter { !$0.isBuiltin }.count }
    var canAddCustom: Bool { customCount < ActionStore.maxCustom }

    func move(from: IndexSet, to: Int) {
        guard !from.contains(0), to != 0 else { return }
        actions.move(fromOffsets: from, toOffset: to)
        save()
    }

    func move(_ id: String, before targetID: String) {
        guard id != "read", targetID != "read",
              let from = actions.firstIndex(where: { $0.id == id }),
              let target = actions.firstIndex(where: { $0.id == targetID }),
              from != target else { return }
        let item = actions.remove(at: from)
        let adjustedTarget = actions.firstIndex(where: { $0.id == targetID }) ?? target
        actions.insert(item, at: max(1, adjustedTarget))
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
        removeDuplicateHotKey(keeping: i)
        save()
    }

    func setHotKey(_ id: String, code: Int?, mods: Int?, display: String?) {
        guard let i = actions.firstIndex(where: { $0.id == id }) else { return }
        actions[i].hotKeyCode = code
        actions[i].hotKeyMods = mods
        actions[i].hotKeyDisplay = display
        removeDuplicateHotKey(keeping: i)
        save()
    }

    @discardableResult
    func addCustom(_ def: ActionDef) -> Bool {
        guard canAddCustom else { return false }
        var custom = def
        custom.id = custom.id.isEmpty ? UUID().uuidString : custom.id
        custom.enabled = true
        custom.isBuiltin = false
        custom.needsLLM = true
        actions.append(custom)
        removeDuplicateHotKey(keeping: actions.count - 1)
        save()
        return true
    }

    @discardableResult
    func addCustom(name: String, icon: String, prompt: String) -> Bool {
        addCustom(ActionDef(id: UUID().uuidString, name: name, icon: icon,
                            enabled: true, isBuiltin: false, needsLLM: true, prompt: prompt))
    }

    func delete(_ id: String) {
        actions.removeAll { $0.id == id && !$0.isBuiltin }
        save()
    }

    /// Re-label built-in actions in the current UI language (custom actions and
    /// user-edited prompts are left untouched).
    func relocalizeBuiltins() {
        let names = Dictionary(uniqueKeysWithValues: ActionStore.builtins.map { ($0.id, $0.name) })
        for i in actions.indices where actions[i].isBuiltin {
            if let name = names[actions[i].id] { actions[i].name = name }
        }
        save()
    }

    func resetToDefaults() {
        actions = ActionStore.builtins
        save()
    }

    private func removeDuplicateHotKey(keeping index: Int) {
        removeDuplicateHotKey(keeping: index, in: &actions)
    }

    private func removeDuplicateHotKey(keeping index: Int, in list: inout [ActionDef]) {
        guard list.indices.contains(index),
              let code = list[index].hotKeyCode,
              let mods = list[index].hotKeyMods else { return }
        for j in list.indices where j != index && list[j].hotKeyCode == code && list[j].hotKeyMods == mods {
            list[j].hotKeyCode = nil
            list[j].hotKeyMods = nil
            list[j].hotKeyDisplay = nil
        }
    }

    private func normalized(_ list: [ActionDef], applyNewDefaults: Bool,
                            applyDefaultHotKeys: Bool = false,
                            applyDefaultPrompts: Bool = false,
                            shouldDisableDefaultBackground: Bool = false) -> [ActionDef] {
        var normalized = list
        if applyNewDefaults, let i = normalized.firstIndex(where: { $0.id == "read" }),
           normalized[i].hotKeyCode == nil, normalized[i].hotKeyMods == nil {
            normalized[i].hotKeyCode = 15
            normalized[i].hotKeyMods = controlKey | shiftKey
            normalized[i].hotKeyDisplay = "⌃⇧R"
            removeDuplicateHotKey(keeping: i, in: &normalized)
        }
        if applyDefaultHotKeys {
            applyDefaultHotKey("explain", code: Int(kVK_ANSI_E), display: "⌃⇧E", in: &normalized)
            applyDefaultHotKey("translate", code: Int(kVK_ANSI_T), display: "⌃⇧T", in: &normalized)
        }
        if applyDefaultPrompts {
            applyOptimizedDefaultPrompts(in: &normalized)
        }
        if shouldDisableDefaultBackground {
            applyBackgroundDefaultOff(in: &normalized)
        }
        if let readIndex = normalized.firstIndex(where: { $0.id == "read" }) {
            let read = normalized.remove(at: readIndex)
            normalized = [read] + normalized
        }
        deduplicateHotKeys(in: &normalized)
        return normalized
    }

    private func applyDefaultHotKey(_ id: String, code: Int, display: String, in actions: inout [ActionDef]) {
        guard let i = actions.firstIndex(where: { $0.id == id }),
              actions[i].hotKeyCode == nil,
              actions[i].hotKeyMods == nil else { return }
        actions[i].hotKeyCode = code
        actions[i].hotKeyMods = controlKey | shiftKey
        actions[i].hotKeyDisplay = display
        removeDuplicateHotKey(keeping: i, in: &actions)
    }

    private func applyOptimizedDefaultPrompts(in actions: inout [ActionDef]) {
        for i in actions.indices {
            let id = actions[i].id
            guard actions[i].isBuiltin,
                  let optimized = Self.optimizedPrompts[id] else { continue }
            guard Self.previousDefaultPrompts[id]?.contains(actions[i].prompt) == true else { continue }
            actions[i].prompt = optimized
        }
    }

    private func applyBackgroundDefaultOff(in actions: inout [ActionDef]) {
        guard let i = actions.firstIndex(where: { $0.id == "background" && $0.isBuiltin }),
              actions[i].enabled else { return }
        var knownDefaults = Self.previousDefaultPrompts["background"] ?? []
        if let optimized = Self.optimizedPrompts["background"] {
            knownDefaults.insert(optimized)
        }
        guard knownDefaults.contains(actions[i].prompt) else { return }
        actions[i].enabled = false
    }

    private func deduplicateHotKeys(in actions: inout [ActionDef]) {
        var seen = Set<String>()
        for i in actions.indices {
            guard let code = actions[i].hotKeyCode,
                  let mods = actions[i].hotKeyMods else { continue }
            let key = "\(code):\(mods)"
            if seen.contains(key) {
                actions[i].hotKeyCode = nil
                actions[i].hotKeyMods = nil
                actions[i].hotKeyDisplay = nil
            } else {
                seen.insert(key)
            }
        }
    }
}
