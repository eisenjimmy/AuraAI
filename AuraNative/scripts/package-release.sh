#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLIST="$ROOT/AuraNative/Resources/Info.plist"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")}"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
OUT="$ROOT/release/github"
STAGING="$(mktemp -d)"

cleanup() {
  rm -rf "$STAGING"
}
trap cleanup EXIT

if [[ "$VERSION" != "$PLIST_VERSION" ]]; then
  echo "Requested version $VERSION does not match Info.plist version $PLIST_VERSION." >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

package_edition() {
  local edition="$1"
  local app_name="$2"
  local artifact_name="$3"
  local app="$ROOT/release/$app_name.app"
  local edition_staging="$STAGING/$artifact_name"

  "$ROOT/AuraNative/scripts/build-app.sh" "$edition"
  codesign --verify --deep --strict "$app"
  file "$app/Contents/MacOS/AuraAI" | grep -q 'arm64'

  ditto -c -k --sequesterRsrc --keepParent \
    "$app" "$OUT/$artifact_name-$VERSION-macOS-arm64.zip"

  mkdir -p "$edition_staging"
  ditto "$app" "$edition_staging/$app_name.app"
  ln -s /Applications "$edition_staging/Applications"
  hdiutil create \
    -volname "$app_name $VERSION" \
    -srcfolder "$edition_staging" \
    -format UDZO \
    -fs HFS+ \
    -ov \
    "$OUT/$artifact_name-$VERSION-macOS-arm64.dmg" >/dev/null
}

package_edition en "Aura AI" "Aura-AI"
package_edition ko "Aura AI Korean" "Aura-AI-Korean"

dot_clean -m "$OUT" >/dev/null 2>&1 || true
find "$OUT" -name '._*' -type f -delete

(
  cd "$OUT"
  shasum -a 256 ./*.dmg ./*.zip > SHA256SUMS.txt
)
find "$OUT" -name '._*' -type f -delete

echo "Release artifacts:"
find "$OUT" -maxdepth 1 -type f ! -name '._*' -print | sort
