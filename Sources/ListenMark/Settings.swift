import Foundation
import AVFoundation
import Carbon.HIToolbox

/// Thin UserDefaults wrapper. Shared with the SwiftUI settings view via
/// matching @AppStorage keys.
enum Settings {
    private static let d = UserDefaults.standard
    private static let disabledAutoPopAppsKey = "disabledAutoPopApps"
    private static let llmServiceProvidersKey = "llmServiceProviders"
    private static let actionLLMProviderOverridesKey = "actionLLMProviderOverrides"

    // MARK: Onboarding

    /// 0 = onboarding never completed. Otherwise stores the CFBundleVersion at
    /// completion (so future builds can show a "what's new" without re-onboarding).
    static var onboardingCompletedBuild: Int {
        get { d.integer(forKey: "onboardingCompletedBuild") }
        set { d.set(newValue, forKey: "onboardingCompletedBuild") }
    }

    /// One-time prompt offering to put the Markdown archive into Obsidian, shown
    /// at the user's first successful archive (not during onboarding).
    static var obsidianHintShown: Bool {
        get { d.bool(forKey: "obsidianHintShown") }
        set { d.set(newValue, forKey: "obsidianHintShown") }
    }

    // MARK: Text actions — OpenAI-compatible chat completions

    static let recommendedLLMBaseURL = "https://api.deepseek.com"
    static let recommendedLLMModel = "deepseek-v4-flash"

    static var llmBaseURL: String {
        get {
            d.string(forKey: "llmBaseURL") ?? recommendedLLMBaseURL
        }
        set { d.set(newValue, forKey: "llmBaseURL") }
    }

    static var llmAPIKey: String {
        get { d.string(forKey: "deepseekKey") ?? "" }
        set { d.set(newValue, forKey: "deepseekKey") }
    }

    static var llmModel: String {
        get {
            let m = d.string(forKey: "deepseekModel") ?? ""
            return m.isEmpty ? recommendedLLMModel : m
        }
        set { d.set(newValue, forKey: "deepseekModel") }
    }

    static var llmChatCompletionsURL: URL? {
        let raw = llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let normalized = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        if normalized.lowercased().hasSuffix("/chat/completions") {
            return URL(string: normalized)
        }
        return URL(string: normalized + "/chat/completions")
    }

    static var defaultLLMProvider: LLMProviderConfig {
        LLMProviderConfig(id: "default", label: AppFlavor.text("默认", "Default"),
                          baseURL: llmBaseURL, apiKey: llmAPIKey, model: llmModel,
                          isDefault: true)
    }

    static var compareProviders: [LLMProviderConfig] {
        compareProviders(baseline: defaultLLMProvider)
    }

    static var llmServiceProviders: [LLMServiceProvider] {
        get {
            if let data = d.data(forKey: llmServiceProvidersKey),
               let providers = try? JSONDecoder().decode([LLMServiceProvider].self, from: data) {
                return providers
            }
            let migrated = legacyCompareProviders()
            if !migrated.isEmpty {
                let data = try? JSONEncoder().encode(migrated)
                d.set(data, forKey: llmServiceProvidersKey)
            }
            return migrated
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            d.set(data, forKey: llmServiceProvidersKey)
        }
    }

    static var enabledLLMServiceProviders: [LLMServiceProvider] {
        llmServiceProviders.filter { $0.enabled }
    }

    static func llmProvider(id: String?) -> LLMProviderConfig {
        guard let id, id != defaultLLMProvider.id,
              let provider = llmServiceProviders.first(where: { $0.id == id && $0.enabled }) else {
            return defaultLLMProvider
        }
        return provider.runtimeConfig
    }

    static func llmProvider(for action: ActionDef) -> LLMProviderConfig {
        llmProvider(id: actionLLMProviderID(for: action.id))
    }

    static func compareProviders(baseline: LLMProviderConfig) -> [LLMProviderConfig] {
        let alternates = llmServiceProviders
            .filter { $0.enabled && $0.compareEnabled && $0.id != baseline.id }
            .map { $0.runtimeConfig }
        return [baseline] + Array(alternates.prefix(2))
    }

    static var llmProviderChoices: [LLMProviderConfig] {
        [defaultLLMProvider] + enabledLLMServiceProviders.map { $0.runtimeConfig }
    }

    static var actionLLMProviderOverrides: [String: String] {
        get { d.dictionary(forKey: actionLLMProviderOverridesKey) as? [String: String] ?? [:] }
        set { d.set(newValue, forKey: actionLLMProviderOverridesKey) }
    }

    static func actionLLMProviderID(for actionID: String) -> String? {
        actionLLMProviderOverrides[actionID]
    }

    static func setActionLLMProviderID(_ providerID: String?, for actionID: String) {
        var overrides = actionLLMProviderOverrides
        if let providerID, providerID != defaultLLMProvider.id {
            overrides[actionID] = providerID
        } else {
            overrides.removeValue(forKey: actionID)
        }
        actionLLMProviderOverrides = overrides
    }

    static func clearActionProviderReferences(to providerID: String) {
        let filtered = actionLLMProviderOverrides.filter { $0.value != providerID }
        if filtered.count != actionLLMProviderOverrides.count {
            actionLLMProviderOverrides = filtered
        }
    }

    private static func legacyCompareProviders() -> [LLMServiceProvider] {
        [legacyCompareProvider(slot: 1), legacyCompareProvider(slot: 2)].compactMap { $0 }
    }

    private static func legacyCompareProvider(slot: Int) -> LLMServiceProvider? {
        let enabled: Bool
        let label: String
        let baseURL: String
        let apiKey: String
        let model: String
        if slot == 1 {
            enabled = compareProvider1Enabled
            label = compareProvider1Label
            baseURL = compareProvider1BaseURL
            apiKey = compareProvider1APIKey
            model = compareProvider1Model
        } else {
            enabled = compareProvider2Enabled
            label = compareProvider2Label
            baseURL = compareProvider2BaseURL
            apiKey = compareProvider2APIKey
            model = compareProvider2Model
        }
        let hasContent = [baseURL, apiKey, model]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard enabled || hasContent else { return nil }
        return LLMServiceProvider(id: "legacy-compare-\(slot)",
                                  label: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppFlavor.text("备选 \(slot)", "Alt \(slot)") : label,
                                  baseURL: baseURL,
                                  apiKey: apiKey,
                                  model: model,
                                  enabled: true,
                                  compareEnabled: enabled)
    }

    static var deepseekKey: String {
        get { llmAPIKey }
        set { llmAPIKey = newValue }
    }

    static var deepseekModel: String {
        get { llmModel }
        set { llmModel = newValue }
    }

    static var useFullContext: Bool {
        get { d.object(forKey: "useFullContext") == nil ? true : d.bool(forKey: "useFullContext") }
        set { d.set(newValue, forKey: "useFullContext") }
    }

    static var autoSpeakAI: Bool {
        get { d.object(forKey: "autoSpeakAI") == nil ? true : d.bool(forKey: "autoSpeakAI") }
        set { d.set(newValue, forKey: "autoSpeakAI") }
    }

    static var panelTextSizeDelta: Int {
        get { d.integer(forKey: "panelTextSizeDelta") }
        set { d.set(max(-2, min(6, newValue)), forKey: "panelTextSizeDelta") }
    }

    static var compareProvider1Enabled: Bool {
        get { d.bool(forKey: "compareProvider1Enabled") }
        set { d.set(newValue, forKey: "compareProvider1Enabled") }
    }

    static var compareProvider1Label: String {
        get { d.string(forKey: "compareProvider1Label") ?? AppFlavor.text("备选 A", "Alt A") }
        set { d.set(newValue, forKey: "compareProvider1Label") }
    }

    static var compareProvider1BaseURL: String {
        get {
            let value = d.string(forKey: "compareProvider1BaseURL") ?? ""
            return value.isEmpty ? recommendedLLMBaseURL : value
        }
        set { d.set(newValue, forKey: "compareProvider1BaseURL") }
    }

    static var compareProvider1APIKey: String {
        get { d.string(forKey: "compareProvider1APIKey") ?? "" }
        set { d.set(newValue, forKey: "compareProvider1APIKey") }
    }

    static var compareProvider1Model: String {
        get { d.string(forKey: "compareProvider1Model") ?? "" }
        set { d.set(newValue, forKey: "compareProvider1Model") }
    }

    static var compareProvider2Enabled: Bool {
        get { d.bool(forKey: "compareProvider2Enabled") }
        set { d.set(newValue, forKey: "compareProvider2Enabled") }
    }

    static var compareProvider2Label: String {
        get { d.string(forKey: "compareProvider2Label") ?? AppFlavor.text("备选 B", "Alt B") }
        set { d.set(newValue, forKey: "compareProvider2Label") }
    }

    static var compareProvider2BaseURL: String {
        get {
            let value = d.string(forKey: "compareProvider2BaseURL") ?? ""
            return value.isEmpty ? recommendedLLMBaseURL : value
        }
        set { d.set(newValue, forKey: "compareProvider2BaseURL") }
    }

    static var compareProvider2APIKey: String {
        get { d.string(forKey: "compareProvider2APIKey") ?? "" }
        set { d.set(newValue, forKey: "compareProvider2APIKey") }
    }

    static var compareProvider2Model: String {
        get { d.string(forKey: "compareProvider2Model") ?? "" }
        set { d.set(newValue, forKey: "compareProvider2Model") }
    }

    // MARK: Speech engine

    /// "local" (macOS), "volcano", "microsoft", "google", or "tencent".
    static var ttsEngine: String {
        get {
            let e = d.string(forKey: "ttsEngine") ?? ""
            return e.isEmpty ? AppFlavor.text("volcano", "local") : e
        }
        set { d.set(newValue, forKey: "ttsEngine") }
    }

    static var volcAppId: String {
        get { d.string(forKey: "volcAppId") ?? "" }
        set { d.set(newValue, forKey: "volcAppId") }
    }

    static var volcToken: String {
        get { d.string(forKey: "volcToken") ?? "" }
        set { d.set(newValue, forKey: "volcToken") }
    }

    static var volcCluster: String {
        get {
            let c = d.string(forKey: "volcCluster") ?? ""
            return c.isEmpty ? "volcano_tts" : c
        }
        set { d.set(newValue, forKey: "volcCluster") }
    }

    static var volcVoice: String {
        get {
            let v = d.string(forKey: "volcVoice") ?? ""
            return v.isEmpty ? AppFlavor.text("zh_female_cancan_uranus_bigtts", "en_female_dacey_uranus_bigtts") : v
        }
        set { d.set(newValue, forKey: "volcVoice") }
    }

    static var volcSpeed: Double {
        get { d.object(forKey: "volcSpeed") == nil ? 1.0 : d.double(forKey: "volcSpeed") }
        set { d.set(newValue, forKey: "volcSpeed") }
    }

    static var volcConfigured: Bool { !volcAppId.isEmpty && !volcToken.isEmpty }

    static var microsoftTTSKey: String {
        get { d.string(forKey: "microsoftTTSKey") ?? "" }
        set { d.set(newValue, forKey: "microsoftTTSKey") }
    }

    static var microsoftTTSRegion: String {
        get {
            let value = d.string(forKey: "microsoftTTSRegion") ?? ""
            return value.isEmpty ? "eastasia" : value
        }
        set { d.set(newValue, forKey: "microsoftTTSRegion") }
    }

    static var microsoftTTSVoice: String {
        get {
            let value = d.string(forKey: "microsoftTTSVoice") ?? ""
            return value.isEmpty ? "zh-CN-XiaoxiaoNeural" : value
        }
        set { d.set(newValue, forKey: "microsoftTTSVoice") }
    }

    static var microsoftTTSConfigured: Bool {
        !microsoftTTSKey.isEmpty && !microsoftTTSRegion.isEmpty && !microsoftTTSVoice.isEmpty
    }

    static var googleTTSKey: String {
        get { d.string(forKey: "googleTTSKey") ?? "" }
        set { d.set(newValue, forKey: "googleTTSKey") }
    }

    static var googleTTSVoice: String {
        get {
            let value = d.string(forKey: "googleTTSVoice") ?? ""
            return value.isEmpty ? "cmn-CN-Standard-A" : value
        }
        set { d.set(newValue, forKey: "googleTTSVoice") }
    }

    static var googleTTSSpeed: Double {
        get { d.object(forKey: "googleTTSSpeed") == nil ? 1.0 : d.double(forKey: "googleTTSSpeed") }
        set { d.set(newValue, forKey: "googleTTSSpeed") }
    }

    static var googleTTSConfigured: Bool {
        !googleTTSKey.isEmpty && !googleTTSVoice.isEmpty
    }

    static var tencentTTSSecretId: String {
        get { d.string(forKey: "tencentTTSSecretId") ?? "" }
        set { d.set(newValue, forKey: "tencentTTSSecretId") }
    }

    static var tencentTTSSecretKey: String {
        get { d.string(forKey: "tencentTTSSecretKey") ?? "" }
        set { d.set(newValue, forKey: "tencentTTSSecretKey") }
    }

    static var tencentTTSHost: String {
        get {
            let value = d.string(forKey: "tencentTTSHost") ?? ""
            return value.isEmpty ? AppFlavor.text("tts.tencentcloudapi.com", "tts.intl.tencentcloudapi.com") : value
        }
        set { d.set(newValue, forKey: "tencentTTSHost") }
    }

    static var tencentTTSRegion: String {
        get {
            let value = d.string(forKey: "tencentTTSRegion") ?? ""
            return value.isEmpty ? "ap-guangzhou" : value
        }
        set { d.set(newValue, forKey: "tencentTTSRegion") }
    }

    static var tencentTTSVoice: String {
        get {
            let value = d.string(forKey: "tencentTTSVoice") ?? ""
            return value.isEmpty ? AppFlavor.text("1001", "1050") : value
        }
        set { d.set(newValue, forKey: "tencentTTSVoice") }
    }

    static var tencentTTSSpeed: Double {
        get { d.object(forKey: "tencentTTSSpeed") == nil ? 0.0 : d.double(forKey: "tencentTTSSpeed") }
        set { d.set(newValue, forKey: "tencentTTSSpeed") }
    }

    static var tencentTTSConfigured: Bool {
        !tencentTTSSecretId.isEmpty && !tencentTTSSecretKey.isEmpty && !tencentTTSHost.isEmpty && !tencentTTSRegion.isEmpty
    }

    // MARK: Archive

    /// Auto-save every interaction. Default OFF — user archives on demand.
    static var autoArchive: Bool {
        get { d.bool(forKey: "autoArchive") }
        set { d.set(newValue, forKey: "autoArchive") }
    }

    /// User-chosen folder for the human-readable Markdown archive (e.g. an
    /// Obsidian vault). Empty → default Application Support folder.
    static var archiveFolder: String {
        get { d.string(forKey: "archiveFolder") ?? "" }
        set { d.set(newValue, forKey: "archiveFolder") }
    }

    static var historyEnabled: Bool {
        get { d.object(forKey: "historyEnabled") == nil ? true : d.bool(forKey: "historyEnabled") }
        set { d.set(newValue, forKey: "historyEnabled") }
    }

    /// Local AVSpeechUtterance rate (0.0–1.0; ~0.5 is the natural default).
    static var speechRate: Float {
        get {
            if d.object(forKey: "rate") == nil { return AVSpeechUtteranceDefaultSpeechRate }
            return d.float(forKey: "rate")
        }
        set { d.set(newValue, forKey: "rate") }
    }

    // MARK: Trigger

    static var autoPop: Bool {
        get { d.object(forKey: "autoPop") == nil ? true : d.bool(forKey: "autoPop") }
        set { d.set(newValue, forKey: "autoPop") }
    }

    static var autoPopCopyFallback: Bool {
        get { d.object(forKey: "autoPopCopyFallback") == nil ? true : d.bool(forKey: "autoPopCopyFallback") }
        set { d.set(newValue, forKey: "autoPopCopyFallback") }
    }

    static var autoDismissPanel: Bool {
        get { d.object(forKey: "autoDismissPanel") == nil ? true : d.bool(forKey: "autoDismissPanel") }
        set { d.set(newValue, forKey: "autoDismissPanel") }
    }

    static var disabledAutoPopApps: [String: String] {
        get { d.dictionary(forKey: disabledAutoPopAppsKey) as? [String: String] ?? [:] }
        set { d.set(newValue, forKey: disabledAutoPopAppsKey) }
    }

    static var disabledAutoPopAppsSorted: [(bundleID: String, name: String)] {
        disabledAutoPopApps
            .map { (bundleID: $0.key, name: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func disableAutoPop(bundleID: String, appName: String) {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        var apps = disabledAutoPopApps
        apps[id] = appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? id : appName
        disabledAutoPopApps = apps
    }

    static func enableAutoPop(bundleID: String) {
        var apps = disabledAutoPopApps
        apps.removeValue(forKey: bundleID)
        disabledAutoPopApps = apps
    }

    static func isAutoPopDisabled(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return disabledAutoPopApps[bundleID] != nil
    }

    static var hotKeyCode: Int {
        get { d.object(forKey: "hkCode") == nil ? 15 : d.integer(forKey: "hkCode") }
        set { d.set(newValue, forKey: "hkCode") }
    }

    static var hotKeyMods: Int {
        get { d.object(forKey: "hkMods") == nil ? (256 | 2048) : d.integer(forKey: "hkMods") }
        set { d.set(newValue, forKey: "hkMods") }
    }

    static var hotKeyDisplay: String {
        get {
            let s = d.string(forKey: "hkDisplay") ?? ""
            return s.isEmpty ? "⌥⌘R" : s
        }
        set { d.set(newValue, forKey: "hkDisplay") }
    }

    static var ocrHotKeyCode: Int {
        get { d.object(forKey: "ocrHkCode") == nil ? Int(kVK_ANSI_O) : d.integer(forKey: "ocrHkCode") }
        set { d.set(newValue, forKey: "ocrHkCode") }
    }

    static var ocrHotKeyMods: Int {
        get { d.object(forKey: "ocrHkMods") == nil ? (controlKey | shiftKey) : d.integer(forKey: "ocrHkMods") }
        set { d.set(newValue, forKey: "ocrHkMods") }
    }

    static var ocrHotKeyDisplay: String {
        get {
            let s = d.string(forKey: "ocrHkDisplay") ?? ""
            return s.isEmpty ? "⌃⇧O" : s
        }
        set { d.set(newValue, forKey: "ocrHkDisplay") }
    }

    static var silentOCRHotKeyCode: Int {
        get { d.object(forKey: "silentOcrHkCode") == nil ? Int(kVK_ANSI_C) : d.integer(forKey: "silentOcrHkCode") }
        set { d.set(newValue, forKey: "silentOcrHkCode") }
    }

    static var silentOCRHotKeyMods: Int {
        get { d.object(forKey: "silentOcrHkMods") == nil ? (controlKey | shiftKey) : d.integer(forKey: "silentOcrHkMods") }
        set { d.set(newValue, forKey: "silentOcrHkMods") }
    }

    static var silentOCRHotKeyDisplay: String {
        get {
            let s = d.string(forKey: "silentOcrHkDisplay") ?? ""
            return s.isEmpty ? "⌃⇧C" : s
        }
        set { d.set(newValue, forKey: "silentOcrHkDisplay") }
    }

    static var inputHotKeyCode: Int {
        get { d.object(forKey: "inputHkCode") == nil ? Int(kVK_ANSI_I) : d.integer(forKey: "inputHkCode") }
        set { d.set(newValue, forKey: "inputHkCode") }
    }

    static var inputHotKeyMods: Int {
        get { d.object(forKey: "inputHkMods") == nil ? (controlKey | shiftKey) : d.integer(forKey: "inputHkMods") }
        set { d.set(newValue, forKey: "inputHkMods") }
    }

    static var inputHotKeyDisplay: String {
        get {
            let s = d.string(forKey: "inputHkDisplay") ?? ""
            return s.isEmpty ? "⌃⇧I" : s
        }
        set { d.set(newValue, forKey: "inputHkDisplay") }
    }

    static var ocrAutoRunLastAction: Bool {
        get { d.object(forKey: "ocrAutoRunLastAction") == nil ? true : d.bool(forKey: "ocrAutoRunLastAction") }
        set { d.set(newValue, forKey: "ocrAutoRunLastAction") }
    }

    static var lastActionID: String {
        get { d.string(forKey: "lastActionID") ?? "" }
        set { d.set(newValue, forKey: "lastActionID") }
    }
}

/// Posted whenever the trigger config (hotkey / auto-pop) changes.
extension Notification.Name {
    static let gebwConfigChanged = Notification.Name("GEBWConfigChanged")
    static let gebwOpenSettings = Notification.Name("GEBWOpenSettings")
    static let gebwOpenActions = Notification.Name("GEBWOpenActions")
    static let gebwOpenServices = Notification.Name("GEBWOpenServices")
    static let gebwOpenHistory = Notification.Name("GEBWOpenHistory")
}
