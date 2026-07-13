# Contributing to Aura AI

Aura AI is a native macOS agent harness. Contributions should preserve its central contract: the model may propose actions, but Aura owns authority, execution, validation, and user-visible consent.

## Development setup

Requirements are an Apple silicon Mac, macOS 15 or newer, and Xcode 16 or newer.

```bash
swift test --package-path AuraNative
swift run --package-path AuraNative AuraAI
```

Build both editions before submitting user-interface, localization, memory, or provider changes:

```bash
./AuraNative/scripts/build-app.sh en
./AuraNative/scripts/build-app.sh ko
```

## Pull requests

- Keep changes scoped and explain the user-visible outcome.
- Add regression tests for harness, tool-call, memory, privacy, context, attachment, and document behavior.
- Keep English and Korean behavior aligned.
- Never weaken path checks or bypass approval prompts to improve convenience.
- Do not commit API keys, private conversations, Application Support data, `.app` bundles, DMGs, ZIP releases, or Swift build products.
- Document model-specific behavior as model-specific; do not present it as a harness guarantee.

## Reporting bugs

Include the Aura edition, macOS version, Mac model, provider kind, model identifier, exact reproduction steps, and sanitized logs. Remove personal content and credentials.
