import Foundation
import Combine

/// The product's spine: interactions persist as JSON (source of truth, kept
/// internally) plus a human-readable Markdown file the user can point at any
/// folder — e.g. an Obsidian vault — so it's always viewable and agent-managed.
final class ArchiveStore: ObservableObject {
    static let shared = ArchiveStore()

    @Published private(set) var entries: [Entry] = []

    private let jsonURL: URL
    let internalFolder: URL

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ListenMark", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        internalFolder = base
        jsonURL = base.appendingPathComponent("archive.json")
        load()
    }

    /// Where the readable Markdown lives — user's folder if set, else internal.
    var markdownURL: URL {
        let folder = Settings.archiveFolder
        if !folder.isEmpty {
            return URL(fileURLWithPath: folder, isDirectory: true).appendingPathComponent("ListenMark.md")
        }
        return internalFolder.appendingPathComponent("ListenMark.md")
    }

    var revealFolder: URL {
        let folder = Settings.archiveFolder
        return folder.isEmpty ? internalFolder : URL(fileURLWithPath: folder, isDirectory: true)
    }

    func load() {
        guard let data = try? Data(contentsOf: jsonURL),
              let list = try? JSONDecoder.iso.decode([Entry].self, from: data) else { return }
        entries = list
    }

    func add(_ entry: Entry) {
        entries.insert(entry, at: 0)
        save()
    }

    func delete(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    /// Re-export to a (possibly newly chosen) Markdown location.
    func relocate() { exportMarkdown() }

    // MARK: 今日回响 (spaced review)

    func dueForReview(limit: Int = 8, now: Date = Date()) -> [Entry] {
        Array(entries.filter { ReviewSchedule.isDue($0, now: now) }
            .sorted { ReviewSchedule.base($0) < ReviewSchedule.base($1) }
            .prefix(limit))
    }

    func oldestForReview(limit: Int = 8) -> [Entry] {
        Array(entries.filter { $0.mastered != true }
            .sorted { ReviewSchedule.base($0) < ReviewSchedule.base($1) }
            .prefix(limit))
    }

    var dueCount: Int { entries.filter { ReviewSchedule.isDue($0, now: Date()) }.count }

    func markReviewed(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].reviewCount = (entries[i].reviewCount ?? 0) + 1
        entries[i].lastReviewed = Date()
        save()
    }

    func setMastered(_ id: UUID, _ on: Bool) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].mastered = on
        save()
    }

    func resetReview(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].reviewCount = 0
        entries[i].lastReviewed = nil
        entries[i].mastered = false
        save()
    }

    private func save() {
        if let data = try? JSONEncoder.iso.encode(entries) {
            try? data.write(to: jsonURL, options: .atomic)
        }
        exportMarkdown()
    }

    private func exportMarkdown() {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        var md = "# ListenMark · 档案\n\n"
        for e in entries {
            md += "## \(e.action) · \(df.string(from: e.date)) · \(e.sourceApp)\n\n"
            md += "> \(e.original.replacingOccurrences(of: "\n", with: "\n> "))\n\n"
            if let r = e.response, !r.isEmpty { md += "\(r)\n\n" }
            md += "---\n\n"
        }
        let url = markdownURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? md.write(to: url, atomically: true, encoding: .utf8)
    }
}
