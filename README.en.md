# ListenMark

[中文 README / Chinese Edition](README.md)

**ListenMark** is a native macOS menu bar app that turns selected text into spoken understanding.

Select text anywhere -> choose an action -> hear the result -> save useful items to a searchable local archive.

The Chinese edition is distributed as **过耳不忘**. The international edition keeps the English app name **ListenMark**, uses its own bundle id, data folder, defaults, and GitHub prerelease update channel.

## Download

Signed and notarized installers are published on GitHub Releases:

<https://github.com/Milktang0128/ListenMark/releases>

Release channels:

| Edition | App name | Release tag | Installer |
|---|---|---|---|
| Chinese | 过耳不忘 | `v...` | `ListenMark-...-arm64.dmg` |
| International | ListenMark | `listenmark-v...` | `ListenMark-International-...-arm64.dmg` |

Use the `listenmark-v...` prerelease for the international edition.

## Features

| Feature | What it does | Requirement |
|---|---|---|
| Read | Speaks selected text directly | None |
| Explain | Explains the selected text in clear English | OpenAI-compatible API key |
| Translate | Translates foreign text to English, or rewrites English more clearly | OpenAI-compatible API key |
| Summarize | Gives the core takeaway | OpenAI-compatible API key |
| Context | Adds background needed to understand the selection, off by default | OpenAI-compatible API key |
| Insight | Surfaces deeper meaning, values, tension, or implications, off by default | OpenAI-compatible API key |
| Blind Spots | Finds missing assumptions, weak points, and follow-up checks, off by default | OpenAI-compatible API key |
| Proofread | Reviews a writing draft with minimal edit suggestions, off by default | OpenAI-compatible API key |
| Custom actions | Add up to 4 personal prompt-based actions | OpenAI-compatible API key |
| Screen OCR | Select a screen region when direct text capture fails | None |
| Archive | Save source text, result, app, time, and context excerpt locally | None |
| Review | Replay and review saved items | None |

## Highlights

- AI actions use full-text context by default when the current app exposes accessible surrounding text.
- When context is used, the result shows a small "Context included" indicator.
- Saved context stays lightweight: only about 200 characters before and after the selection are archived, with the selection marked.
- Every action can have its own global hotkey. Defaults: Read `Control + Shift + R`, Explain `Control + Shift + E`, Translate `Control + Shift + T`.
- Read always stays first; other actions can be reordered, disabled, edited, or moved into the More menu.
- The action editor includes AI Optimize for improving prompts with your current AI model.
- The copy icon copies immediately, then shows a small save affordance.
- Replay uses the existing generated result instead of asking the model again.
- Screen selection OCR is available from Settings as a fallback hotkey. Default: `Control + Shift + O`.
- Automatic updates follow the matching GitHub release channel, verify the downloaded app, and install it directly when macOS permissions allow. Chinese and international builds do not cross-update.

## Quick Start

1. Open ListenMark and grant Accessibility permission when macOS asks.
2. Add an OpenAI-compatible API key in Settings for AI actions. DeepSeek is prefilled as the recommended default provider.
3. Select text in any app.
4. Use the floating panel, menu bar item, or an action hotkey.
5. Save useful results to the local archive.

Default hotkeys:

| Action | Hotkey |
|---|---|
| Show panel | `Option + Command + R` |
| Read | `Control + Shift + R` |
| Explain | `Control + Shift + E` |
| Translate | `Control + Shift + T` |
| Screen OCR fallback | `Control + Shift + O` |

## Data

The international edition stores data separately from the Chinese edition:

```text
~/Library/Application Support/ListenMark International/
```

The readable Markdown archive is named:

```text
ListenMark.md
```

You can choose a custom archive folder in Settings, including an Obsidian vault.

## Build

Build the international edition:

```bash
FLAVOR=en ./make-app.sh
open ListenMark.app
```

Build the Chinese edition:

```bash
./make-app.sh
open 过耳不忘.app
```

Run during development:

```bash
swift run
```

## Notes

- Direct capture depends on macOS Accessibility and, when needed, a simulated copy fallback. Some apps may block both.
- Full-text context is best effort. When it is unavailable, ListenMark falls back to the selected text.
- AI actions require an OpenAI-compatible Chat Completions API. DeepSeek is the prefilled recommended default.
- The international edition defaults to local macOS speech; Volcengine TTS is optional and can use a custom `voice_type`.
