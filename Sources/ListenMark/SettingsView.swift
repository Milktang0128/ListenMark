import SwiftUI
import AVFoundation

struct SettingsView: View {
    @AppStorage("autoPop") private var autoPop = true
    @AppStorage("hkDisplay") private var hkDisplay = "⌥⌘R"
    @AppStorage("autoArchive") private var autoArchive = false
    @AppStorage("archiveFolder") private var archiveFolder = ""

    @AppStorage("deepseekKey") private var deepseekKey = ""
    @AppStorage("deepseekModel") private var deepseekModel = "deepseek-v4-flash"

    @AppStorage("ttsEngine") private var ttsEngine = "volcano"
    @AppStorage("volcAppId") private var volcAppId = ""
    @AppStorage("volcToken") private var volcToken = ""
    @AppStorage("volcCluster") private var volcCluster = "volcano_tts"
    @AppStorage("volcVoice") private var volcVoice = "zh_female_cancan_uranus_bigtts"
    @AppStorage("volcSpeed") private var volcSpeed = 1.0
    @AppStorage("rate") private var rate = Double(AVSpeechUtteranceDefaultSpeechRate)

    private var volcUnconfigured: Bool {
        ttsEngine == "volcano" && (volcAppId.isEmpty || volcToken.isEmpty)
    }

    var body: some View {
        Form {
            Section("触发方式") {
                Toggle("划词后自动弹出（推荐）", isOn: $autoPop)
                    .onChange(of: autoPop) { _, _ in
                        NotificationCenter.default.post(name: .gebwConfigChanged, object: nil)
                    }
                HStack {
                    Text("全局快捷键")
                    Spacer()
                    HotkeyRecorder(display: $hkDisplay) { code, mods, disp in
                        Settings.hotKeyCode = Int(code)
                        Settings.hotKeyMods = carbonModifiers(mods)
                        Settings.hotKeyDisplay = disp
                        hkDisplay = disp
                        NotificationCenter.default.post(name: .gebwConfigChanged, object: nil)
                    }
                    .frame(width: 150, height: 22)
                }
            }

            Section("留档") {
                Toggle("自动留档（每次动作都保存）", isOn: $autoArchive)
                Text("默认关闭——结果卡上点「留档」才保存。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("留存位置（可读 Markdown）") {
                HStack {
                    Text(archiveFolder.isEmpty ? "默认（应用支持目录）" : archiveFolder)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("选择…") { pickFolder() }
                }
                HStack {
                    Button("在访达中显示") { NSWorkspace.shared.open(ArchiveStore.shared.revealFolder) }
                    if !archiveFolder.isEmpty {
                        Button("用默认") { archiveFolder = ""; ArchiveStore.shared.relocate() }
                    }
                }
                Text("可读的「ListenMark.md」会写到这里——放进 Obsidian 库即可随时查看、供后续 agent 管理。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("技能") {
                Text("在 菜单栏 👂 → 编辑技能… 里排序、禁用、或新增最多 4 个自定义技能（自定义提示词）。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("解释 / 翻译模型（DeepSeek）") {
                SecureField("DeepSeek API Key（sk-…）", text: $deepseekKey)
                TextField("模型", text: $deepseekModel)
                Text("默认 deepseek-v4-flash（快）；也可填 deepseek-chat / deepseek-reasoner。")
                    .font(.caption).foregroundStyle(.secondary)
                Link("前往 DeepSeek 获取 API Key ↗", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                    .font(.caption)
            }

            Section("语音合成") {
                Picker("引擎", selection: $ttsEngine) {
                    Text("火山引擎 · 推荐").tag("volcano")
                    Text("本地（macOS）").tag("local")
                }
                .pickerStyle(.segmented)

                if ttsEngine == "volcano" {
                    Link("没有账号？前往火山引擎语音控制台开通、获取 App ID / Token ↗",
                         destination: URL(string: "https://console.volcengine.com/speech/app")!)
                        .font(.caption)
                    SecureField("App ID", text: $volcAppId)
                    SecureField("Access Token", text: $volcToken)
                    Picker("音色", selection: $volcVoice) {
                        ForEach(VolcanoVoices.all) { voice in
                            Text(voice.name).tag(voice.id)
                        }
                        if !VolcanoVoices.all.contains(where: { $0.id == volcVoice }) {
                            Text("自定义（\(volcVoice)）").tag(volcVoice)
                        }
                    }
                    TextField("自定义 voice_type（可选）", text: $volcVoice)
                    TextField("Cluster", text: $volcCluster)
                    HStack {
                        Text("语速")
                        Slider(value: $volcSpeed, in: 0.5...2.0)
                        Text(String(format: "%.1fx", volcSpeed)).font(.caption).foregroundStyle(.secondary)
                    }
                    if volcUnconfigured {
                        Text("未填 App ID / Access Token，暂时回退本地语音。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Text("音色需在火山控制台开通；下拉为常用大模型音色，也可手填任意 voice_type。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text("本地语速")
                        Slider(value: $rate, in: 0.3...0.7)
                    }
                }

                Button("试听") {
                    Settings.speechRate = Float(rate)
                    Speaker.shared.speak("ListenMark，这是当前语音的试听效果。")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 470, height: 620)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            archiveFolder = url.path
            ArchiveStore.shared.relocate()
        }
    }
}
