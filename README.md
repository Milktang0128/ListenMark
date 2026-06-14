# 过耳不忘

[English / International Edition](README.en.md)

**过耳不忘**是一款 macOS 原生菜单栏 App。它把「选中文本」变成一组可以直接听、解释、翻译、提炼、留档的语音化动作：

选中文字 -> 选择技能 -> 听到结果 -> 需要时一键留档、搜索、重听。

中文用户安装后的 App 名称是 **过耳不忘**。仓库名、SwiftPM target、安装包和国际版沿用英文名 **ListenMark**。

## 下载

已签名和公证的安装包发布在 GitHub Releases：

<https://github.com/Milktang0128/ListenMark/releases>

发行通道：

| 版本 | App 名称 | Release tag | 安装包 |
|---|---|---|---|
| 中文版 | 过耳不忘 | `v...` | `ListenMark-...-arm64.dmg` |
| 国际版 | ListenMark | `listenmark-v...` | `ListenMark-International-...-arm64.dmg` |

两个版本使用不同的 bundle id、数据目录和自动更新通道，可以并行维护。

## 核心能力

| 能力 | 说明 | 需要配置 |
|---|---|---|
| 朗读 | 直接朗读选中文本 | 无，本地语音可用 |
| 解释 | 用简体中文解释选中内容，保留重点和背景 | DeepSeek API Key |
| 翻译 | 中文译英文；其他语言译简体中文 | DeepSeek API Key |
| 提炼 | 提取核心结论，适合快速听懂 | DeepSeek API Key |
| 背景 | 补充必要背景知识，不展开成百科 | DeepSeek API Key |
| 自定义技能 | 最多新增 4 个自己的处理动作 | DeepSeek API Key |
| 屏幕 OCR | 无法直接取词时，快捷键框选屏幕区域识别文字 | 无 |
| 留档 | 本地保存原文、结果、来源、时间和上下文摘录 | 无 |
| 档案 / 今日回响 | 搜索、回看、重听、复习已保存内容 | 无 |

## 新特性

- **全文上下文**：解释、翻译、提炼、背景和自定义技能默认会尽量读取当前文本控件或页面的可访问上下文，把「选中内容 + 上下文」一起交给模型；拿不到时自动回退到选中文本。
- **上下文感知提示**：如果本次回答成功带上上下文，结果区域会显示「已附带上下文」，让用户知道这次不是孤立处理。
- **轻量留档上下文**：留档不会保存整篇全文，只保存选中内容上下各 200 字，并用标记突出选中内容。
- **技能快捷键**：每个技能都可以设置全局快捷键。朗读默认 `Control + Shift + R`，解释默认 `Control + Shift + E`，翻译默认 `Control + Shift + T`。
- **技能管理**：朗读固定第一；其它技能可拖动排序、禁用、编辑提示词；浮窗只展示前 5 个启用技能，其余收进更多菜单。
- **AI 优化提示词**：编辑技能时可以让当前 DeepSeek 模型优化提示词，适合把草稿提示词整理成更稳定的技能。
- **复制后顺手留档**：点击复制图标会立即复制，随后弹出轻量气泡，可以顺手点一下留档。
- **重听不重算**：结果页和档案里的重听会播放已有结果，不会重新调用模型生成。
- **屏幕选框 OCR**：设置里可配置 OCR 快捷键，默认 `Control + Shift + O`，用于处理无法取词或不允许复制的界面。
- **自动更新**：App 会检查当前发行通道的 GitHub Releases；中文和国际版互不串线。

## 首次启用

1. 打开 App 后授予 **辅助功能** 权限：系统设置 -> 隐私与安全性 -> 辅助功能 -> 打开「过耳不忘」。
2. 菜单栏耳朵图标 -> **设置...**：
   - **DeepSeek API Key**：解释、翻译、提炼、背景和自定义技能需要。
   - **语音合成引擎**：中文版默认火山引擎 TTS；未配置或失败时回退到 macOS 本地语音。
   - **火山音色**：设置页提供[官方完整音色列表](https://www.volcengine.com/docs/6561/1257544?lang=zh)链接，也支持手填 `voice_type`。
3. 选中任意应用里的文字，等待浮窗弹出，或按弹出面板快捷键 `Option + Command + R`。

> 每次重新构建开发版都会重新签名，macOS 可能作废旧的辅助功能授权。重新构建后请移除旧授权、重新添加 App，并重启。

## 使用方式

- 选中文字后，浮窗会显示朗读、解释、翻译、提炼、背景等技能。
- 点击技能后，朗读会直接开始；AI 技能会流式生成文字，完整结果生成后朗读。
- 如果当前应用暴露了可访问全文，上下文会自动参与处理；设置里可以关闭「默认使用全文上下文」。
- 点击复制图标会立即复制文本，并提供轻量留档入口。
- 点击 **留档** 会写入本地 JSON 和可读 Markdown。
- 菜单栏耳朵图标 -> **打开档案...** 可搜索历史、查看上下文摘录、重听结果。
- 菜单栏耳朵图标 -> **今日回响...** 可复习已保存内容。
- 菜单栏耳朵图标 -> **检查更新...** 可手动同步 GitHub Releases。

## 本地数据

默认数据目录：

```text
~/Library/Application Support/ListenMark/
```

主要文件：

```text
archive.json
过耳不忘.md
```

也可以在设置中选择自己的留档目录，例如 Obsidian vault。Markdown 留档会保留来源、时间、动作、AI 回答和轻量上下文摘录。

## 国际版

国际版面向英文用户，安装后 App 名称为 **ListenMark**，见 [README.en.md](README.en.md)。

主要差异：

- 英文界面和英文默认技能名称。
- 国际版默认本地 macOS 语音，降低首次使用门槛。
- 翻译默认目标是自然英文；如果原文已经是英文，则改写成更清晰自然的英文。
- 使用 `listenmark-v...` prerelease 通道，不会影响中文版 `v...` 稳定通道。
- 数据目录为 `~/Library/Application Support/ListenMark International/`。

## 构建

构建中文版：

```bash
./make-app.sh
open 过耳不忘.app
```

构建国际版：

```bash
FLAVOR=en ./make-app.sh
open ListenMark.app
```

开发运行：

```bash
swift run
```

## 代码结构

| 路径 | 职责 |
|---|---|
| `Sources/ListenMark/AppFlavor.swift` | 中文 / 国际版 flavor、名称、发行通道 |
| `Sources/ListenMark/AppDelegate.swift` | 菜单栏、触发编排、窗口和动作流 |
| `Sources/ListenMark/ActionPanel.swift` / `ActionPanelView.swift` | 光标旁浮动动作面板 |
| `Sources/ListenMark/ActionStore.swift` | 内置技能、自定义技能、排序、快捷键、提示词 |
| `Sources/ListenMark/ActionsConfigView.swift` | 技能编辑、AI 优化提示词 |
| `Sources/ListenMark/Hotkey.swift` / `HotkeyRecorder.swift` | 全局快捷键和快捷键录制 |
| `Sources/ListenMark/SelectionGrabber.swift` | AX 选区、上下文读取、模拟复制回退 |
| `Sources/ListenMark/ScreenOCR.swift` | 屏幕选框 OCR |
| `Sources/ListenMark/LLMClient.swift` | DeepSeek Chat Completions |
| `Sources/ListenMark/Speaker.swift` / `VolcanoTTS.swift` | 本地语音和火山引擎 TTS |
| `Sources/ListenMark/ArchiveStore.swift` | 本地 JSON 和 Markdown 留档 |
| `Sources/ListenMark/ArchiveView.swift` / `ReviewView.swift` | 档案和今日回响 |
| `Sources/ListenMark/GitHubReleaseUpdater.swift` | GitHub Releases 自动更新 |
| `Sources/ListenMark/SettingsView.swift` | 设置页 |

## 已知边界

- 取词依赖 Accessibility 和模拟复制；少数禁用复制、跨进程隔离强或未暴露可访问文本的应用可能拿不到全文上下文。
- 屏幕 OCR 是兜底能力，识别质量取决于截图清晰度、语言和系统 Vision OCR。
- AI 技能依赖 DeepSeek API；没有 Key 时仍可使用朗读、OCR、复制、留档和档案。
- 火山引擎音色需要在控制台开通对应 `voice_type`；设置页下拉只列常用音色，完整列表以[官方文档](https://www.volcengine.com/docs/6561/1257544?lang=zh)为准。
