#!/usr/bin/env bash
# Replays two Claude Code sessions running in parallel through the hook
# command installed in ~/.claude/settings.json, exactly as Claude Code runs it.
set -euo pipefail

HOOK=${HOOK:-"/Applications/Hear Agent.app/Contents/MacOS/hearagent-hook"}
CMD=$("$HOOK" status claude-code | sed -n 's/^installed: //p')
[[ -n "$CMD" ]] || { echo "Claude Code hooks are not installed" >&2; exit 1; }

send() { printf '%s' "$1" | sh -c "$CMD"; }

session_a() {
  local base='"session_id":"demo-a","cwd":"/demo/checkout-web","transcript_path":"/nonexistent"'
  send "{$base,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"fix the cart test\"}"
  sleep 0.3
  send "{$base,\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm test\"}}"
  sleep 0.5
  send "{$base,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm test\"},\"tool_response\":{\"exit_code\":1,\"stderr\":\"cart.test.ts: expected 3 items, got 2\"}}"
  sleep 0.5
  send "{$base,\"hook_event_name\":\"Stop\",\"last_assistant_message\":\"I fixed the cart quantity bug and the cart tests pass now.\"}"
}

session_b() {
  local base='"session_id":"demo-b","cwd":"/demo/api-server","transcript_path":"/nonexistent"'
  sleep 0.2
  send "{$base,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"add a health endpoint\"}"
  sleep 0.6
  send "{$base,\"hook_event_name\":\"Notification\",\"message\":\"Claude needs your permission to use Bash\",\"notification_type\":\"permission_prompt\"}"
}

session_a &
session_b &
wait
echo "sent two sessions through: $CMD"
