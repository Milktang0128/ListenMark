import Foundation

/// A toolbar action — built-in or user-defined. LLM actions carry a system
/// prompt; `read` (needsLLM == false) just speaks the original text.
struct ActionDef: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var icon: String
    var enabled: Bool
    var isBuiltin: Bool
    var needsLLM: Bool
    var prompt: String
    var hotKeyCode: Int?
    var hotKeyMods: Int?
    var hotKeyDisplay: String?

    init(id: String, name: String, icon: String, enabled: Bool, isBuiltin: Bool,
         needsLLM: Bool, prompt: String, hotKeyCode: Int? = nil,
         hotKeyMods: Int? = nil, hotKeyDisplay: String? = nil) {
        self.id = id
        self.name = name
        self.icon = icon
        self.enabled = enabled
        self.isBuiltin = isBuiltin
        self.needsLLM = needsLLM
        self.prompt = prompt
        self.hotKeyCode = hotKeyCode
        self.hotKeyMods = hotKeyMods
        self.hotKeyDisplay = hotKeyDisplay
    }
}

/// One archived interaction. `action`/`icon` are stored by value so custom and
/// renamed actions still render correctly in the archive.
struct Entry: Identifiable, Codable {
    var id: UUID = UUID()
    var date: Date = Date()
    var action: String
    var icon: String?
    var sourceApp: String
    var sourceMetadata: SourceMetadata? = nil
    var original: String
    var response: String?
    var responseModel: String? = nil
    var comparison: ComparisonRecord? = nil
    var contextUsed: Bool?
    var contextExcerpt: String?
    // Multi-turn conversation (nil for single-shot entries; back-compatible).
    var conversationTurns: [ConversationTurn]? = nil
    // Spaced-repetition state (optional → back-compatible with old archives).
    var reviewCount: Int?
    var lastReviewed: Date?
    var mastered: Bool?
}

/// One turn in a multi-turn conversation (the 对话 skill and global follow-up).
/// `languageIsEnglish` is captured when the turn is created so old turns keep
/// rendering with the labels they were written in even if the UI language flips.
struct ConversationTurn: Codable, Equatable, Identifiable {
    enum Role: String, Codable { case user, assistant }
    var id: UUID = UUID()
    var role: Role
    var text: String
    var date: Date = Date()
    var model: String? = nil
    var languageIsEnglish: Bool = false
}

/// Silent recent-history item. This deliberately omits full-text context so it
/// stays lightweight and separate from intentional archive entries.
struct HistoryEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var date: Date = Date()
    var action: String
    var icon: String?
    var sourceApp: String
    var original: String
    var response: String?
    var responseModel: String? = nil
    var comparison: ComparisonRecord? = nil
}

struct SourceMetadata: Codable, Equatable {
    var appName: String
    var bundleIdentifier: String?
    var windowTitle: String?
    var pageTitle: String?
    var pageURL: String?

    init(appName: String,
         bundleIdentifier: String? = nil,
         windowTitle: String? = nil,
         pageTitle: String? = nil,
         pageURL: String? = nil) {
        self.appName = appName
        self.bundleIdentifier = SourceMetadata.clean(bundleIdentifier)
        self.windowTitle = SourceMetadata.clean(windowTitle)
        self.pageTitle = SourceMetadata.clean(pageTitle)
        self.pageURL = SourceMetadata.clean(pageURL)
    }

    var searchText: String {
        [appName, windowTitle, pageTitle, pageURL]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    var compactSummary: String? {
        if let pageTitle, !pageTitle.isEmpty { return pageTitle }
        if let windowTitle, !windowTitle.isEmpty, windowTitle != appName { return windowTitle }
        return nil
    }

    var hasReadableContext: Bool {
        if let pageURL, !pageURL.isEmpty { return true }
        if let pageTitle, !pageTitle.isEmpty { return true }
        if let windowTitle, !windowTitle.isEmpty, windowTitle != appName { return true }
        return false
    }

    var modelContextBlock: String? {
        var lines: [String] = []
        lines.append(AppFlavor.text("应用：\(appName)", "App: \(appName)"))
        if let pageTitle, !pageTitle.isEmpty {
            lines.append(AppFlavor.text("网页标题：\(pageTitle)", "Page title: \(pageTitle)"))
        } else if let windowTitle, !windowTitle.isEmpty, windowTitle != appName {
            lines.append(AppFlavor.text("窗口标题：\(windowTitle)", "Window title: \(windowTitle)"))
        }
        if let pageURL, !pageURL.isEmpty {
            lines.append(AppFlavor.text("网页链接：\(pageURL)", "Page URL: \(pageURL)"))
        }
        guard lines.count > 1 || bundleIdentifier != nil else { return nil }
        return lines.joined(separator: "\n")
    }

    var markdownBlock: String? {
        var lines: [String] = []
        lines.append("**\(AppFlavor.text("来源", "Source"))**：\(appName.markdownInlineEscaped)")
        if let pageTitle, !pageTitle.isEmpty {
            lines.append("**\(AppFlavor.text("页面", "Page"))**：\(pageTitle.markdownInlineEscaped)")
        } else if let windowTitle, !windowTitle.isEmpty, windowTitle != appName {
            lines.append("**\(AppFlavor.text("窗口", "Window"))**：\(windowTitle.markdownInlineEscaped)")
        }
        if let pageURL, !pageURL.isEmpty {
            lines.append("**\(AppFlavor.text("链接", "URL"))**：<\(pageURL)>")
        }
        guard lines.count > 1 else { return nil }
        return lines.joined(separator: "\n")
    }

    private static func clean(_ value: String?) -> String? {
        let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return clean.isEmpty ? nil : clean
    }
}

struct LLMProviderConfig: Identifiable, Equatable {
    var id: String
    var label: String
    var baseURL: String
    var apiKey: String
    var model: String
    var isDefault: Bool = false
}

struct LLMServiceProvider: Identifiable, Codable, Equatable {
    var id: String
    var label: String
    var baseURL: String
    var apiKey: String
    var model: String
    var enabled: Bool
    var compareEnabled: Bool
    var presetID: String?

    init(id: String = UUID().uuidString,
         label: String,
         baseURL: String,
         apiKey: String = "",
         model: String,
         enabled: Bool = true,
         compareEnabled: Bool = false,
         presetID: String? = nil) {
        self.id = id
        self.label = label
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.enabled = enabled
        self.compareEnabled = compareEnabled
        self.presetID = presetID
    }

    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var runtimeConfig: LLMProviderConfig {
        LLMProviderConfig(id: id, label: label, baseURL: baseURL, apiKey: apiKey, model: model)
    }
}

struct CompareModelResult: Identifiable, Equatable {
    var id: String
    var label: String
    var model: String
    var text: String
    var isLoading: Bool
    var error: String?
}

struct ModelRunResult: Identifiable, Codable, Equatable {
    var id: String
    var label: String
    var model: String
    var status: String
    var response: String?
    var error: String?
}

struct ComparisonRecord: Codable, Equatable {
    var primaryID: String
    var selectedID: String
    var results: [ModelRunResult]
}

/// Lightweight spaced-repetition schedule for 今日回响.
enum ReviewSchedule {
    /// Intervals after each review, in seconds: 1d → 3d → 7d → 16d → 35d → 90d.
    static let intervals: [TimeInterval] = [86_400, 259_200, 604_800, 1_382_400, 3_024_000, 7_776_000]

    static func interval(forCount c: Int) -> TimeInterval {
        intervals[max(0, min(c, intervals.count - 1))]
    }

    /// Baseline a due date is measured from: last review, or creation if never reviewed.
    static func base(_ e: Entry) -> Date { e.lastReviewed ?? e.date }

    static func isDue(_ e: Entry, now: Date) -> Bool {
        if e.mastered == true { return false }
        return now.timeIntervalSince(base(e)) >= interval(forCount: e.reviewCount ?? 0)
    }
}

extension String {
    /// Rough CJK/Kana/Hangul check — used to pick a voice.
    var containsCJK: Bool {
        for s in unicodeScalars {
            let v = s.value
            if (0x4E00...0x9FFF).contains(v) || (0x3040...0x30FF).contains(v) || (0xAC00...0xD7AF).contains(v) {
                return true
            }
        }
        return false
    }

    var preview: String {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count <= 24 ? t : String(t.prefix(24)) + "…"
    }

    var markdownInlineEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

extension JSONEncoder {
    static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
}
