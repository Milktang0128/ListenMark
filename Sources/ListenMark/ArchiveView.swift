import SwiftUI

func actionTint(_ name: String) -> Color {
    switch name {
    case "朗读": return .blue
    case "解释": return .orange
    case "翻译": return .green
    case "提炼": return .purple
    case "背景": return .pink
    default: return .teal
    }
}

/// The "回看" surface — sidebar (filter by action) + searchable card list.
struct ArchiveView: View {
    @ObservedObject private var store = ArchiveStore.shared
    @ObservedObject private var actions = ActionStore.shared
    @State private var query = ""
    @State private var filter: Filter? = .all

    enum Filter: Hashable { case all; case action(String) }

    private var base: [Entry] {
        switch filter ?? .all {
        case .all: return store.entries
        case .action(let name): return store.entries.filter { $0.action == name }
        }
    }

    private var filtered: [Entry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.original.localizedCaseInsensitiveContains(q) ||
            ($0.response ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    private func count(_ name: String) -> Int { store.entries.filter { $0.action == name }.count }

    var body: some View {
        NavigationSplitView {
            List(selection: $filter) {
                Section("资源库") {
                    Label("全部记录", systemImage: "tray.full")
                        .badge(store.entries.count)
                        .tag(Filter.all)
                }
                Section("按动作") {
                    ForEach(actions.actions) { def in
                        HStack(spacing: 9) {
                            Circle().fill(actionTint(def.name)).frame(width: 8, height: 8)
                            Text(def.name)
                        }
                        .badge(count(def.name))
                        .tag(Filter.action(def.name))
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detail
        }
        .navigationTitle("档案")
    }

    private var detail: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                    TextField("搜索原文或 AI 回应…", text: $query)
                        .textFieldStyle(.plain).font(.system(size: 13))
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))

                Text("\(filtered.count) 条").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(14)
            Divider()

            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: store.entries.isEmpty ? "ear" : "magnifyingglass")
                        .font(.system(size: 30)).foregroundStyle(.tertiary)
                    Text(store.entries.isEmpty ? "还没有记录\n选中文本，处理后点「留档」" : "没有匹配的记录")
                        .multilineTextAlignment(.center)
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { EntryCard(entry: $0) }
                    }
                    .padding(14)
                }
            }
        }
    }
}

private struct EntryCard: View {
    let entry: Entry
    @ObservedObject private var store = ArchiveStore.shared
    @State private var hover = false

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    var body: some View {
        let tint = actionTint(entry.action)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: entry.icon ?? "text.bubble").font(.system(size: 10))
                    Text(entry.action).font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(tint.opacity(0.14)))

                Text(entry.sourceApp).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(Self.df.string(from: entry.date)).font(.system(size: 11)).foregroundStyle(.tertiary)
                Spacer()
                Button { Speaker.shared.speak(entry.response ?? entry.original) } label: {
                    Image(systemName: "play.circle").font(.system(size: 15))
                }.buttonStyle(.plain).foregroundStyle(hover ? .primary : .secondary).help("重听")
                Button { store.delete(entry) } label: {
                    Image(systemName: "trash").font(.system(size: 13))
                }.buttonStyle(.plain).foregroundStyle(hover ? .secondary : .tertiary).help("删除")
            }

            Text(entry.original)
                .font(.system(size: 13))
                .foregroundStyle(entry.response == nil ? .primary : .secondary)
                .lineLimit(3)

            if let r = entry.response, !r.isEmpty {
                Text(r).font(.system(size: 13)).lineLimit(8).textSelection(.enabled)
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(hover ? 0.12 : 0.06), lineWidth: 0.5)
        )
        .onHover { hover = $0 }
    }
}
