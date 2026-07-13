#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EDITION="${1:-en}"
APP_NAME="Aura AI"
if [[ "$EDITION" == "ko" ]]; then
  APP_NAME="Aura AI Korean"
fi

swift build -c release --package-path "$ROOT/AuraNative"

APP="$ROOT/release/$APP_NAME.app"
BIN="$ROOT/AuraNative/.build/release/AuraAI"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AuraAI"
RESOURCE_BUNDLE="$(find "$ROOT/AuraNative/.build" -type d -path '*/release/AuraNative_AuraAI.bundle' -print -quit)"
if [[ -n "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
fi
cp "$ROOT/AuraNative/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :AuraEdition string $EDITION" "$APP/Contents/Info.plist"
if [[ "$EDITION" == "ko" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.eisenjimmy.aura.ko" "$APP/Contents/Info.plist"
fi

ICONSET="$(mktemp -d)/AuraIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16 16" "32 16@2x" "32 32" "64 32@2x" "128 128" "256 128@2x" "256 256" "512 256@2x" "512 512" "1024 512@2x"; do
  pixels="${spec%% *}"
  name="${spec#* }"
  sips -z "$pixels" "$pixels" "$ROOT/build/aura.png" --out "$ICONSET/icon_${name}.png" >/dev/null
done
iconutil --convert icns "$ICONSET" --output "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
find "$APP" -name '._*' -type f -delete
dot_clean -m "$APP" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$APP" >/dev/null
find "$APP" -name '._*' -type f -delete
dot_clean -m "$APP" >/dev/null 2>&1 || true
echo "$APP"
