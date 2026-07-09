<div align="center">

# Aura AI

**A private desktop AI companion with personalities, memory, images, and local LLM support.**

**Language:** English · [한국어](README.ko.md)

[![Electron](https://img.shields.io/badge/Electron-33-2b2e3a?logo=electron)](https://www.electronjs.org/)
[![React](https://img.shields.io/badge/React-18-087ea4?logo=react)](https://react.dev/)
[![TypeScript](https://img.shields.io/badge/TypeScript-5-3178c6?logo=typescript)](https://www.typescriptlang.org/)
[![Local-first](https://img.shields.io/badge/local--first-yes-3fb950)](#privacy-and-local-files)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

![Aura AI hero banner](docs/assets/readme/hero.png)

**Talk to seven distinct AI companions. Keep your memories in plain files. Attach images. Run local when you want privacy.**

**Editions:** Aura AI ships from one repository as an English edition and a Korean edition. The Korean build has Korean UI text, Korean persona names, Korean system prompts, and separate Korean default portraits.

[Quick Start](#quick-start) · [Editions](#editions) · [Meet The Personas](#meet-the-personas) · [Image Chat](#image-chat) · [Local LLM Setup](#local-llm-setup) · [For Code Agents](#code-agent-handoff-prompt)

</div>

---

## What Is Aura AI?

Aura AI is a desktop chat app for people who want AI to feel less like a command line and more like a small circle of useful companions.

You choose a persona, start a conversation, and Aura keeps the experience personal:

- **Seven built-in personas** with different voices, profile images, and conversation styles.
- **Image uploads in chat** so you can ask about screenshots, designs, photos, or documents.
- **Character-specific memory** so each persona remembers only what they learned with you.
- **Global memory** for manual facts you want every persona to share.
- **Kokoro text-to-speech** for local voice replies, with per-persona voice settings.
- **Beginner local LLM setup** with an in-app model downloader and llama.cpp launcher.
- **Optional cloud providers** for OpenAI, Anthropic, and Gemini.
- **No accounts, no telemetry, no hosted database.**

![Aura local-first visual](docs/assets/readme/local-first.png)

![Aura feature overview](docs/assets/readme/feature-grid.png)

## Quick Start

### Option 1: Download A Release

Installers are produced with Electron Builder:

- macOS: `.dmg` and `.zip`
- Windows: NSIS `.exe`

Release files are attached to GitHub Releases. Local builds write artifacts to the `release/` folder.

### Option 2: Run From Source

```bash
git clone https://github.com/eisenjimmy/AuraAI.git
cd AuraAI
npm install
npm run dev
```

Aura opens a first-run setup flow. Pick a provider, enter your name, choose a persona, and start chatting.

## Editions

Aura keeps one codebase and builds two desktop editions:

| Edition | App name | UI | Persona defaults | Data folder |
|---|---|---|---|---|
| English | Aura AI | English | Nova, Sage, Rio, Luna, Max, Gilleon, Neir | Aura AI |
| Korean | Aura AI Korean / 아우라 AI | Korean | 하나, 서윤, 재민, 은별, 민준, 길온, 나이르 | Aura AI Korean |

Build commands:

```bash
npm run dist:en:mac
npm run dist:en:win
npm run dist:ko:mac
npm run dist:ko:win
```

The English edition is the default when no `AURA_EDITION` flag is set.

## Local LLM Setup

Aura talks to any OpenAI-compatible local server.

The beginner setup can download the recommended GGUF model, point Aura at it, and start a llama.cpp server from inside the app. Advanced users can skip the beginner flow and configure Ollama, LM Studio, a custom llama.cpp server, or a cloud provider manually.

The recommended beginner setup is:

| Setting | Default |
|---|---|
| Provider | Local llama.cpp |
| URL | `http://127.0.0.1:8080/v1` |
| Model | Gemma 4 E4B / `gemma4-v2` |

This repo also includes a launcher script for the Jarvis-hosted Gemma 4 v2 llama.cpp runtime used by this machine:

```bash
npm run llm:gemma4-v2
```

Then open Aura and choose **Local (llama.cpp)**.

You can also use:

- [Ollama](https://ollama.com)
- [LM Studio](https://lmstudio.ai)
- Any llama.cpp server exposing `/v1/chat/completions`

## Meet The Personas

![Aura personas banner](docs/assets/readme/personas.png)

Each persona is editable. You can change the name, tagline, system prompt, accent color, Kokoro voice, and profile image. The original generated profile pictures are preserved as defaults, so users can switch back after uploading their own.

Profile images can be changed from Settings. Aura ships with the original seven generated portraits, ten additional portrait choices across Korean, European, Black, Latin, South Asian, Middle Eastern, silver-haired, and mixed-race styles, plus a user upload option.

| Persona | Portrait | Personality |
|---|---:|---|
| **Nova** | <img src="src/renderer/src/assets/avatars/nova.png" width="88" alt="Nova portrait"> | High-energy, warm, playful hype-friend. |
| **Sage** | <img src="src/renderer/src/assets/avatars/sage.png" width="88" alt="Sage portrait"> | Calm mentor, reflective listener, practical perspective. |
| **Rio** | <img src="src/renderer/src/assets/avatars/rio.png" width="88" alt="Rio portrait"> | Witty, fast, comedic, useful after the joke lands. |
| **Luna** | <img src="src/renderer/src/assets/avatars/luna.png" width="88" alt="Luna portrait"> | Soft-spoken night owl for quiet thoughts and creative moods. |
| **Max** | <img src="src/renderer/src/assets/avatars/max.png" width="88" alt="Max portrait"> | Direct, practical, dry humor, no wasted motion. |
| **Gilleon** | <img src="src/renderer/src/assets/avatars/gilleon.png" width="88" alt="Gilleon portrait"> | Charismatic inventor-founder energy: sharp, technical, irreverent. |
| **Neir** | <img src="src/renderer/src/assets/avatars/neir.png" width="88" alt="Neir portrait"> | Minimalist designer and visionary: calm, exacting, taste-driven. |

Aura also ships ten additional profile images to choose from, plus user uploads.

## Korean Edition Personas

The Korean edition keeps the same internal persona IDs but presents Korean names, Korean prompts, and Korean default portraits.

| Persona | Portrait | Personality |
|---|---:|---|
| **하나** | <img src="src/renderer/src/assets/avatars/nova-ko.png" width="88" alt="하나 portrait"> | Bright, playful, warm Korean hype-friend energy. |
| **서윤** | <img src="src/renderer/src/assets/avatars/sage-ko.png" width="88" alt="서윤 portrait"> | Calm former-teacher presence, careful questions, no judgment. |
| **재민** | <img src="src/renderer/src/assets/avatars/rio-ko.png" width="88" alt="재민 portrait"> | Korean banter, quick wit, useful after the joke lands. |
| **은별** | <img src="src/renderer/src/assets/avatars/luna-ko.png" width="88" alt="은별 portrait"> | Quiet Hongdae night-owl artist, soft emotional read. |
| **민준** | <img src="src/renderer/src/assets/avatars/max-ko.png" width="88" alt="민준 portrait"> | Practical shop-owner directness, dry humor, loyal help. |
| **길온** | <img src="src/renderer/src/assets/avatars/gilleon-ko.png" width="88" alt="길온 portrait"> | Inventor-founder parody energy: sharp, technical, fast. |
| **나이르** | <img src="src/renderer/src/assets/avatars/neir-ko.png" width="88" alt="나이르 portrait"> | White-haired minimalist Korean designer and product visionary. |

## Image Chat

Use the image button in the composer to attach one or more images. Aura copies those files into your configured image folder, displays thumbnails in the chat, and sends the current images to providers that support vision.

Default storage:

```text
Documents/AuraAi
```

Change it in:

```text
Settings -> Chat & Features -> Image uploads folder
```

Provider behavior:

| Provider | Image support |
|---|---|
| OpenAI-compatible | Sends image data as `image_url` content parts. Requires a vision-capable model. |
| Anthropic | Sends base64 image blocks. Requires a vision-capable Claude model. |
| Gemini | Sends inline image data. Requires a vision-capable Gemini model. |
| Local models | Works when your local model/server supports vision-style OpenAI payloads. Text-only models will return a normal provider error. |

## Memory

Aura stores durable memories as markdown files, not as a hidden database. Memory is split into two layers:

- **Global memory** is the manually editable shared memory slot. It appears above Settings in the sidebar.
- **Character memory** is isolated per persona. What you tell one persona is not automatically shown to another.

You can open character memory by clicking a persona profile image in the chat header, clicking an assistant avatar in the conversation, or right-clicking a persona profile image in the friends list.

Examples:

```text
memory-vault/
  favorite-coffee.md
  project-aura-ai.md
  sister-maya.md
```

The memory folder can be opened, edited, backed up, or deleted by hand. If you use Obsidian, it behaves like a normal markdown vault.

## Voice

Aura uses [Kokoro TTS](https://github.com/hexgrad/kokoro) in the renderer for local speech synthesis.

Each persona has:

- A Kokoro voice
- A speaking speed
- A preview button in settings

The first playback loads the local Kokoro model assets, so the first voice response can take longer than later responses.

If the first voice playback cannot fetch the Kokoro model files, Aura now resets the failed loader so you can retry after fixing the network connection. The renderer allows Kokoro model downloads from Hugging Face model storage.

## AI Providers

| Provider | Use it when |
|---|---|
| **Local llama.cpp** | You want privacy, no API bill, and control over your model. |
| **OpenAI** | You want strong general chat and vision support. |
| **Anthropic** | You want high-quality long-form conversation and reasoning. |
| **Gemini** | You want Google AI Studio support and multimodal models. |

API keys stay in your local config file and are sent only to the provider you choose.

## Privacy And Local Files

Aura is intentionally boring about data:

| Data | Local location |
|---|---|
| Settings and API keys | App config JSON |
| Persona edits | `personas.json` |
| Chats | `chats/<persona>.json` |
| Memories | Markdown files in the memory vault |
| Uploaded profile images | App data `avatars/` folder |
| Uploaded chat images | `Documents/AuraAi` by default, configurable |

There is no hosted Aura account, no analytics pipeline, and no remote Aura database.

Network traffic goes only to:

- Your selected AI provider
- Your selected web search provider when web search is enabled

## Build Releases

```bash
npm run typecheck
npm run build
npm run dist:mac
npm run dist:win
```

For explicit edition builds:

```bash
npm run dist:en:mac
npm run dist:en:win
npm run dist:ko:mac
npm run dist:ko:win
```

Generated installers are written to:

```text
release/
```

## Project Structure

```text
src/
  common/       Shared types and persona definitions
  main/         Electron main process, storage, providers, memory, search
  preload/      Typed bridge between main and renderer
  renderer/     React UI, chat, settings, avatars, Kokoro voice queue
docs/assets/    README artwork
build/          App icons
release/        Built installers
```

## Code Agent Handoff Prompt

Use this prompt to hand the repo to a code agent and get a working local setup:

```text
You are working in the AuraAI Electron + React + TypeScript repo.

Goal:
Get Aura AI running locally with the local llama.cpp provider, verify chat, image upload, memory, and Kokoro voice settings without introducing unrelated refactors.

Context:
- Use the existing project structure and scripts.
- Prefer the existing bundled Node runtime if global node/npm is unavailable.
- Default local provider:
  - baseUrl: http://127.0.0.1:8080/v1
  - model: gemma4-v2
- Start the local model with:
  npm run llm:gemma4-v2
- Then run:
  npm install
  npm run typecheck
  npm run dev

Validation:
- Confirm provider test succeeds against /v1/models.
- Send a text-only message.
- Upload an image in chat and confirm it is copied to Documents/AuraAi unless settings override it.
- Confirm the image thumbnail renders in chat.
- Confirm a vision-capable provider receives the image payload.
- Confirm text input still works while image attachments are staged.
- Confirm Korean IME text clears fully after sending.
- Open the global memory panel from the sidebar.
- Open character memory by clicking and right-clicking persona profile images.
- Open Settings -> Personas and preview a Kokoro voice.
- If Kokoro reports a fetch error, confirm network access and retry without restarting the app.
- Do not run destructive git commands.
- Do not mutate user data or production databases.
```

## Contributing

Contributions are welcome, especially:

- Better local model presets
- More persona packs
- Image understanding improvements
- Memory visualization
- Voice input
- Accessibility and localization
- Smaller release assets

Please keep the app understandable for non-technical users. A feature that needs a manual is probably not finished yet.

## License

MIT. See [LICENSE](LICENSE).
