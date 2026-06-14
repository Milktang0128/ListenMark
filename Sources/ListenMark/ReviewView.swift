import SwiftUI

/// 今日回响 — passively resurfaces archived items on a spaced schedule and reads
/// them aloud again, so "听过的" becomes "记住的". No notifications; you come here.
struct ReviewView: View {
    @ObservedObject private var store = ArchiveStore.shared
    @State private var items: [Entry] = []
    @State private var reviewed: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if items.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { entry in
                            ReviewCard(entry: entry,
                                       done: reviewed.contains(entry.id),
                                       onPlay: { play(entry) },
                                       onMaster: { master(entry) })
                        }
                    }
                    .padding(14)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 480, minHeight: 520)
        .onAppear { items = store.dueForReview() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("今日回响").font(.system(size: 17, weight: .semibold))
                Text(items.isEmpty ? "把听过的内容再过一遍耳朵" : "把这 \(items.count) 条再过一遍耳朵")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if !items.isEmpty {
                Button { playAll() } label: { Label("全部回响", systemImage: "play.circle.fill") }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle").font(.system(size: 32)).foregroundStyle(.green.opacity(0.7))
            Text(store.entries.isEmpty ? "还没有可回响的内容\n先去听点东西、留个档" : "今天没有需要回响的内容 🎉")
                .multilineTextAlignment(.center).font(.system(size: 13)).foregroundStyle(.secondary)
            if !store.entries.isEmpty {
                Button("现在回响最旧的几条") { items = store.oldestForReview() }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func play(_ entry: Entry) {
        Speaker.shared.speak(entry.response ?? entry.original)
        store.markReviewed(entry.id)
        reviewed.insert(entry.id)
    }

    private func master(_ entry: Entry) {
        store.setMastered(entry.id, true)
        withAnimation { items.removeAll { $0.id == entry.id } }
    }

    private func playAll() {
        Speaker.shared.startStream()
        for entry in items {
            Speaker.shared.feed(entry.response ?? entry.original)
            store.markReviewed(entry.id)
            reviewed.insert(entry.id)
        }
        Speaker.shared.endStream()
    }
}

private struct ReviewCard: View {
    let entry: Entry
    let done: Bool
    let onPlay: () -> Void
    let onMaster: () -> Void
    @State private var hover = false

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM-dd"; return f
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
                if done {
                    Label("已回响", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10)).foregroundStyle(.green)
                }
                Spacer()
            }

            Text(entry.original)
                .font(.system(size: 13))
                .foregroundStyle(entry.response == nil ? .primary : .secondary)
                .lineLimit(2)
            if let r = entry.response, !r.isEmpty {
                Text(r).font(.system(size: 13)).lineLimit(5)
            }

            HStack(spacing: 8) {
                Button { onPlay() } label: { Label("重听", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                Button { onMaster() } label: { Label("已掌握", systemImage: "checkmark.seal") }
                    .buttonStyle(.bordered).tint(.green)
                Spacer()
            }
            .controlSize(.small)
            .buttonBorderShape(.capsule)
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(hover ? 0.12 : 0.06), lineWidth: 0.5)
        )
        .opacity(done ? 0.7 : 1)
        .onHover { hover = $0 }
    }
}
