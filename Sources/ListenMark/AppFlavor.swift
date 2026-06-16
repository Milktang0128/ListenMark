import Foundation

enum AppFlavor {
    // MARK: Build flavor (fixed at build time — distribution identity, NOT UI language)

    static var rawValue: String {
        Bundle.main.object(forInfoDictionaryKey: "LMAppFlavor") as? String ?? "zh"
    }

    /// The legacy international BUILD. Drives bundle id / update channel only —
    /// NOT the interface language. Kept so the GitHub updater stays correct.
    static var isInternational: Bool { rawValue == "international" }

    // Bridge release: keep the old bundle identifiers and support folders so
    // existing users retain Accessibility permission, settings, and archives.
    static var bundleIdentifier: String { isInternational ? "com.listenmark.international" : "com.listenmark.app" }
    static var supportFolderName: String { isInternational ? "ListenMark International" : "ListenMark" }
    static var releaseTagPrefix: String { isInternational ? "listenmark-v" : "v" }
    static var usesPrereleaseUpdateChannel: Bool { isInternational }

    // MARK: Branding (unified — one name regardless of build or language)

    static var brandName: String { "Dob" }
    static var appName: String { "Dob" }
    static var tagline: String {
        text("过耳不忘的 AI 读写工具", "An AI reading and writing tool with context, speech, and memory.")
    }

    // MARK: UI language (runtime — follows system locale, overridable in Settings)

    /// "system" | "zh" | "en"
    static var languagePreference: String {
        UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
    }

    static var systemPrefersChinese: Bool {
        (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("zh")
    }

    /// The single switch every piece of localized copy (and the translate target)
    /// reads. Changing the override or the system language flips the whole app.
    static var uiLanguageIsEnglish: Bool {
        switch languagePreference {
        case "en": return true
        case "zh": return false
        default:   return !systemPrefersChinese   // "system"
        }
    }

    static func text(_ zh: String, _ en: String) -> String {
        uiLanguageIsEnglish ? en : zh
    }
}
