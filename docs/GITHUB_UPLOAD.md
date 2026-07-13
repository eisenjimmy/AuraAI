# GitHub upload checklist

## Repository presentation

Suggested description:

> Native macOS agent harness with permissioned tools, local LLM support, real document generation, and inspectable Markdown memory.

Suggested topics:

```text
ai-agent macos swift swiftui local-llm llama-cpp agent-harness
tool-use privacy markdown-memory openai-compatible korean
```

Use `docs/assets/readme/aura-native-workspace.png` as the repository social preview. It is a current product screenshot rather than a generated interface concept.

## Before pushing

```bash
swift test --package-path AuraNative
./AuraNative/scripts/package-release.sh 1.2.0
git diff --check
git status --short
```

Confirm that no API keys, Application Support data, private conversations, `.app` bundles, DMGs, ZIPs, `.DS_Store`, or AppleDouble `._*` files are staged.

## Publish source

After reviewing the working tree:

```bash
git add README.md README.ko.md AuraNative .github docs CHANGELOG.md CONTRIBUTING.md SECURITY.md
git commit -m "Launch Aura AI native macOS harness"
git push origin main
```

## Publish v1.2.0 release

```bash
gh release create v1.2.0 \
  release/github/Aura-AI-1.2.0-macOS-arm64.dmg \
  release/github/Aura-AI-1.2.0-macOS-arm64.zip \
  release/github/Aura-AI-Korean-1.2.0-macOS-arm64.dmg \
  release/github/Aura-AI-Korean-1.2.0-macOS-arm64.zip \
  release/github/SHA256SUMS.txt \
  --title "Aura AI 1.2.0 — Native macOS Harness" \
  --notes-file docs/releases/v1.2.0.md
```

The source push and GitHub release are intentionally separate. Release binaries stay outside Git history.
