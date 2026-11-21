# Hear Agent

A Mac app for people who run coding agents (Claude Code and Codex). It speaks short, human summaries when an agent needs approval, finishes, or stops with an error, and gives you a dashboard and a notch panel for sessions, usage, limits, spend, dev servers, actions and agent config. [hearagent.app](https://hearagent.app)

- `core/`: Rust engine. Parses hook events, names sessions (worktree / project + branch), condenses the finished turn from the transcript, ranks what to play across sessions, installs hooks, talks to the backend, reads usage from local Claude Code and Codex session files, and finds local dev servers. Also the `hearagent-hook` CLI that agent hooks call.
- `app/`: SwiftUI app: dashboard window, notch panel, menu bar menu, sign-in (Supabase Auth: Google and Apple) and playback. Talks to the engine through UniFFI.
- `backend/`: Cloudflare Worker (TypeScript). Verifies Supabase sessions, writes GPT-5 mini summaries, voices them with ElevenLabs (George), spends credits, and runs Dodo Payments checkout and webhooks. Holds all API keys; the app never sees them.
- `migrations/`: Supabase SQL (profiles, plans, subscriptions, credits). Paste into the Supabase SQL editor.

## Build the app

Requirements: Xcode 16+, Rust (`rustup`), XcodeGen (`brew install xcodegen`).

```bash
scripts/build-app.sh            # debug build, talks to http://localhost:8787
scripts/package.sh --install    # release build -> dist/HearAgent-<version>.dmg and /Applications
# Render every dashboard page and notch tab to PNGs (debug builds):
"build/DerivedData/Build/Products/Debug/Hear Agent.app/Contents/MacOS/Hear Agent" --render-snapshots /tmp/shots [--real]
```

The release build's backend URL is `HEARAGENT_API_BASE_URL` in `app/project.yml`. Any build can be pointed elsewhere with
`defaults write com.karthikponna.hearagent apiBaseURL https://your-worker.workers.dev`.

## Run the backend locally

```bash
cd backend
npm install
cp .dev.vars.example .dev.vars        # set MOCK_PROVIDERS=1 to skip OpenAI/ElevenLabs
npm run db:migrate:local
npm run dev                           # http://localhost:8787
```

## Test

```bash
cd core && CARGO_TARGET_DIR=target cargo test     # Rust engine
cd backend && npm test                             # Worker (runs in the Workers runtime)
scripts/fire-event.sh claude-code claude_stop      # send a sample hook event to the running app
```

## Credits

1 credit = 1 spoken character. The $19 plan (`plans` table, id `starter`) grants 150,000 credits per billing period; Dodo `subscription.active` / `subscription.renewed` webhooks refill them.
