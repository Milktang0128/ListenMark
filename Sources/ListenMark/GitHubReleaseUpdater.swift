import AppKit
import Foundation

@MainActor
final class GitHubReleaseUpdater {
    static let shared = GitHubReleaseUpdater()

    private let owner = "Milktang0128"
    private let repo = "ListenMark"
    private let lastCheckKey = "githubReleaseUpdater.lastCheckAt"
    private let checkInterval: TimeInterval = 24 * 60 * 60
    private var isDownloading = false

    private init() {}

    func checkAutomaticallyIfNeeded() {
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
        guard last == nil || Date().timeIntervalSince(last!) > checkInterval else { return }
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)

        Task { await check(silent: true) }
    }

    func checkNow() {
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)
        Task { await check(silent: false) }
    }

    private func check(silent: Bool) async {
        do {
            let release = try await fetchLatestRelease()
            guard release.isUsableForCurrentFlavor else {
                if !silent {
                    showMessage(AppFlavor.text("没有可用更新", "No Update Available"),
                                AppFlavor.text("当前发布通道没有可安装的新版本。", "There is no installable release on the current update channel."))
                }
                return
            }

            let current = currentVersion
            guard Self.compare(release.cleanVersion, current) == .orderedDescending else {
                if !silent {
                    showMessage(AppFlavor.text("已是最新版本", "You're Up to Date"),
                                AppFlavor.text("当前版本 \(current) 已经是 GitHub Releases 上的最新版本。", "Version \(current) is already the newest release on this channel."))
                }
                return
            }

            guard let asset = release.preferredDMGAsset else {
                if !silent {
                    showMessage(AppFlavor.text("发现新版本 \(release.tagName)", "New Version Found \(release.tagName)"),
                                AppFlavor.text("但这个 Release 里没有找到适合当前 Mac 的 DMG 安装包。", "This release does not include a DMG installer for this Mac."))
                }
                return
            }

            promptForUpdate(release: release, asset: asset)
        } catch {
            if !silent { showMessage(AppFlavor.text("检查更新失败", "Update Check Failed"), error.localizedDescription) }
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let releases: [GitHubRelease] = try await fetch("https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=30")
        guard let release = releases.first(where: { $0.isUsableForCurrentFlavor }) else {
            throw UpdaterError.noUsableRelease
        }
        return release
    }

    private func fetch<T: Decodable>(_ rawURL: String) async throws -> T {
        let url = URL(string: rawURL)!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ListenMark", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdaterError.badResponse
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func promptForUpdate(release: GitHubRelease, asset: GitHubAsset) {
        let size = ByteCountFormatter.string(fromByteCount: Int64(asset.size), countStyle: .file)
        let alert = NSAlert()
        alert.messageText = AppFlavor.text("发现新版本 \(release.tagName)", "New Version Found \(release.tagName)")
        alert.informativeText = AppFlavor.text(
            """
            当前版本：\(currentVersion)
            安装包：\(asset.name)（\(size)）

            下载后会先验证安装包，然后自动替换当前 App 并重新打开。若系统权限不允许自动安装，会打开 DMG 让你手动拖拽更新。
            """,
            """
            Current version: \(currentVersion)
            Installer: \(asset.name) (\(size))

            After download, the installer is verified, the current app is replaced, and ListenMark reopens. If macOS permissions prevent automatic install, the DMG opens for manual update.
            """
        )
        alert.addButton(withTitle: AppFlavor.text("下载并安装", "Download and Install"))
        alert.addButton(withTitle: AppFlavor.text("查看发布页", "View Release Page"))
        alert.addButton(withTitle: AppFlavor.text("稍后", "Later"))
        NSApp.activate(ignoringOtherApps: true)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            downloadAndInstall(release: release, asset: asset)
        case .alertSecondButtonReturn:
            if let url = URL(string: release.htmlURL) { NSWorkspace.shared.open(url) }
        default:
            break
        }
    }

    private func downloadAndInstall(release: GitHubRelease, asset: GitHubAsset) {
        guard !isDownloading else { return }
        isDownloading = true

        Task {
            defer { isDownloading = false }
            var destination: URL?
            do {
                destination = try await download(asset)
                try installDownloadedDMG(destination!, release: release)
            } catch {
                if let destination {
                    NSWorkspace.shared.open(destination)
                    showMessage(AppFlavor.text("自动安装失败，已打开 DMG", "Automatic Install Failed; DMG Opened"),
                                error.localizedDescription)
                } else {
                    showMessage(AppFlavor.text("下载更新失败", "Update Download Failed"), error.localizedDescription)
                }
            }
        }
    }

    private func download(_ asset: GitHubAsset) async throws -> URL {
        guard let url = URL(string: asset.downloadURL) else { throw UpdaterError.badDownloadURL }
        var request = URLRequest(url: url)
        request.setValue("ListenMark", forHTTPHeaderField: "User-Agent")

        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdaterError.badResponse
        }

        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let destination = downloads.appendingPathComponent(asset.name)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func installDownloadedDMG(_ dmgURL: URL, release: GitHubRelease) throws {
        let currentApp = Bundle.main.bundleURL
        guard currentApp.pathExtension == "app" else {
            throw UpdaterError.notRunningFromAppBundle
        }

        let installParent = currentApp.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: installParent.path) else {
            throw UpdaterError.installLocationNotWritable(installParent.path)
        }

        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("listenmark-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        var mounted = false
        var handedOff = false
        do {
            _ = try runTool("/usr/bin/hdiutil", ["attach", dmgURL.path, "-readonly", "-nobrowse", "-mountpoint", mountPoint.path])
            mounted = true

            let candidate = try findAppBundle(in: mountPoint)
            try validateCandidateApp(candidate, expectedVersion: release.cleanVersion)
            try launchInstaller(candidateApp: candidate, targetApp: currentApp, mountPoint: mountPoint)
            handedOff = true
            NSApp.terminate(nil)
        } catch {
            if mounted && !handedOff {
                _ = try? runTool("/usr/bin/hdiutil", ["detach", mountPoint.path])
            }
            if !mounted {
                try? FileManager.default.removeItem(at: mountPoint)
            }
            throw error
        }
    }

    private func findAppBundle(in mountPoint: URL) throws -> URL {
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        guard let enumerator = FileManager.default.enumerator(at: mountPoint, includingPropertiesForKeys: nil, options: options) else {
            throw UpdaterError.noAppInDMG
        }

        for case let url as URL in enumerator where url.pathExtension == "app" {
            return url
        }
        throw UpdaterError.noAppInDMG
    }

    private func validateCandidateApp(_ appURL: URL, expectedVersion: String) throws {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any] else {
            throw UpdaterError.badAppBundle
        }

        let bundleID = info["CFBundleIdentifier"] as? String
        guard bundleID == AppFlavor.bundleIdentifier else {
            throw UpdaterError.bundleMismatch(bundleID ?? AppFlavor.text("未知", "unknown"))
        }

        let flavor = info["LMAppFlavor"] as? String
        guard flavor == AppFlavor.rawValue else {
            throw UpdaterError.flavorMismatch(flavor ?? AppFlavor.text("未知", "unknown"))
        }

        let version = info["CFBundleShortVersionString"] as? String ?? ""
        guard Self.compare(version, currentVersion) == .orderedDescending,
              Self.compare(version, expectedVersion) == .orderedSame else {
            throw UpdaterError.versionMismatch(version)
        }

        _ = try runTool("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path])
        _ = try runTool("/usr/sbin/spctl", ["-a", "-t", "exec", "-vvv", appURL.path])
    }

    private func launchInstaller(candidateApp: URL, targetApp: URL, mountPoint: URL) throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("listenmark-install-\(UUID().uuidString).zsh")
        let script = """
        #!/bin/zsh
        set -euo pipefail

        pid="$1"
        source_app="$2"
        target_app="$3"
        mount_point="$4"
        log_dir="$HOME/Library/Logs"
        log_file="$log_dir/ListenMark-Updater.log"

        mkdir -p "$log_dir"
        exec >> "$log_file" 2>&1

        while kill -0 "$pid" 2>/dev/null; do
          sleep 0.2
        done

        tmp_app="${target_app}.updating.$$"
        backup_app="${target_app}.previous.$$"
        rm -rf "$tmp_app" "$backup_app"

        /usr/bin/ditto "$source_app" "$tmp_app"

        if [[ -e "$target_app" ]]; then
          /bin/mv "$target_app" "$backup_app"
        fi

        if /bin/mv "$tmp_app" "$target_app"; then
          rm -rf "$backup_app"
          /usr/bin/hdiutil detach "$mount_point" >/dev/null 2>&1 || true
          /usr/bin/open "$target_app"
          exit 0
        fi

        if [[ -e "$backup_app" ]]; then
          /bin/mv "$backup_app" "$target_app"
        fi
        /usr/bin/hdiutil detach "$mount_point" >/dev/null 2>&1 || true
        exit 1
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            scriptURL.path,
            "\(ProcessInfo.processInfo.processIdentifier)",
            candidateApp.path,
            targetApp.path,
            mountPoint.path
        ]
        try process.run()
    }

    @discardableResult
    private func runTool(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw UpdaterError.toolFailed(URL(fileURLWithPath: path).lastPathComponent, output)
        }
        return output
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private func showMessage(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: AppFlavor.text("好", "OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let l = versionParts(lhs)
        let r = versionParts(rhs)
        let count = max(l.count, r.count)
        for i in 0..<count {
            let lv = i < l.count ? l[i] : 0
            let rv = i < r.count ? r[i] : 0
            if lv > rv { return .orderedDescending }
            if lv < rv { return .orderedAscending }
        }
        return .orderedSame
    }

    private static func versionParts(_ value: String) -> [Int] {
        let core = value.split(separator: "-", maxSplits: 1).first.map(String.init) ?? value
        return core
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split { !$0.isNumber }
            .prefix(3)
            .compactMap { Int($0) }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }

    var cleanVersion: String {
        var value = tagName
        if value.hasPrefix(AppFlavor.releaseTagPrefix) {
            value.removeFirst(AppFlavor.releaseTagPrefix.count)
            return value
        }
        return tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    var isUsableForCurrentFlavor: Bool {
        guard !draft else { return false }
        if AppFlavor.isInternational {
            return tagName.hasPrefix(AppFlavor.releaseTagPrefix)
        }
        return !prerelease && tagName.hasPrefix(AppFlavor.releaseTagPrefix)
    }

    var preferredDMGAsset: GitHubAsset? {
        let dmgs = assets.filter { $0.isDMGForCurrentFlavor }
        let arch = Hardware.currentReleaseArch
        return dmgs.first { $0.name.lowercased().contains(arch) } ?? dmgs.first
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let size: Int
    let downloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case downloadURL = "browser_download_url"
    }

    var isDMGForCurrentFlavor: Bool {
        let normalized = name.lowercased()
        guard normalized.hasSuffix(".dmg") else { return false }
        if AppFlavor.isInternational {
            return normalized.contains("international")
        }
        return !normalized.contains("international")
    }
}

private enum Hardware {
    static var currentReleaseArch: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
}

private enum UpdaterError: LocalizedError {
    case noUsableRelease
    case badResponse
    case badDownloadURL
    case notRunningFromAppBundle
    case installLocationNotWritable(String)
    case noAppInDMG
    case badAppBundle
    case bundleMismatch(String)
    case flavorMismatch(String)
    case versionMismatch(String)
    case toolFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .noUsableRelease:
            return AppFlavor.text("当前发布通道没有可用的 GitHub Release。", "No usable GitHub release exists on the current channel.")
        case .badResponse:
            return AppFlavor.text("GitHub 返回了无法使用的响应。", "GitHub returned an unusable response.")
        case .badDownloadURL:
            return AppFlavor.text("GitHub Release 资产缺少有效下载地址。", "The GitHub release asset is missing a valid download URL.")
        case .notRunningFromAppBundle:
            return AppFlavor.text("当前不是从 .app 包运行，无法自动替换。", "The app is not currently running from an .app bundle, so it cannot be replaced automatically.")
        case .installLocationNotWritable(let path):
            return AppFlavor.text("当前安装位置不可写：\(path)。请在打开的 DMG 中手动拖拽安装。", "The current install location is not writable: \(path). Please update manually from the opened DMG.")
        case .noAppInDMG:
            return AppFlavor.text("DMG 中没有找到可安装的 App。", "No installable app was found in the DMG.")
        case .badAppBundle:
            return AppFlavor.text("安装包里的 App 结构不完整。", "The app inside the installer is incomplete.")
        case .bundleMismatch(let found):
            return AppFlavor.text("安装包 bundle id 不匹配：\(found)。为避免中英文版串线，已停止自动安装。", "Installer bundle id does not match: \(found). Automatic install stopped to avoid crossing editions.")
        case .flavorMismatch(let found):
            return AppFlavor.text("安装包版本类型不匹配：\(found)。为避免中英文版串线，已停止自动安装。", "Installer flavor does not match: \(found). Automatic install stopped to avoid crossing editions.")
        case .versionMismatch(let found):
            return AppFlavor.text("安装包版本不符合预期：\(found)。", "Installer version is not the expected update: \(found).")
        case .toolFailed(let tool, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return AppFlavor.text("\(tool) 验证失败：\(detail)", "\(tool) validation failed: \(detail)")
        }
    }
}
