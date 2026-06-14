import SwiftUI
import AVFoundation

struct SettingsView: View {
    private static var volcanoVoiceListURL: URL {
        URL(string: AppFlavor.text("https://www.volcengine.com/docs/6561/1257544?lang=zh",
                                   "https://www.volcengine.com/docs/6561/1257544"))!
    }

    @AppStorage("autoPop") private var autoPop = true
    @AppStorage("hkDisplay") private var hkDisplay = "⌥⌘R"
    @AppStorage("ocrHkDisplay") private var ocrHkDisplay = "⌃⇧O"
    @AppStorage("autoArchive") private var autoArchive = false
    @AppStorage("archiveFolder") private var archiveFolder = ""

    @AppStorage("llmBaseURL") private var llmBaseURL = Settings.recommendedLLMBaseURL
    @AppStorage("deepseekKey") private var llmAPIKey = ""
    @AppStorage("deepseekModel") private var llmModel = Settings.recommendedLLMModel
    @AppStorage("useFullContext") private var useFullContext = true

    @AppStorage("ttsEngine") private var ttsEngine = AppFlavor.text("volcano", "local")
    @AppStorage("volcAppId") private var volcAppId = ""
    @AppStorage("volcToken") private var volcToken = ""
    @AppStorage("volcCluster") private var volcCluster = "volcano_tts"
    @AppStorage("volcVoice") private var volcVoice = AppFlavor.text("zh_female_cancan_uranus_bigtts", "en_female_dacey_uranus_bigtts")
    @AppStorage("volcSpeed") private var volcSpeed = 1.0
    @AppStorage("rate") private var rate = Double(AVSpeechUtteranceDefaultSpeechRate)

    private var volcUnconfigured: Bool {
        ttsEngine == "volcano" && (volcAppId.isEmpty || volcToken.isEmpty)
    }

    var body: some View {
        Form {
            Section(AppFlavor.text("触发方式", "Triggers")) {
                Toggle(AppFlavor.text("划词后自动弹出（推荐）", "Show panel after text selection (recommended)"), isOn: $autoPop)
                    .onChange(of: autoPop) { _, _ in
                        NotificationCenter.default.post(name: .gebwConfigChanged, object: nil)
                    }
                HStack {
                    Text(AppFlavor.text("弹出面板快捷键", "Panel hotkey"))
                    Spacer()
                    HotkeyRecorder(display: $hkDisplay) { code, mods, disp in
                        Settings.hotKeyCode = Int(code)
                        Settings.hotKeyMods = carbonModifiers(mods)
                        Settings.hotKeyDisplay = disp
                        hkDisplay = disp
                        NotificationCenter.default.post(name: .gebwConfigChanged, object: nil)
                    }
                    .frame(width: 176, height: 22)
                }
            }

            Section(AppFlavor.text("高级取词", "Fallback Capture")) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppFlavor.text("屏幕选框 OCR", "Screen selection OCR"))
                        Text(AppFlavor.text("无法直接取词时，按快捷键框选屏幕区域，识别出的文字会进入同一个处理面板。", "When direct text capture fails, press the hotkey and drag a screen region. Recognized text opens in the same action panel."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HotkeyRecorder(display: $ocrHkDisplay) { code, mods, disp in
                        Settings.ocrHotKeyCode = Int(code)
                        Settings.ocrHotKeyMods = carbonModifiers(mods)
                        Settings.ocrHotKeyDisplay = disp
                        ocrHkDisplay = disp
                        NotificationCenter.default.post(name: .gebwConfigChanged, object: nil)
                    }
                    .frame(width: 176, height: 22)
                }
            }

            Section(AppFlavor.text("留档", "Saving")) {
                Toggle(AppFlavor.text("自动留档（每次动作都保存）", "Auto-save every action"), isOn: $autoArchive)
                Text(AppFlavor.text("默认关闭——结果卡上点「留档」才保存。", "Off by default. Use Save on the result card when you want to keep something."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(AppFlavor.text("留存位置（可读 Markdown）", "Archive Location (Readable Markdown)")) {
                HStack {
                    Text(archiveFolder.isEmpty ? AppFlavor.text("默认（应用支持目录）", "Default (Application Support)") : archiveFolder)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(AppFlavor.text("选择…", "Choose…")) { pickFolder() }
                }
                HStack {
                    Button(AppFlavor.text("在访达中显示", "Show in Finder")) { NSWorkspace.shared.open(ArchiveStore.shared.revealFolder) }
                    if !archiveFolder.isEmpty {
                        Button(AppFlavor.text("用默认", "Use Default")) { archiveFolder = ""; ArchiveStore.shared.relocate() }
                    }
                }
                Text(AppFlavor.text("可读的档案 Markdown 会写到这里——放进 Obsidian 库即可随时查看、供后续 agent 管理。", "Readable Markdown is written here, so you can keep it in Obsidian or any folder you want to review later."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(AppFlavor.text("技能", "Actions")) {
                HStack {
                    Text(AppFlavor.text("排序、设置快捷键、禁用、或新增最多 4 个自定义技能。技能快捷键会直接处理当前选中文本。", "Reorder, set hotkeys, disable actions, or add up to 4 custom actions. Action hotkeys process the current selection directly."))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(AppFlavor.text("编辑技能…", "Edit Actions…")) {
                        NotificationCenter.default.post(name: .gebwOpenActions, object: nil)
                    }
                }
                Text(AppFlavor.text("朗读固定在第一位；浮窗显示前 5 个启用技能，其余收在更多菜单。", "Read stays first. The floating panel shows the first 5 enabled actions; the rest live in the More menu."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(AppFlavor.text("AI 模型（OpenAI 兼容）", "AI Model (OpenAI-compatible)")) {
                Toggle(AppFlavor.text("默认使用全文上下文", "Use full-text context by default"), isOn: $useFullContext)
                Text(AppFlavor.text("开启后，解释、翻译、提炼、背景和自定义技能会尽量读取当前文本控件或页面的可访问上下文，只把它作为选中内容的参考；拿不到时自动回退。", "When enabled, AI actions try to read accessible surrounding text and use it only as context for the selected text. If context is unavailable, they fall back automatically."))
                    .font(.caption).foregroundStyle(.secondary)
                TextField(AppFlavor.text("Base URL，例如 https://api.deepseek.com", "Base URL, e.g. https://api.deepseek.com"), text: $llmBaseURL)
                SecureField(AppFlavor.text("API Key（Bearer Token）", "API Key (Bearer token)"), text: $llmAPIKey)
                TextField(AppFlavor.text("模型", "Model"), text: $llmModel)
                Text(AppFlavor.text("默认预填 DeepSeek 推荐配置：Base URL 为 https://api.deepseek.com，模型为 deepseek-v4-flash。也可填写任何 OpenAI 兼容接口的 Base URL，例如以 /v1 结尾的服务；若直接填到 /chat/completions，也会按完整地址使用。", "DeepSeek is prefilled as the recommended default: Base URL https://api.deepseek.com and model deepseek-v4-flash. You can use any OpenAI-compatible Base URL, including /v1 endpoints; a full /chat/completions URL is also accepted."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Link(AppFlavor.text("前往 DeepSeek 获取 API Key ↗", "Get a DeepSeek API Key ↗"), destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                        .font(.caption)
                    Spacer()
                    Button(AppFlavor.text("恢复 DeepSeek 推荐", "Use DeepSeek Defaults")) {
                        llmBaseURL = Settings.recommendedLLMBaseURL
                        llmModel = Settings.recommendedLLMModel
                    }
                }
            }

            Section(AppFlavor.text("语音合成", "Text-to-Speech")) {
                Picker(AppFlavor.text("引擎", "Engine"), selection: $ttsEngine) {
                    Text(AppFlavor.text("火山引擎 · 推荐", "Volcengine")).tag("volcano")
                    Text(AppFlavor.text("本地（macOS）", "Local (macOS)")).tag("local")
                }
                .pickerStyle(.segmented)

                if ttsEngine == "volcano" {
                    Link(AppFlavor.text("没有账号？前往火山引擎语音控制台开通、获取 App ID / Token ↗", "Open the Volcengine speech console to get App ID / Token ↗"),
                         destination: URL(string: "https://console.volcengine.com/speech/app")!)
                        .font(.caption)
                    SecureField("App ID", text: $volcAppId)
                    SecureField("Access Token", text: $volcToken)
                    Picker(AppFlavor.text("音色", "Voice"), selection: $volcVoice) {
                        ForEach(VolcanoVoices.all) { voice in
                            Text(voice.name).tag(voice.id)
                        }
                        if !VolcanoVoices.all.contains(where: { $0.id == volcVoice }) {
                            Text(AppFlavor.text("自定义（\(volcVoice)）", "Custom (\(volcVoice))")).tag(volcVoice)
                        }
                    }
                    Link(AppFlavor.text("查看官方完整音色列表，复制 voice_type 填到下方 ↗", "Open the full official voice list and copy voice_type below ↗"),
                         destination: Self.volcanoVoiceListURL)
                        .font(.caption)
                    TextField(AppFlavor.text("自定义 voice_type（可选）", "Custom voice_type (optional)"), text: $volcVoice)
                    TextField("Cluster", text: $volcCluster)
                    HStack {
                        Text(AppFlavor.text("语速", "Speed"))
                        Slider(value: $volcSpeed, in: 0.5...2.0)
                        Text(String(format: "%.1fx", volcSpeed)).font(.caption).foregroundStyle(.secondary)
                    }
                    if volcUnconfigured {
                        Text(AppFlavor.text("未填 App ID / Access Token，暂时回退本地语音。", "App ID or Access Token is missing, so local macOS speech is used for now."))
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Text(AppFlavor.text("音色需在火山控制台开通；下拉只列常用大模型音色，完整列表以官方文档为准。", "Voices must be enabled in the Volcengine console. The picker lists common voices; the official documentation is the source of truth."))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text(AppFlavor.text("本地语速", "Local speed"))
                        Slider(value: $rate, in: 0.3...0.7)
                    }
                }

                Button(AppFlavor.text("试听", "Test Voice")) {
                    Settings.speechRate = Float(rate)
                    Speaker.shared.speak(AppFlavor.text("过耳不忘，这是当前语音的试听效果。", "ListenMark. This is how the current voice sounds."))
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
        panel.prompt = AppFlavor.text("选择", "Choose")
        if panel.runModal() == .OK, let url = panel.url {
            archiveFolder = url.path
            ArchiveStore.shared.relocate()
        }
    }
}
