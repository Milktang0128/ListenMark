import Foundation

enum AppFlavor {
    static var rawValue: String {
        Bundle.main.object(forInfoDictionaryKey: "LMAppFlavor") as? String ?? "zh"
    }

    static var isInternational: Bool { rawValue == "international" }

    static var appName: String { isInternational ? "ListenMark" : "过耳不忘" }
    static var bundleIdentifier: String { isInternational ? "com.listenmark.international" : "com.listenmark.app" }
    static var supportFolderName: String { isInternational ? "ListenMark International" : "ListenMark" }
    static var releaseTagPrefix: String { isInternational ? "listenmark-v" : "v" }
    static var usesPrereleaseUpdateChannel: Bool { isInternational }

    static func text(_ zh: String, _ en: String) -> String {
        isInternational ? en : zh
    }
}
