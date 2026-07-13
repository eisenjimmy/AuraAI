# Changelog

All notable native Aura AI Harness changes are documented here.

## [1.2.0] - 2026-07-12

### Added

- Full SwiftUI macOS workspace with English and Korean editions.
- Permissioned agent loop for workspace reads, writes, shell commands, and macOS control.
- Team-wide and per-character Markdown, HTML, Excel, Word, and PowerPoint skills.
- Attachment extraction for common document formats, scanned-PDF OCR, and multimodal images.
- Split document preview and clickable generated-file attachments.
- Per-character and shared Obsidian-compatible Markdown memory vaults.
- Post-response memory curator with rolling context, attachment evidence, and Korean memory output.
- Cloud privacy review for high-confidence contact, card, secret, and custom-pattern matches.
- Rolling conversation continuity and visible context usage.

### Changed

- Replaced the macOS browser-shell product direction with a native agent-harness application.
- Standardized the interface accent, fixed sidebar behavior, native pointer feedback, and three-pane layout.

### Distribution

- Apple silicon, macOS 15 or newer.
- Ad-hoc signed community builds; Apple notarization is not yet configured.
- Removed the unused bundled Kokoro model assets from the native macOS repository release.
