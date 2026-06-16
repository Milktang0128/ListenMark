import SwiftUI

/// First-run guided setup. Narrative: 你是谁 → 给眼睛(辅助功能) → 接大脑(服务商)
/// → 见证魔法(听+解释+上下文) → 上路. Accessibility is the one mandatory gate;
/// the rest are skippable. Lives in its own window, opened on first launch.
final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable { case welcome, accessibility, provider, tryIt, done }

    @Published var step: Step = .welcome
    @Published var trusted: Bool = SelectionGrabber.isTrusted
    @Published var hasKey: Bool = !Settings.llmAPIKey.isEmpty

    let onOpenAX: () -> Void
    let onOpenServices: () -> Void
    let onTrustGranted: () -> Void
    let onFinish: () -> Void

    private var timer: Timer?

    init(onOpenAX: @escaping () -> Void,
         onOpenServices: @escaping () -> Void,
         onTrustGranted: @escaping () -> Void,
         onFinish: @escaping () -> Void) {
        self.onOpenAX = onOpenAX
        self.onOpenServices = onOpenServices
        self.onTrustGranted = onTrustGranted
        self.onFinish = onFinish
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()   // fires on the main run loop
        }
    }

    private func poll() {
        let t = SelectionGrabber.isTrusted
        if t != trusted {
            trusted = t
            if t { onTrustGranted() }   // re-arm capture; no restart needed
        }
        hasKey = !Settings.llmAPIKey.isEmpty
    }

    func stopTimer() { timer?.invalidate(); timer = nil }

    func markSeenIfNeeded() {
        if Settings.onboardingCompletedBuild == 0 {
            Settings.onboardingCompletedBuild = OnboardingModel.currentBuild
        }
    }

    static var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
    }

    func next() {
        if let n = Step(rawValue: step.rawValue + 1) { step = n } else { onFinish() }
    }
    func back() {
        if let p = Step(rawValue: step.rawValue - 1) { step = p }
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @AppStorage("deepseekKey") private var apiKey = ""

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 32)
                .padding(.top, 30)
            footer
        }
        .frame(minWidth: 520, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear { model.stopTimer(); model.markSeenIfNeeded() }
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch model.step {
        case .welcome: welcome
        case .accessibility: accessibility
        case .provider: provider
        case .tryIt: tryIt
        case .done: done
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 76, height: 76).cornerRadius(16)
            Text(AppFlavor.text("欢迎使用 \(AppFlavor.appName)", "Welcome to \(AppFlavor.appName)"))
                .font(.system(size: 22, weight: .semibold))
            Text(AppFlavor.tagline)
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Label(AppFlavor.text("我住在屏幕右上角的菜单栏 ↑（Dob 图标）", "I live in the menu bar, top-right ↑ (the Dob icon)"),
                  systemImage: "arrow.up")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .padding(.top, 6)
            Text(AppFlavor.text("花一分钟设好，之后划词即用。", "One minute to set up, then just select text anywhere."))
                .font(.system(size: 12)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).padding(.top, 8)
    }

    private var accessibility: some View {
        stepScaffold(
            icon: "hand.raised.fill",
            title: AppFlavor.text("第一步 · 给我「眼睛」", "Step 1 · Give Me “Eyes”"),
            subtitle: AppFlavor.text("Dob 需要「辅助功能」权限才能读取你在别的 App 里选中的文字。这是唯一必需的一步。",
                                     "Dob needs Accessibility permission to read text you select in other apps. This is the one required step.")
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: model.trusted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(model.trusted ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    Text(model.trusted ? AppFlavor.text("已授权，太好了", "Granted — you're set")
                                       : AppFlavor.text("尚未授权", "Not yet granted"))
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    if !model.trusted {
                        Button(AppFlavor.text("打开系统设置", "Open System Settings")) { model.onOpenAX() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))

                Text(AppFlavor.text("在 系统设置 › 隐私与安全性 › 辅助功能 里把「\(AppFlavor.appName)」打开——打开后这里会自动变绿，无需重启。",
                                    "In System Settings › Privacy & Security › Accessibility, turn on “\(AppFlavor.appName)”. It turns green here automatically — no restart needed."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Label(AppFlavor.text("隐私：数据默认只留在你电脑本地。", "Privacy: your data stays on your Mac by default."),
                      systemImage: "lock.shield")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
    }

    private var provider: some View {
        stepScaffold(
            icon: "brain.head.profile",
            title: AppFlavor.text("第二步 · 接上「大脑」", "Step 2 · Connect a “Brain”"),
            subtitle: AppFlavor.text("绑定一个服务商后才能用 解释 / 翻译 / 比较；朗读不需要。这步可跳过，随时能在「服务管理」里补。",
                                     "Bind a provider to unlock Explain / Translate / Compare; Read needs none. Skippable — you can do it later in Services.")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppFlavor.text("DeepSeek API Key（推荐，已预设好接口与模型）", "DeepSeek API Key (recommended; endpoint & model preset)"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                SecureField("sk-…", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 14) {
                    Link(AppFlavor.text("前往获取 DeepSeek Key ↗", "Get a DeepSeek key ↗"),
                         destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                        .font(.system(size: 12))
                    Button(AppFlavor.text("更多服务商 → 服务管理", "More providers → Services")) { model.onOpenServices() }
                        .buttonStyle(.link).font(.system(size: 12))
                }
                Text(AppFlavor.text("也支持 OpenAI / Kimi / 通义 / 智谱 / 火山方舟 / Gemini 等任意 OpenAI 兼容接口。",
                                    "Also supports OpenAI / Kimi / Qwen / Zhipu / Gemini and any OpenAI-compatible API."))
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
    }

    private var tryIt: some View {
        stepScaffold(
            icon: "sparkles",
            title: AppFlavor.text("第三步 · 试一下", "Step 3 · Try It"),
            subtitle: AppFlavor.text("在任意 App 选中文字，屏幕边缘就会弹出工具条。现在拿下面这段练手：",
                                     "Select text in any app and a toolbar pops up at the screen edge. Practice on this:")
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppFlavor.text(
                    "熵增定律说，孤立系统的无序程度只增不减——这正是它无法自发回到初始状态的原因。",
                    "The second law says disorder in an isolated system only increases — which is why it never returns to its initial state on its own."))
                    .font(.system(size: 14)).lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))

                if model.hasKey {
                    instruction(AppFlavor.text("选中其中「它无法自发回到初始状态」→ 点「解释」。", "Select “it never returns to its initial state” → tap Explain."))
                    instruction(AppFlavor.text("注意结果上的「已附带上下文」——它理解的是整段，不只是你选的那句。", "Watch for the “context included” badge — it reads the whole passage, not just your phrase."))
                } else {
                    instruction(AppFlavor.text("还没绑服务商？先点工具条上的「朗读」听听（不需要 Key）。", "No provider yet? Tap Read on the toolbar to hear it (no key needed)."))
                    instruction(AppFlavor.text("想要解释/翻译，回上一步绑定一个服务商即可。", "Want Explain/Translate? Go back one step and bind a provider."))
                }
                Label(AppFlavor.text("没弹出来？按 ⌥⌘R 手动呼出工具条。", "No toolbar? Press ⌥⌘R to summon it."),
                      systemImage: "keyboard")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
    }

    private var done: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44)).foregroundStyle(.green)
            Text(AppFlavor.text("上路了 🎉", "You're all set 🎉"))
                .font(.system(size: 22, weight: .semibold))
            VStack(alignment: .leading, spacing: 10) {
                tip("cursorarrow.rays", AppFlavor.text("划词即用——选中文字，工具条自动弹出。", "Just select text — the toolbar appears."))
                tip("menubar.arrow.up.rectangle", AppFlavor.text("所有设置、服务、档案都在菜单栏 Dob 图标里。", "Settings, services and archive live under the menu-bar icon."))
                tip("command", AppFlavor.text("⌥⌘R 手动呼出；每个技能都能设自己的快捷键。", "⌥⌘R summons it; every skill can have its own hotkey."))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.top, 8)
    }

    // MARK: Footer

    private var footer: some View {
        let isGate = model.step == .accessibility
        return HStack {
            if !isGate {
                Button(AppFlavor.text("跳过引导", "Skip")) { model.onFinish() }
                    .buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 12))
            }
            HStack(spacing: 5) {
                ForEach(OnboardingModel.Step.allCases, id: \.rawValue) { s in
                    Circle()
                        .fill(s.rawValue == model.step.rawValue ? Color.accentColor : Color.primary.opacity(0.18))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)
            if model.step != .welcome {
                Button(AppFlavor.text("上一步", "Back")) { model.back() }
            }
            Button(model.step == .done ? AppFlavor.text("完成", "Done") : AppFlavor.text("下一步", "Next")) {
                model.next()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGate && !model.trusted)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .background(.bar)
    }

    // MARK: Pieces

    private func stepScaffold(icon: String, title: String, subtitle: String,
                              @ViewBuilder body: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Color.accentColor)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 17, weight: .semibold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            body()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func instruction(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "circle.fill").font(.system(size: 4)).foregroundStyle(.secondary).padding(.top, 6)
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Color.accentColor).frame(width: 22)
            Text(text).font(.system(size: 13))
            Spacer(minLength: 0)
        }
    }
}
