#!/usr/bin/env bash
# Release build of "Hear Agent.app", ad-hoc signed, plus a drag-to-Applications DMG.
#   scripts/package.sh            -> dist/Hear Agent.app, dist/HearAgent-<version>.dmg
#   scripts/package.sh --install  -> also copies the app into /Applications
#
# Ad-hoc signing runs on this Mac. Sharing with other people needs a
# Developer ID signature and notarization (Apple Developer Program).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-app.sh" Release

BUILT="$ROOT/build/DerivedData/Build/Products/Release/Hear Agent.app"
DIST="$ROOT/dist"
APP="$DIST/Hear Agent.app"
rm -rf "$DIST"
mkdir -p "$DIST"
ditto "$BUILT" "$APP"

echo "==> signing (ad hoc)"
codesign --force --sign - --options runtime "$APP/Contents/MacOS/hearagent-hook"
codesign --force --sign - --options runtime "$APP"
codesign --verify --deep --strict "$APP"
echo "   signature ok"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$DIST/HearAgent-$VERSION.dmg"
echo "==> building $DMG"
STAGE=$(mktemp -d)
ditto "$APP" "$STAGE/Hear Agent.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Hear Agent" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

if [[ "${1:-}" == "--install" ]]; then
  echo "==> installing to /Applications"
  pkill -x "Hear Agent" 2>/dev/null || true
  sleep 0.5
  rm -rf "/Applications/Hear Agent.app"
  ditto "$APP" "/Applications/Hear Agent.app"
fi

du -sh "$APP" "$DMG"
echo "==> done"
