#!/usr/bin/env bash
# Builds the Rust engine for the Mac app:
#   - app/Frameworks/HearAgentFFI.xcframework  (static library + C headers)
#   - app/Generated/hearagent_ffi.swift         (UniFFI Swift bindings)
#   - core/target/release/hearagent-hook        (the CLI agent hooks call)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
export CARGO_TARGET_DIR="$ROOT/core/target"
# Match the app's deployment target (project.yml), so the library runs on every macOS the app supports.
export MACOSX_DEPLOYMENT_TARGET=14.0
OUT="$CARGO_TARGET_DIR/release"

echo "==> cargo build (release)"
cd "$ROOT/core"
cargo build --release -p hearagent-ffi -p hearagent-hook

echo "==> generating Swift bindings"
GEN="$ROOT/app/Generated"
TMP=$(mktemp -d)
cargo run --quiet --release -p hearagent-ffi --bin uniffi-bindgen -- \
  generate --library "$OUT/libhearagent_ffi.dylib" --language swift --out-dir "$TMP"
rm -rf "$GEN"
mkdir -p "$GEN/include"
mv "$TMP"/*.swift "$GEN/"
mv "$TMP"/*.h "$GEN/include/"
mv "$TMP"/*.modulemap "$GEN/include/module.modulemap"
rm -rf "$TMP"

echo "==> creating XCFramework"
XCF="$ROOT/app/Frameworks/HearAgentFFI.xcframework"
rm -rf "$XCF"
xcodebuild -create-xcframework \
  -library "$OUT/libhearagent_ffi.a" \
  -headers "$GEN/include" \
  -output "$XCF" >/dev/null

echo "==> done"
ls "$GEN" "$XCF"
