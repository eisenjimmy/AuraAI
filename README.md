<div align="center">

# Aura AI

**A private AI chat companion that lives on your computer.**

Five friends. Five personalities. A memory that grows with every conversation.

[Features](#features) · [Quick start](#quick-start) · [Providers](#ai-providers) · [Memory](#memory--an-obsidian-style-vault) · [Personas](#the-five-personas) · [Architecture](#architecture) · [FAQ](#faq)

![Electron](https://img.shields.io/badge/Electron-33-2b2e3a?logo=electron)
![React](https://img.shields.io/badge/React-18-087ea4?logo=react)
![TypeScript](https://img.shields.io/badge/TypeScript-5-3178c6?logo=typescript)
![License](https://img.shields.io/badge/license-MIT-green)
![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Windows-8b93a0)

</div>

---

Aura is a **chat buddy, not a home assistant**. No command palettes, no forty tools, no
setup rabbit holes. You open it, you pick a friend, you talk. Under the hood it quietly
does three things well:

1. **Remembers you** — durable facts from your conversations are saved as plain markdown
   notes with wikilinks (open the folder in [Obsidian](https://obsidian.md) and see the
   graph of what your friends know about you).
2. **Knows what day it is** — when a question depends on the real world (news, weather,
   prices, "did X come out yet?"), it searches the web and answers with today's context.
3. **Feels like a person** — five distinct personas with their own voices, speech styles,
   quirks, and opinions. Not five system prompts wearing name tags.

Everything is local-first: your chats, your memories, and your settings live in files on
your machine. The only network traffic is to the AI provider **you** choose — which can
be a model running entirely on your own computer.

## Features

| | |
|---|---|
| **Discord-style chat** | Familiar message groups, avatars, timestamps, streaming replies, markdown & code blocks — in a compact, code-editor-clean shell. |
| **5 preset personas** | Nova, Sage, Rio, Luna, Max — each with a distinct personality, accent color, and voice. Fully editable, with custom profile images. |
| **Any AI backend** | Local & free via [Ollama](https://ollama.com) / LM Studio / llama.cpp, or bring an API key for **Claude**, **OpenAI**, or **Gemini**. Switch anytime. |
| **Persistent memory** | Automatic, LLM-curated memory notes in an Obsidian-style markdown vault with `[[wikilinks]]`. View, edit, or delete anything — it's just markdown. |
| **Web awareness** | Built-in web search (no API key needed — DuckDuckGo fallback; optional Brave/Tavily keys for quality) plus authoritative current date/time in every conversation. |
| **Voice replies** | Per-persona text-to-speech using your OS voices. Speech starts while the reply is still streaming. |
| **Tools mode (opt-in)** | An advanced agentic loop where the model itself decides when to search, read pages, and save memories. Off by default — the default pipeline is deterministic and predictable. |
| **Onboarding wizard** | First launch walks you through provider → name → first friend in about a minute. |
| **Private by design** | No telemetry, no accounts, no cloud storage. Plain JSON + markdown files you can read, back up, and delete. |

## Quick start

### Run from source

Requires [Node.js](https://nodejs.org) 20+.

```bash
git clone https://github.com/<you>/aura-ai
cd aura-ai
npm install
npm run dev
```

### The one-minute setup

When Aura opens for the first time, the wizard asks three things:

1. **Which AI?** — pick *Local (Ollama)* for free & private, or paste an API key for
   Claude / OpenAI / Gemini. There's a **Test connection** button so you know it works
   before moving on.
2. **Who are you?** — your name and (optionally) a sentence about yourself. This seeds
   your friends' first impression of you.
3. **Who do you want to talk to first?**

That's it. Start typing.

### Going fully local (free & private)

```bash
# 1. Install Ollama from https://ollama.com
# 2. Pull a chat model:
ollama pull llama3.2
# 3. (Optional but recommended) pull the embedding model for smarter memory recall:
ollama pull nomic-embed-text
```

Then pick **Local (Ollama)** in Aura's setup. Any OpenAI-compatible server works —
LM Studio and llama.cpp's `llama-server` too; just change the URL in Settings.

### Build installers

```bash
npm run dist:mac   # .dmg + .zip
npm run dist:win   # NSIS installer
```

## AI providers

| Provider | Models | Cost | Notes |
|---|---|---|---|
| **Local (Ollama)** | Anything you `ollama pull` | Free | 100% private. Aura auto-detects installed models. |
| **Claude (Anthropic)** | Opus 4.8, Sonnet 5, Haiku 4.5 | API pricing | Excellent conversational quality. Key from [console.anthropic.com](https://console.anthropic.com). |
| **OpenAI** | GPT-5.2, GPT-4o, minis | API pricing | Key from [platform.openai.com](https://platform.openai.com). |
| **Gemini (Google)** | 2.5 Pro / Flash | Generous free tier | Key from [aistudio.google.com](https://aistudio.google.com). |

API keys are stored in a local config file, sent only to the provider you chose, and
never anywhere else.

## Memory — an Obsidian-style vault

After each exchange, Aura quietly asks the model: *"was anything durable revealed about
this person?"* If yes (their dog's name, their job, that they hate cilantro), it's filed
as a markdown note:

```markdown
---
title: Dog named Biscuit
type: relationship
importance: 4
created: 2026-07-04T21:14:03.201Z
updated: 2026-07-04T21:14:03.201Z
source: nova
---

Has a golden retriever named Biscuit, adopted in 2024.

Related: [[weekend-hiking]]
```

- **One fact per note**, with YAML frontmatter and `[[wikilinks]]` between related notes.
- An auto-generated `MEMORY.md` index groups everything by type.
- Recall blends semantic similarity (when an embedding model is available), importance,
  and recency — the same scoring formula on every provider.
- Open the vault folder from the **Memory** panel — it's plain markdown, so it works
  beautifully as an Obsidian vault. Edit or delete notes by hand; Aura picks up changes.
- Memory is shared across personas (tell Nova about your sister; Sage knows too), and
  each note records which friend learned it.

## The five personas

| | Persona | Vibe |
|---|---|---|
| **N** | **Nova** | Your hype-friend. Big energy, bigger heart. Remembers your interview date and demands updates. |
| **S** | **Sage** | Calm perspective, good questions, zero judgment. The retired-teacher friend with a garden. |
| **R** | **Rio** | Banter first, answers second — usually both. Will defend pineapple pizza to the death. |
| **L** | **Luna** | Soft-spoken night owl. Here for the 2am thoughts and the songs on repeat. |
| **M** | **Max** | Straight answers, dry humor, no fluff. Tells you the thing everyone else is too polite to say. |

Every persona is fully editable in **Settings → Personas**: name, tagline, accent color,
the entire personality prompt, a custom profile image (blank by default — add your own),
and a voice (pick any OS voice, tune rate & pitch, preview instantly). Built-ins can
always be reset to default.

All five are honest about being AI when asked — they're companions, not catfish.

## Voice

Aura speaks with your operating system's speech engine — zero setup, works offline, and
each persona gets their own voice. Replies are spoken **while they stream**: sentences
are flushed to the speech queue as they complete, so audio starts long before the reply
finishes (a pattern inherited from Aura's Jarvis-era voice stack).

**Want better voices?** The OS engine is the pragmatic default. Natural upgrades this
architecture supports (contributions welcome):

- **Neural TTS**: a local [Kokoro](https://github.com/hexgrad/kokoro) or
  [Piper](https://github.com/rhasspy/piper) HTTP server returning WAV — the speech queue
  already isolates synthesis behind one function.
- **Voice input (STT)**: local [whisper.cpp](https://github.com/ggerganov/whisper.cpp)
  with push-to-talk, streamed through the same pipeline.
- **Barge-in**: renderer-side VAD to pause speech when you start typing/talking.

## Tools mode (advanced)

By default Aura uses a **deterministic pipeline** — host code decides when to recall
memories and when to search, so behavior is predictable and fast, and it works with any
model, even small local ones.

Flip on **Settings → Tools mode** and the model instead drives a bounded agentic loop
(max 4 rounds) with four tools: `web_search`, `read_webpage`, `save_memory`,
`recall_memories` — using native tool-calling on Claude / OpenAI / Gemini / Ollama.
Everything the model does shows up as small chips above the reply, so nothing is hidden.
Use a model with solid tool-calling (GPT-4o, Claude, Gemini, or a larger local model).

## Architecture

```
aura/
├─ src/
│  ├─ common/            Shared types + the five persona definitions
│  ├─ main/              Electron main process (all privileged work)
│  │  ├─ providers/      One streaming contract, four backends
│  │  │                  (OpenAI-compatible fetch+SSE, Anthropic SDK, Gemini REST)
│  │  ├─ memory/         Markdown vault: parse/write notes, embeddings sidecar,
│  │  │                  recall scoring, LLM extraction
│  │  ├─ search/         Provider ladder: Brave/Tavily (keyed) → DuckDuckGo (free)
│  │  ├─ agent/          Prompt assembly, deterministic pipeline, optional tool loop
│  │  ├─ store.ts        JSON settings + persona overrides
│  │  └─ chats.ts        One JSON file per persona, like DM threads
│  ├─ preload/           contextBridge — the only door between worlds
│  └─ renderer/          React UI (sidebar, chat, onboarding, settings, memory panel)
└─ build/                App icons
```

**Design principles**

- **Deterministic over agentic (by default).** Tool access is governed by host code, not
  by an unconstrained model — the model writes text; the app decides what runs.
- **Files over databases.** Settings are JSON, chats are JSON, memory is markdown. No
  native modules, no migrations, nothing you can't inspect with a text editor.
- **One streaming contract.** Every provider yields the same `text / toolCalls / done`
  events, so the pipeline, the tool loop, and the UI don't care whose API is behind it.
- **Renderer is unprivileged.** Context isolation on, node integration off, strict CSP,
  a typed `contextBridge` API, and a dedicated `aura-avatar://` protocol for images.

### Where your data lives

| Data | Location (`%APPDATA%/aura-ai` on Windows, `~/Library/Application Support/aura-ai` on macOS) |
|---|---|
| Settings & API keys | `config.json` |
| Persona edits | `personas.json` |
| Conversations | `chats/<persona>.json` |
| Memory vault | `memory-vault/*.md` (relocatable in settings) |
| Avatars | `avatars/` |

Delete the folder and Aura forgets everything. That's the whole privacy policy.

## FAQ

**Which local model should I use?**
`llama3.2` (3B) is fine for casual chat on most machines. If you have the RAM/GPU, an
8B+ model makes personas noticeably more, well, *them*. For Tools mode, bigger is better.

**Do I need the embedding model?**
No — memory recall falls back to keyword matching. `ollama pull nomic-embed-text` makes
recall semantic ("what do I like for breakfast" finds the coffee note).

**Does web search cost anything?**
No. The default is a credential-free DuckDuckGo fallback. Add a free
[Brave Search](https://brave.com/search/api/) or [Tavily](https://tavily.com) key in
settings for better results.

**Can personas see each other's chats?**
No — each friendship is its own conversation. They share the memory vault though, like
friends who talk about you when you're not around (affectionately).

**Is anything sent anywhere besides my AI provider?**
Web searches go to the search provider (DuckDuckGo by default). That's it. No telemetry,
no analytics, no phone-home.

## Contributing

PRs welcome. The codebase is intentionally small and dependency-light — please keep it
that way. Good first contributions: new persona presets, a Kokoro/Piper TTS backend,
whisper.cpp voice input, localization, a memory graph view.

```bash
npm run dev        # hot-reloading dev app
npm run typecheck  # strict TS across main + renderer
npm run build      # production bundles
```

## License

[MIT](./LICENSE)

---

<div align="center">
<sub>Aura grew out of a personal Jarvis-style home assistant project, rebuilt from
scratch as a friendly, open-source chat companion. The deterministic-pipeline philosophy
— host code governs tools, not the model — carried over.</sub>
</div>
