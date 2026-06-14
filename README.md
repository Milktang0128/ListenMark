# ListenMark

ListenMark（中文名：过耳不忘）是一款 macOS 原生菜单栏 App：
划词选中任何文本 → 选一个**语音化动作**（朗读 / 解释 / 翻译 / 提炼 / 背景）→ 结果用语音念出 → 每次交互**自动留档**，可搜索、可回看、可重听。

## Download

已签名和公证的安装包会发布在 GitHub Releases：

<https://github.com/Milktang0128/ListenMark/releases>

当前发行包：

- `ListenMark-0.1.0-arm64.dmg`
- `ListenMark-0.1.0-arm64.zip`

## 当前能力

| 动作 | 说明 | 需要配置 |
|---|---|---|
| **朗读** | 念原文 | 无，本地语音零配置 |
| **解释 / 翻译 / 提炼 / 背景** | 调 DeepSeek 处理后念出回应 | DeepSeek Key |
| **自动留档** | 原文 + 动作 + 来源 + 时间 + AI 回应 → 本地 | 无 |
| **档案** | 时间线 + 全文搜索 + 一键重听 | 无 |

- 文本动作走 DeepSeek（`deepseek-chat`，OpenAI 兼容接口）。
- 语音合成默认用 macOS 本地语音（离线、免配置）；可在设置里切到火山引擎（豆包语音）TTS，失败自动回退本地。
- 数据默认只存在本地：`~/Library/Application Support/ListenMark/`（`archive.json` + `ListenMark.md`）。

## 构建 & 运行

```bash
./make-app.sh
open ListenMark.app
```

或开发时直接：

```bash
swift run
```

> 每次重新构建都会 ad-hoc 重新签名，macOS 会作废旧的辅助功能授权。
> 重新构建后请到 系统设置 > 隐私与安全性 > 辅助功能 把旧的 `ListenMark` 移除再重新添加，并重启 App。

## 首次启用

1. 启动后授予**辅助功能**权限（读取选中文本所必需）：系统设置 > 隐私与安全性 > 辅助功能 → 打开 `ListenMark` → 重启 App。
2. 菜单栏耳朵图标 → **设置...**：
   - **DeepSeek API Key**：解释 / 翻译 / 提炼 / 背景 需要。
   - **语音合成引擎**：默认本地；要用豆包音色就选「火山引擎」并填 App ID / Access Token / 音色。

## 用法

- 任意应用里选中文字 → 面板自动弹出（或按全局快捷键，默认 `Option + Command + R`）。
- 点 **朗读** 立刻念；点 **解释 / 翻译 / 提炼 / 背景** 走 DeepSeek 再念。
- 菜单栏耳朵图标 → **打开档案...** 查看 / 搜索 / 重听历史。

## 代码结构

| 路径 | 职责 |
|---|---|
| `Sources/ListenMark/main.swift` | 入口，accessory 模式 |
| `Sources/ListenMark/AppDelegate.swift` | 菜单栏、触发编排、面板、窗口 |
| `Sources/ListenMark/Hotkey.swift` | Carbon 全局热键 |
| `Sources/ListenMark/SelectionGrabber.swift` | AX 选区优先 + 模拟 Command-C 回退取词 |
| `Sources/ListenMark/ActionPanel.swift` / `ActionPanelView.swift` | 光标旁浮动动作面板 |
| `Sources/ListenMark/Speaker.swift` | 语音输出（本地 / 火山引擎路由） |
| `Sources/ListenMark/VolcanoTTS.swift` | 火山引擎 TTS |
| `Sources/ListenMark/LLMClient.swift` | DeepSeek Chat Completions |
| `Sources/ListenMark/ArchiveStore.swift` | 本地留档（JSON + Markdown 导出） |
| `Sources/ListenMark/ArchiveView.swift` / `SettingsView.swift` | 档案 / 设置 |

## 已知边界

- 取词靠 Accessibility / 模拟复制：少数禁用复制的应用可能取不到。
- 文本动作走 DeepSeek SSE 流式：边出字边念。
- 「今日回响」复习、跨端续听仍处于早期实现 / 规划阶段。
