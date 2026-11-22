#!/usr/bin/env bash
# Sill.app 만들기 (macOS 전용)
#   swift build 결과 + 엔진(sill · templates) + Info.plist → 임시 서명 → app/build/Sill.app · Sill-<판>.zip
#   ./app/scripts/build-app.sh             이 Mac 의 아키텍처로
#   ./app/scripts/build-app.sh --universal Apple Silicon + Intel 함께 (Xcode 필요)
set -euo pipefail
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$APP_DIR/.." && pwd)"
[ "$(uname -s)" = Darwin ] || { echo "Sill.app 은 macOS 에서만 만들 수 있습니다" >&2; exit 1; }

VERSION="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$ROOT/sill")"
[ -n "$VERSION" ] || { echo "엔진에서 판 번호를 읽지 못했습니다" >&2; exit 1; }
ARCH_ARGS=()
[ "${1:-}" = "--universal" ] && ARCH_ARGS=(--arch arm64 --arch x86_64)

# bash 3.2 + set -u 에서 빈 배열을 안전하게 펼치는 꼴
swift build -c release --package-path "$APP_DIR" ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"}
BIN_DIR="$(swift build -c release --package-path "$APP_DIR" ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} --show-bin-path)"

BUILD="$APP_DIR/build"
OUT="$BUILD/Sill.app"
rm -rf "$OUT" "$BUILD/Sill-$VERSION.zip"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources/engine"
cp "$BIN_DIR/Sill" "$OUT/Contents/MacOS/Sill"
cp "$ROOT/sill" "$OUT/Contents/Resources/engine/sill"
chmod +x "$OUT/Contents/Resources/engine/sill"
cp -R "$ROOT/templates" "$OUT/Contents/Resources/engine/templates"
cp "$ROOT/LICENSE" "$OUT/Contents/Resources/LICENSE"
sed "s/@VERSION@/$VERSION/g" "$APP_DIR/Resources/Info.plist" > "$OUT/Contents/Info.plist"
if [ -f "$APP_DIR/Resources/AppIcon.icns" ]; then
  cp "$APP_DIR/Resources/AppIcon.icns" "$OUT/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$OUT/Contents/Info.plist"
fi
plutil -lint "$OUT/Contents/Info.plist" >/dev/null
# 임시(ad-hoc) 서명 — 이 Mac 에서 바로 실행된다. 다른 Mac 에 배포하려면 Developer ID 서명 · 공증이 필요하다.
codesign --force --deep --sign - "$OUT"
(cd "$BUILD" && ditto -c -k --keepParent Sill.app "Sill-$VERSION.zip")
echo "✓ $OUT"
echo "✓ $BUILD/Sill-$VERSION.zip"
