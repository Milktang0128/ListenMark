import SwiftUI

/// 今日回响 — passively resurfaces archived items on a spaced schedule and reads
/// them aloud again, so "听过的" becomes "记住的". No notifications; you come here.
struct ReviewView: View {
    @ObservedObject private var store = ArchiveStore.shared
    @ObservedObject private var speaker = Speaker.shared
    @State private var items: [Entry] = []
    @State private var reviewed: Set<UUID> = []
    @State private var playbackTarget: ReviewPlaybackTarget?

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
                                       isActive: isActive(entry),
                                       isPaused: isPaused(entry),
                                       isPreparing: isPreparing(entry),
                                       onPlay: { play(entry) },
                                       onPause: { Speaker.shared.pause() },
                                       onResume: { Speaker.shared.resume() },
                                       onStop: { stopPlayback() },
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
        .onChange(of: speaker.status) { _, status in
            if case .idle = status {
                playbackTarget = nil
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppFlavor.text("今日回响", "Review")).font(.system(size: 17, weight: .semibold))
                Text(items.isEmpty ? AppFlavor.text("把听过的内容再过一遍耳朵", "Replay what you have saved") : AppFlavor.text("把这 \(items.count) 条再过一遍耳朵", "Replay these \(items.count) items"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if !items.isEmpty {
                HStack(spacing: 8) {
                    Button {
                        handleAllPlaybackButton()
                    } label: {
                        Label(allPlaybackTitle, systemImage: allPlaybackIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(speaker.isPreparing)

                    if allIsActive {
                        Button { stopPlayback() } label: {
                            Label(AppFlavor.text("停止", "Stop"), systemImage: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
            }
        }
        .padding(14)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle").font(.system(size: 32)).foregroundStyle(.green.opacity(0.7))
            Text(store.entries.isEmpty ? AppFlavor.text("还没有可回响的内容\n先去听点东西、留个档", "Nothing to review yet\nSave something after listening") : AppFlavor.text("今天没有需要回响的内容", "Nothing due today"))
                .multilineTextAlignment(.center).font(.system(size: 13)).foregroundStyle(.secondary)
            if !store.entries.isEmpty {
                Button(AppFlavor.text("现在回响最旧的几条", "Review Oldest Now")) { items = store.oldestForReview() }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func play(_ entry: Entry) {
        Speaker.shared.speak(entry.response ?? entry.original)
        playbackTarget = .entry(entry.id)
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
        playbackTarget = .all
    }

    private func stopPlayback() {
        Speaker.shared.stop()
        playbackTarget = nil
    }

    private func handleAllPlaybackButton() {
        if playbackTarget == .all && speaker.isPlaying {
            Speaker.shared.pause()
        } else if playbackTarget == .all && speaker.isPaused {
            Speaker.shared.resume()
        } else if !speaker.isPreparing {
            playAll()
        }
    }

    private var allIsActive: Bool {
        playbackTarget == .all && !speaker.isIdle
    }

    private var allPlaybackTitle: String {
        if allIsActive && speaker.isPlaying { return AppFlavor.text("暂停", "Pause") }
        if allIsActive && speaker.isPaused { return AppFlavor.text("继续", "Resume") }
        if allIsActive && speaker.isPreparing { return AppFlavor.text("准备中", "Preparing") }
        return AppFlavor.text("全部回响", "Play All")
    }

    private var allPlaybackIcon: String {
        if allIsActive && speaker.isPlaying { return "pause.fill" }
        if allIsActive && speaker.isPaused { return "play.fill" }
        if allIsActive && speaker.isPreparing { return "hourglass" }
        return "play.circle.fill"
    }

    private func isActive(_ entry: Entry) -> Bool {
        playbackTarget == .entry(entry.id) && !speaker.isIdle
    }

    private func isPaused(_ entry: Entry) -> Bool {
        playbackTarget == .entry(entry.id) && speaker.isPaused
    }

    private func isPreparing(_ entry: Entry) -> Bool {
        playbackTarget == .entry(entry.id) && speaker.isPreparing
    }
}

private enum ReviewPlaybackTarget: Equatable {
    case all
    case entry(UUID)
}

private struct ReviewCard: View {
    let entry: Entry
    let done: Bool
    let isActive: Bool
    let isPaused: Bool
    let isPreparing: Bool
    let onPlay: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onStop: () -> Void
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
                    Label(AppFlavor.text("已回响", "Reviewed"), systemImage: "checkmark.circle.fill")
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
                Button { handlePlaybackButton() } label: {
                    Label(playbackTitle, systemImage: playbackIcon)
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPreparing)
                if isActive {
                    Button { onStop() } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .help(AppFlavor.text("停止并重置", "Stop and Reset"))
                }
                Button { onMaster() } label: { Label(AppFlavor.text("已掌握", "Mastered"), systemImage: "checkmark.seal") }
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

    private func handlePlaybackButton() {
        if !isActive {
            onPlay()
        } else if isPaused {
            onResume()
        } else if !isPreparing {
            onPause()
        }
    }

    private var playbackTitle: String {
        if isPreparing { return AppFlavor.text("准备中", "Preparing") }
        if isPaused { return AppFlavor.text("继续", "Resume") }
        if isActive { return AppFlavor.text("暂停", "Pause") }
        return AppFlavor.text("重听", "Replay")
    }

    private var playbackIcon: String {
        if isPreparing { return "hourglass" }
        if isPaused { return "play.fill" }
        if isActive { return "pause.fill" }
        return "play.fill"
    }
}
