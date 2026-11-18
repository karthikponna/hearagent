#!/usr/bin/env bash
# Sends a sample hook payload to the running Hear Agent app, exactly as an agent hook would.
#   scripts/fire-event.sh claude-code claude_stop        (fixture name)
#   scripts/fire-event.sh codex path/to/payload.json     (any file)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
AGENT=${1:?agent: claude-code or codex}
INPUT=${2:?fixture name or JSON file}
HOOK="$ROOT/core/target/release/hearagent-hook"
[[ -x "$HOOK" ]] || { echo "build first: scripts/build-rust.sh" >&2; exit 1; }

if [[ -f "$INPUT" ]]; then
  FILE="$INPUT"
else
  FILE="$ROOT/core/fixtures/${INPUT%.json}.json"
fi
sed "s#FIXTURES#$ROOT/core/fixtures#g" "$FILE" | "$HOOK" "$AGENT"
echo "sent $(basename "$FILE") as $AGENT"
