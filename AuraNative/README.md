# Aura AI Native

The supported Aura AI Harness implementation is the SwiftUI macOS package in this directory.

```bash
swift test --package-path AuraNative
swift run --package-path AuraNative AuraAI
./AuraNative/scripts/build-app.sh en
./AuraNative/scripts/build-app.sh ko
./AuraNative/scripts/package-release.sh 1.2.0
```

See the repository [README](../README.md) for the harness architecture, permissions, providers, memory model, release downloads, and complete build instructions. Korean documentation is available in [README.ko.md](../README.ko.md).
