import AVFoundation

/// Voice-first output with streaming support.
/// - One-shot `speak` for replay / 试听.
/// - `startStream` → `feed(sentence)` × N → `endStream` for speaking as text arrives.
/// Local engine queues utterances natively; 火山 synthesizes each sentence and
/// plays them back-to-back through a serial audio queue. 火山 failure falls back
/// to the local voice.
final class Speaker: NSObject, AVAudioPlayerDelegate {
    static let shared = Speaker()

    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?

    private var streaming = false
    private var volcQueue: [String] = []
    private var volcDraining = false
    private var onFinishPlay: (() -> Void)?

    private var useVolcano: Bool { Settings.ttsEngine == "volcano" && Settings.volcConfigured }

    // MARK: One-shot

    func speak(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        stop()
        if useVolcano {
            Task { [weak self] in
                do {
                    let data = try await VolcanoTTS.synthesize(t)
                    guard let self else { return }
                    await MainActor.run { self.playThen(data) {} }
                } catch {
                    NSLog("ListenMark · 火山 TTS 失败，回退本地语音：\(error)")
                    guard let self else { return }
                    await MainActor.run { self.localSpeak(t) }
                }
            }
        } else {
            localSpeak(t)
        }
    }

    // MARK: Streaming

    func startStream() {
        stop()
        streaming = true
    }

    func feed(_ sentence: String) {
        let s = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard streaming, !s.isEmpty else { return }
        if useVolcano {
            volcQueue.append(s)
            startDrainIfNeeded()
        } else {
            synth.speak(utterance(for: s))   // AVSpeechSynthesizer queues
        }
    }

    func endStream() { streaming = false }

    // MARK: Stop

    func stop() {
        streaming = false
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        player?.stop(); player = nil
        volcQueue.removeAll()
        volcDraining = false
        onFinishPlay = nil
    }

    // MARK: Internals

    private func utterance(for t: String) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: t)
        u.voice = AVSpeechSynthesisVoice(language: t.containsCJK ? "zh-CN" : "en-US")
        u.rate = Settings.speechRate
        return u
    }

    private func localSpeak(_ t: String) { synth.speak(utterance(for: t)) }

    private func startDrainIfNeeded() {
        guard !volcDraining else { return }
        volcDraining = true
        drainNext()
    }

    private func drainNext() {
        guard !volcQueue.isEmpty else { volcDraining = false; return }
        let next = volcQueue.removeFirst()
        Task { [weak self] in
            do {
                let data = try await VolcanoTTS.synthesize(next)
                guard let self else { return }
                await MainActor.run { self.playThen(data) { [weak self] in self?.drainNext() } }
            } catch {
                NSLog("ListenMark · 火山 TTS 失败，回退本地语音：\(error)")
                guard let self else { return }
                await MainActor.run { self.localSpeak(next); self.drainNext() }
            }
        }
    }

    private func playThen(_ data: Data, _ done: @escaping () -> Void) {
        do {
            let p = try AVAudioPlayer(data: data)
            p.delegate = self
            player = p
            onFinishPlay = done
            p.play()
        } catch {
            NSLog("ListenMark · 音频播放失败：\(error)")
            done()
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let done = onFinishPlay
        onFinishPlay = nil
        done?()
    }
}
