# Aura AI Native

The macOS-native Aura AI client. It is written in SwiftUI and uses a local-first
store, an OpenAI-compatible model connection, a reviewable privacy filter, and
a permissioned agent harness for practical document work.

## Documents and OCR

- Text and multiple files can be sent together from one composer. Each file is
  limited to 20 MB, and extracted text is token-budgeted for local models with
  small context windows.
- Supported ingestion includes images, PDF, DOCX, XLSX, RTF, CSV, Markdown,
  HTML, JSON, and plain text.
- Apple Vision performs offline OCR for images and scanned PDF pages.
- Assistant messages render Markdown headings, emphasis, lists, rules, and
  fenced code blocks as native chat content.
- Approved tools create real XLSX workbooks, editable Word documents, real
  PowerPoint presentations, self-contained HTML reports, and Markdown documents
  inside the selected workspace. Each appears as a clickable attachment below
  the friend's reply.
- **Settings > Skills** manages Markdown, HTML, Excel, Word, and PowerPoint for
  the whole team, including the purpose and backing tool name for each skill.
  Friend Editor applies an additional per-friend skill allowance. A tool is
  exposed only when both the global and friend-level settings are enabled.
- Aura creates `Documents/AuraAi` by default (`Documents/AuraAiKR` in the Korean
  edition) for tool-generated files. Settings can replace or restore that write
  folder. Omitted document paths fall back to a safe title-derived filename.
- Right-clicking a friend opens memory or a Friend Editor for bundled template
  portraits, custom photo upload, specialty, tagline, and personality.
- The Korean edition reuses its full Korean persona prompts from the Electron
  source and requires Korean responses unless the user requests another
  language. Document tools attach their output to the final assistant reply.

`baidu/Unlimited-OCR` is not embedded in the app. Its official runtime uses a
large custom Python/CUDA model, which is not compatible with Aura's signed,
native Swift distribution path. The attachment layer can support an optional
external OCR provider in a future release without changing chat storage.

## Run

```bash
swift run --package-path AuraNative AuraAI
```

## Build an app bundle

```bash
./AuraNative/scripts/build-app.sh en
./AuraNative/scripts/build-app.sh ko
```

The generated app is ad-hoc signed for local testing. Release signing and
notarization remain separate distribution steps.

## Safety model

- Privacy filtering runs only before a cloud request. The user reviews every
  detected replacement and can cancel the request.
- Read-only workspace inspection is automatic when tools are enabled in
  Settings. File and artifact writes, shell commands, and macOS control are
  always presented for approval.
- Computer control requires macOS Accessibility permission and has no hidden
  auto-approval path.
