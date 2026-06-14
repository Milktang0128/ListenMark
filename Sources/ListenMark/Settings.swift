import Foundation
import AVFoundation

/// Thin UserDefaults wrapper. Shared with the SwiftUI settings view via
/// matching @AppStorage keys.
enum Settings {
    private static let d = UserDefaults.standard

    // MARK: Text actions — DeepSeek

    static var deepseekKey: String {
        get { d.string(forKey: "deepseekKey") ?? "" }
        set { d.set(newValue, forKey: "deepseekKey") }
    }

    static var deepseekModel: String {
        get {
            let m = d.string(forKey: "deepseekModel") ?? ""
            return m.isEmpty ? "deepseek-v4-flash" : m
        }
        set { d.set(newValue, forKey: "deepseekModel") }
    }

    // MARK: Speech engine

    /// "volcano" (火山引擎, recommended) or "local" (macOS).
    static var ttsEngine: String {
        get {
            let e = d.string(forKey: "ttsEngine") ?? ""
            return e.isEmpty ? "volcano" : e
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
            return v.isEmpty ? "zh_female_cancan_uranus_bigtts" : v
        }
        set { d.set(newValue, forKey: "volcVoice") }
    }

    static var volcSpeed: Double {
        get { d.object(forKey: "volcSpeed") == nil ? 1.0 : d.double(forKey: "volcSpeed") }
        set { d.set(newValue, forKey: "volcSpeed") }
    }

    static var volcConfigured: Bool { !volcAppId.isEmpty && !volcToken.isEmpty }

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
}

/// Posted whenever the trigger config (hotkey / auto-pop) changes.
extension Notification.Name {
    static let gebwConfigChanged = Notification.Name("GEBWConfigChanged")
}
