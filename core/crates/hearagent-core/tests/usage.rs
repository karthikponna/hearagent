use hearagent_core::event::Agent;
use hearagent_core::usage::{civil_from_days, claude_cost, days_from_civil, parse_iso_ms, scan, ReportOptions, Tokens};
use serde_json::json;
use std::fs;
use std::path::Path;

const NOV_18_10AM: &str = "2026-11-18T10:00:00.000Z";

fn ms(iso: &str) -> i64 {
    parse_iso_ms(iso).unwrap()
}

fn write_lines(path: &Path, lines: &[serde_json::Value]) {
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, lines.iter().map(|l| l.to_string()).collect::<Vec<_>>().join("\n")).unwrap();
}

fn assistant(id: &str, ts: &str, model: &str, input: u64, output: u64, read: u64, write: u64) -> serde_json::Value {
    json!({"type": "assistant", "timestamp": ts, "sessionId": "s-claude", "cwd": "/Users/dev/code/storefront", "gitBranch": "feat/passkeys",
           "message": {"id": id, "model": model, "usage": {"input_tokens": input, "output_tokens": output, "cache_read_input_tokens": read, "cache_creation_input_tokens": write}}})
}

fn home_with_sessions() -> tempfile::TempDir {
    let home = tempfile::tempdir().unwrap();
    write_lines(
        &home.path().join(".claude/projects/-Users-dev-code-storefront/s-claude.jsonl"),
        &[
            json!({"type": "user", "timestamp": "2026-11-18T08:59:00.000Z", "sessionId": "s-claude", "cwd": "/Users/dev/code/storefront", "isMeta": true, "message": {"content": "<command-name>/clear</command-name>"}}),
            json!({"type": "user", "timestamp": "2026-11-18T09:00:00.000Z", "sessionId": "s-claude", "cwd": "/Users/dev/code/storefront", "message": {"content": "Add passkey sign-in to checkout\nand keep the email fallback"}}),
            assistant("msg_1", "2026-11-18T09:00:05.000Z", "claude-opus-5-5", 1000, 500, 10_000, 2000),
            // Streaming writes the same message twice; it must be counted once.
            assistant("msg_1", "2026-11-18T09:00:06.000Z", "claude-opus-5-5", 1000, 500, 10_000, 2000),
            assistant("msg_2", "2026-11-18T09:30:00.000Z", "claude-opus-5-5", 2000, 1000, 20_000, 0),
            json!({"type": "assistant", "timestamp": "2026-11-18T09:31:00.000Z", "message": {"id": "x", "model": "<synthetic>", "usage": {"input_tokens": 0, "output_tokens": 0}}}),
            // A week earlier, in its own 5-hour block.
            assistant("msg_0", "2026-11-10T09:00:00.000Z", "claude-sonnet-5-5", 100_000, 50_000, 0, 0),
        ],
    );
    write_lines(
        &home.path().join(".codex/sessions/2026/11/18/rollout-abc.jsonl"),
        &[
            json!({"timestamp": "2026-11-18T07:00:00.000Z", "type": "session_meta", "payload": {"id": "s-codex", "cwd": "/Users/dev/code/search-service"}}),
            json!({"timestamp": "2026-11-18T07:00:01.000Z", "type": "turn_context", "payload": {"model": "gpt-5.5-codex", "cwd": "/Users/dev/code/search-service"}}),
            json!({"timestamp": "2026-11-18T07:00:01.000Z", "type": "response_item", "payload": {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "<environment_context>x</environment_context>"}]}}),
            json!({"timestamp": "2026-11-18T07:00:02.000Z", "type": "response_item", "payload": {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "Speed up product search"}]}}),
            json!({"timestamp": "2026-11-18T07:05:00.000Z", "type": "event_msg", "payload": {"type": "token_count",
                "info": {"total_token_usage": {"total_tokens": 1500}, "last_token_usage": {"input_tokens": 1000, "cached_input_tokens": 400, "output_tokens": 500, "cache_write_input_tokens": 0}},
                "rate_limits": {"plan_type": "plus", "primary": {"used_percent": 34.0, "window_minutes": 300, "resets_at": 1795000000}, "secondary": {"used_percent": 41.5, "window_minutes": 10080, "resets_at": 1795500000}}}}),
            // Repeated token_count with an unchanged running total is not new usage.
            json!({"timestamp": "2026-11-18T07:05:01.000Z", "type": "event_msg", "payload": {"type": "token_count",
                "info": {"total_token_usage": {"total_tokens": 1500}, "last_token_usage": {"input_tokens": 1000, "cached_input_tokens": 400, "output_tokens": 500}}}}),
        ],
    );
    home
}

fn opts() -> ReportOptions {
    ReportOptions { now_ms: ms(NOV_18_10AM), utc_offset_seconds: 0, claude_five_hour_limit: 0, claude_weekly_limit: 0 }
}

#[test]
fn sessions_have_titles_models_tokens_and_cost() {
    let home = home_with_sessions();
    let r = scan(home.path(), opts());
    assert_eq!(r.sessions.len(), 2);

    let claude = r.sessions.iter().find(|s| s.agent == Agent::ClaudeCode).unwrap();
    assert_eq!(claude.title, "Add passkey sign-in to checkout");
    assert_eq!(claude.project, "storefront");
    assert_eq!(claude.branch.as_deref(), Some("feat/passkeys"));
    assert_eq!(claude.model, "claude-sonnet-5-5", "model of the latest line read");
    assert_eq!(claude.messages, 3, "duplicate and synthetic messages are skipped");
    assert_eq!(claude.tokens, Tokens { input: 103_000, output: 51_500, cache_read: 30_000, cache_write: 2000 });

    let codex = r.sessions.iter().find(|s| s.agent == Agent::Codex).unwrap();
    assert_eq!(codex.title, "Speed up product search");
    assert_eq!(codex.model, "gpt-5.5-codex");
    assert_eq!(codex.messages, 1);
    assert_eq!(codex.tokens, Tokens { input: 600, output: 500, cache_read: 400, cache_write: 0 });
    assert!((codex.cost_usd - (600.0 * 1.25 + 500.0 * 10.0 + 400.0 * 0.125) / 1e6).abs() < 1e-12);

    assert_eq!(r.sessions[0].agent, Agent::ClaudeCode, "newest activity first");
}

#[test]
fn days_month_and_heatmap() {
    let home = home_with_sessions();
    let r = scan(home.path(), opts());
    let today = r.days.last().unwrap();
    assert_eq!(today.day, "2026-11-18");
    assert_eq!(today.claude_tokens, 1500 + 12_000 + 3000 + 20_000);
    assert_eq!(today.codex_tokens, 1500);
    assert_eq!(today.sessions, 2);
    let nov10 = r.days.iter().find(|d| d.day == "2026-11-10").unwrap();
    assert_eq!(nov10.claude_tokens, 150_000);

    assert_eq!(r.month.days_in_month, 30);
    assert_eq!(r.month.active_days, 2);
    assert_eq!(r.month.sessions, 2);
    assert!(r.month.forecast_usd > r.month.cost_usd);
    // Wednesday 2026-11-18 09:00 UTC.
    assert_eq!(r.heatmap[2 * 24 + 9], 2);
    assert_eq!(r.heatmap[2 * 24 + 7], 1);
}

#[test]
fn claude_limit_windows_are_estimated_from_blocks() {
    let home = home_with_sessions();
    let r = scan(home.path(), opts());
    let five = &r.claude_five_hour;
    assert!(five.estimated);
    assert_eq!(five.used_tokens, 1000 + 500 + 2000 + 2000 + 1000, "current block, cache reads excluded");
    assert_eq!(five.limit_tokens, 150_000, "busiest past block is 100%");
    assert_eq!(five.resets_at_ms, Some(ms("2026-11-18T14:00:00.000Z")));
    assert!((five.used_percent - 6500.0 / 150_000.0 * 100.0).abs() < 1e-9);

    let custom = scan(home.path(), ReportOptions { claude_five_hour_limit: 13_000, ..opts() });
    assert!((custom.claude_five_hour.used_percent - 50.0).abs() < 1e-9);

    let later = scan(home.path(), ReportOptions { now_ms: ms("2026-11-18T16:00:00.000Z"), ..opts() });
    assert_eq!(later.claude_five_hour.used_tokens, 0, "block has reset");
}

#[test]
fn codex_limits_come_from_codex() {
    let home = home_with_sessions();
    let c = scan(home.path(), opts()).codex.unwrap();
    assert!(!c.five_hour.estimated);
    assert_eq!(c.five_hour.used_percent, 34.0);
    assert_eq!(c.weekly.used_percent, 41.5);
    assert_eq!(c.five_hour.resets_at_ms, Some(1_795_000_000_000));
    assert_eq!(c.plan.as_deref(), Some("plus"));
}

#[test]
fn local_time_offset_moves_day_boundaries() {
    let home = home_with_sessions();
    // UTC+14: Nov 18 10:00 UTC is already Nov 19 locally.
    let r = scan(home.path(), ReportOptions { utc_offset_seconds: 14 * 3600, ..opts() });
    assert_eq!(r.days.last().unwrap().day, "2026-11-19");
}

#[test]
fn rescans_pick_up_new_lines() {
    let home = home_with_sessions();
    let first = scan(home.path(), opts());
    let path = home.path().join(".claude/projects/-Users-dev-code-storefront/s-claude.jsonl");
    let mut text = fs::read_to_string(&path).unwrap();
    text.push('\n');
    text.push_str(&assistant("msg_3", "2026-11-18T09:45:00.000Z", "claude-opus-5-5", 10, 10, 0, 0).to_string());
    fs::write(&path, text).unwrap();
    let second = scan(home.path(), opts());
    let count = |r: &hearagent_core::usage::UsageReport| r.sessions.iter().find(|s| s.agent == Agent::ClaudeCode).unwrap().messages;
    assert_eq!(count(&second), count(&first) + 1);
}

#[test]
fn empty_home_is_fine() {
    let home = tempfile::tempdir().unwrap();
    let r = scan(home.path(), opts());
    assert!(r.sessions.is_empty());
    assert_eq!(r.days.len(), 180);
    assert_eq!(r.claude_five_hour.used_percent, 0.0);
    assert!(r.codex.is_none());
}

#[test]
fn titles_from_slash_commands_last_prompt_and_code_fences() {
    let home = tempfile::tempdir().unwrap();
    let base = |sid: &str| json!({"sessionId": sid, "cwd": "/Users/dev/code/app", "timestamp": "2026-11-18T09:00:00.000Z"});
    let with = |mut v: serde_json::Value, extra: serde_json::Value| {
        v.as_object_mut().unwrap().extend(extra.as_object().unwrap().clone());
        v
    };
    write_lines(&home.path().join(".claude/projects/p/a.jsonl"), &[
        with(base("a"), json!({"type": "user", "message": {"content": "<command-message>plan</command-message>\n<command-name>/plan</command-name>\n<command-args>split the billing module</command-args>"}})),
        assistant("a1", "2026-11-18T09:00:01.000Z", "claude-opus-5-5", 1, 1, 0, 0),
    ]);
    write_lines(&home.path().join(".claude/projects/p/b.jsonl"), &[
        with(base("b"), json!({"type": "user", "message": {"content": [{"type": "tool_result", "content": "x"}]}})),
        json!({"type": "last-prompt", "lastPrompt": "Refactor the cart store", "sessionId": "b"}),
        with(assistant("b1", "2026-11-18T09:00:01.000Z", "claude-opus-5-5", 1, 1, 0, 0), json!({"sessionId": "b"})),
    ]);
    write_lines(&home.path().join(".claude/projects/p/c.jsonl"), &[
        with(base("c"), json!({"type": "user", "message": {"content": "```python\nprint(1)\n```\nWhy does this fail?"}})),
        with(assistant("c1", "2026-11-18T09:00:01.000Z", "claude-opus-5-5", 1, 1, 0, 0), json!({"sessionId": "c"})),
    ]);
    let r = scan(home.path(), opts());
    let title = |id: &str| r.sessions.iter().find(|s| s.id == id).unwrap().title.clone();
    assert_eq!(title("a"), "/plan split the billing module");
    assert_eq!(title("b"), "Refactor the cart store");
    assert_eq!(title("c"), "print(1)");
}

#[test]
fn dates_and_prices() {
    assert_eq!(parse_iso_ms("1970-01-01T00:00:00Z"), Some(0));
    assert_eq!(parse_iso_ms("1970-01-01T05:30:00.5+05:30"), Some(500));
    assert_eq!(parse_iso_ms("nope"), None);
    let d = days_from_civil(2024, 2, 29);
    assert_eq!(civil_from_days(d), (2024, 2, 29));
    let t = Tokens { input: 1_000_000, output: 1_000_000, cache_read: 0, cache_write: 0 };
    assert_eq!(claude_cost("claude-opus-5-5", &t), 30.0);
    assert_eq!(claude_cost("claude-sonnet-5-5", &t), 18.0);
    assert_eq!(claude_cost("claude-haiku-4-5", &t), 6.0);
}
