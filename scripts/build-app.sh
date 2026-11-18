#!/usr/bin/env bash
# Builds "Hear Agent.app". Usage: scripts/build-app.sh [Debug|Release]
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CONFIG=${1:-Debug}

"$ROOT/scripts/build-rust.sh"

cd "$ROOT/app"
xcodegen generate --quiet
xcodebuild -project HearAgent.xcodeproj -scheme HearAgent -configuration "$CONFIG" \
  -derivedDataPath "$ROOT/build/DerivedData" build -quiet

APP="$ROOT/build/DerivedData/Build/Products/$CONFIG/Hear Agent.app"
echo "==> built $APP"
