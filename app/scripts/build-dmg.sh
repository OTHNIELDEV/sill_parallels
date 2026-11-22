#!/usr/bin/env bash
# Sill DMG 만들기 (macOS 전용) — 열면 Sill.app 을 「응용 프로그램」으로 끌어 넣는 창이 뜬다
#   ./app/scripts/build-dmg.sh              이 Mac 의 아키텍처로
#   ./app/scripts/build-dmg.sh --universal  Apple Silicon + Intel 함께 (Xcode 필요)
set -euo pipefail
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$APP_DIR/.." && pwd)"
[ "$(uname -s)" = Darwin ] || { echo "DMG 는 macOS 에서만 만들 수 있습니다" >&2; exit 1; }

"$APP_DIR/scripts/build-app.sh" "$@"

VERSION="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$ROOT/sill")"
BUILD="$APP_DIR/build"
DMG="$BUILD/Sill-$VERSION.dmg"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/sill-dmg.XXXX")"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$BUILD/Sill.app" "$STAGE/Sill.app"
ln -s /Applications "$STAGE/Applications"
cp "$APP_DIR/Resources/설치 방법.txt" "$STAGE/설치 방법.txt"

rm -f "$DMG"
hdiutil create -quiet -volname "Sill $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
hdiutil verify -quiet "$DMG"
echo "✓ $DMG"
