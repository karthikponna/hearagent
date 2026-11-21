//! Reads Claude Code and Codex session files on this Mac and turns them into
//! usage numbers for the dashboard: sessions, tokens, estimated cost, activity
//! by day and hour, and the 5-hour / weekly limit windows. Nothing leaves the Mac.

use crate::event::Agent;
use serde::Serialize;
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const DAY_MS: i64 = 86_400_000;
const HOUR_MS: i64 = 3_600_000;
const BLOCK_MS: i64 = 5 * HOUR_MS;
const WEEK_MS: i64 = 7 * DAY_MS;
const MAX_AGE: Duration = Duration::from_secs(180 * 86_400);
const REPORT_DAYS: i64 = 180;
const MAX_SESSIONS: usize = 400;

#[derive(Debug, Clone, Copy, Default, PartialEq, Serialize)]
pub struct Tokens {
    pub input: u64,
    pub output: u64,
    pub cache_read: u64,
    pub cache_write: u64,
}

impl Tokens {
    pub fn total(&self) -> u64 {
        self.input + self.output + self.cache_read + self.cache_write
    }
    /// What counts toward plan limits: cache reads are cheap and excluded.
    pub fn billable(&self) -> u64 {
        self.input + self.output + self.cache_write
    }
    fn add(&mut self, o: &Tokens) {
        self.input += o.input;
        self.output += o.output;
        self.cache_read += o.cache_read;
        self.cache_write += o.cache_write;
    }
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct SessionUsage {
    pub id: String,
    pub agent: Agent,
    pub project: String,
    pub cwd: String,
    pub title: String,
    pub model: String,
    pub branch: Option<String>,
    pub tokens: Tokens,
    pub cost_usd: f64,
    pub messages: u32,
    pub started_ms: i64,
    pub last_ms: i64,
    pub transcript_path: String,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct DayUsage {
    /// Local date, "YYYY-MM-DD".
    pub day: String,
    pub claude_tokens: u64,
    pub codex_tokens: u64,
    pub cost_usd: f64,
    pub sessions: u32,
    /// Prompt tokens served from cache, and all prompt tokens (fresh, cached, written).
    pub cache_read_tokens: u64,
    pub prompt_tokens: u64,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct LimitWindow {
    pub used_tokens: u64,
    pub limit_tokens: u64,
    pub used_percent: f64,
    pub resets_at_ms: Option<i64>,
    /// True when the percentage is Hear Agent's estimate rather than the agent's own number.
    pub estimated: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct CodexLimits {
    pub five_hour: LimitWindow,
    pub weekly: LimitWindow,
    pub plan: Option<String>,
    pub observed_ms: i64,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct MonthSummary {
    pub tokens: u64,
    pub cost_usd: f64,
    pub forecast_usd: f64,
    pub sessions: u32,
    pub active_days: u32,
    pub days_in_month: u32,
    pub cache_hit_rate: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct UsageReport {
    pub sessions: Vec<SessionUsage>,
    /// Oldest first, one entry per local day, ending today.
    pub days: Vec<DayUsage>,
    /// 7 x 24 message counts over the last 28 days; index = weekday (Mon = 0) * 24 + hour.
    pub heatmap: Vec<u32>,
    pub claude_five_hour: LimitWindow,
    pub claude_weekly: LimitWindow,
    pub codex: Option<CodexLimits>,
    pub month: MonthSummary,
    pub generated_ms: i64,
}

#[derive(Debug, Clone, Copy)]
pub struct ReportOptions {
    pub now_ms: i64,
    pub utc_offset_seconds: i32,
    /// 0 = auto: the busiest past window counts as 100%.
    pub claude_five_hour_limit: u64,
    pub claude_weekly_limit: u64,
}

#[derive(Debug, Clone)]
struct Msg {
    ts_ms: i64,
    tokens: Tokens,
    cost: f64,
}

#[derive(Debug, Clone)]
struct FileSummary {
    session: SessionUsage,
    msgs: Vec<Msg>,
    codex_limits: Option<CodexLimits>,
}

type Cache = HashMap<PathBuf, (u64, SystemTime, Option<FileSummary>)>;
static CACHE: Mutex<Option<Cache>> = Mutex::new(None);

/// Scans the user's agent folders (re-reading only files that changed) and builds a report.
pub fn scan(home: &Path, opts: ReportOptions) -> UsageReport {
    let mut files: Vec<(PathBuf, Agent)> = Vec::new();
    collect_jsonl(&home.join(".claude/projects"), 3, &mut |p| files.push((p, Agent::ClaudeCode)));
    collect_jsonl(&home.join(".codex/sessions"), 4, &mut |p| files.push((p, Agent::Codex)));

    let mut guard = CACHE.lock().unwrap();
    let cache = guard.get_or_insert_with(HashMap::new);
    let mut summaries = Vec::new();
    let mut live = HashSet::new();
    for (path, agent) in files {
        let Ok(meta) = std::fs::metadata(&path) else { continue };
        let modified = meta.modified().unwrap_or(UNIX_EPOCH);
        if SystemTime::now().duration_since(modified).unwrap_or_default() > MAX_AGE {
            continue;
        }
        live.insert(path.clone());
        let fresh = matches!(cache.get(&path), Some((size, m, _)) if *size == meta.len() && *m == modified);
        if !fresh {
            let summary = match agent {
                Agent::ClaudeCode => parse_claude(&path),
                Agent::Codex => parse_codex(&path),
            };
            cache.insert(path.clone(), (meta.len(), modified, summary));
        }
        if let Some((_, _, Some(s))) = cache.get(&path) {
            summaries.push(s.clone());
        }
    }
    cache.retain(|p, _| live.contains(p));
    drop(guard);
    build_report(summaries, opts)
}

fn collect_jsonl(dir: &Path, depth: u32, out: &mut dyn FnMut(PathBuf)) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(kind) = entry.file_type() else { continue };
        if kind.is_dir() && depth > 0 {
            collect_jsonl(&path, depth - 1, out);
        } else if kind.is_file() && path.extension().is_some_and(|e| e == "jsonl") {
            out(path);
        }
    }
}

fn lines(path: &Path) -> impl Iterator<Item = Value> {
    let reader = File::open(path).ok().map(BufReader::new);
    reader.into_iter().flat_map(|r| r.lines().map_while(Result::ok)).filter_map(|l| serde_json::from_str(&l).ok())
}

fn s<'a>(v: &'a Value, key: &str) -> &'a str {
    v.get(key).and_then(Value::as_str).unwrap_or_default()
}

fn u(v: &Value, key: &str) -> u64 {
    v.get(key).and_then(Value::as_u64).unwrap_or(0)
}

fn folder(cwd: &str) -> String {
    Path::new(cwd).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| "unknown".into())
}

fn title_from(text: &str) -> Option<String> {
    let t = text.trim();
    // Slash commands are logged as <command-name>/plan</command-name><command-args>…</command-args>.
    if let Some(name) = between(t, "<command-name>", "</command-name>") {
        let args = between(t, "<command-args>", "</command-args>").unwrap_or_default();
        return Some(clip(format!("{} {}", name.trim(), args.trim()).trim()));
    }
    if t.is_empty()
        || t.starts_with('<')
        || t.starts_with("# AGENTS.md")
        || t.starts_with("Caveat:")
        || t.starts_with("The following is the Codex agent history")
    {
        return None;
    }
    let line = t.lines().map(str::trim).find(|l| !l.is_empty() && !l.starts_with("```"))?;
    Some(clip(line))
}

fn between<'a>(s: &'a str, start: &str, end: &str) -> Option<&'a str> {
    let from = s.find(start)? + start.len();
    let to = s[from..].find(end)? + from;
    Some(&s[from..to])
}

fn clip(line: &str) -> String {
    if line.chars().count() > 90 {
        format!("{}…", line.chars().take(89).collect::<String>())
    } else {
        line.to_string()
    }
}

fn parse_claude(path: &Path) -> Option<FileSummary> {
    let mut seen = HashSet::new();
    let mut msgs = Vec::new();
    let (mut id, mut cwd, mut model, mut branch, mut title) = (String::new(), String::new(), String::new(), None, None::<String>);
    let mut last_prompt = None::<String>;
    let mut total = Tokens::default();
    let mut cost = 0.0;
    let (mut started, mut last) = (i64::MAX, 0i64);
    for v in lines(path) {
        let ts = parse_iso_ms(s(&v, "timestamp"));
        if id.is_empty() && !s(&v, "sessionId").is_empty() {
            id = s(&v, "sessionId").to_string();
        }
        if !s(&v, "cwd").is_empty() {
            cwd = s(&v, "cwd").to_string();
        }
        let b = s(&v, "gitBranch");
        if !b.is_empty() && b != "HEAD" {
            branch = Some(b.to_string());
        }
        if let Some(t) = ts {
            started = started.min(t);
            last = last.max(t);
        }
        match s(&v, "type") {
            "last-prompt" => last_prompt = title_from(s(&v, "lastPrompt")),
            "user" if title.is_none() && v.get("isMeta").and_then(Value::as_bool) != Some(true) => {
                title = match v.pointer("/message/content") {
                    Some(Value::String(text)) => title_from(text),
                    Some(Value::Array(items)) => items
                        .iter()
                        .filter(|i| s(i, "type") == "text")
                        .find_map(|i| title_from(s(i, "text"))),
                    _ => None,
                };
            }
            "assistant" => {
                let Some(msg) = v.get("message") else { continue };
                let Some(usage) = msg.get("usage") else { continue };
                let key = [s(msg, "id"), s(&v, "requestId")].into_iter().find(|k| !k.is_empty()).unwrap_or_default().to_string();
                if !key.is_empty() && !seen.insert(key) {
                    continue;
                }
                let m = s(msg, "model");
                if m.is_empty() || m.starts_with('<') {
                    continue;
                }
                model = m.to_string();
                let tokens = Tokens {
                    input: u(usage, "input_tokens"),
                    output: u(usage, "output_tokens"),
                    cache_read: u(usage, "cache_read_input_tokens"),
                    cache_write: u(usage, "cache_creation_input_tokens"),
                };
                let c = claude_cost(m, &tokens);
                total.add(&tokens);
                cost += c;
                if let Some(t) = ts {
                    msgs.push(Msg { ts_ms: t, tokens, cost: c });
                }
            }
            _ => {}
        }
    }
    if msgs.is_empty() {
        return None;
    }
    if id.is_empty() {
        id = path.file_stem().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    }
    Some(FileSummary {
        session: SessionUsage {
            id,
            agent: Agent::ClaudeCode,
            project: folder(&cwd),
            title: title.or(last_prompt).unwrap_or_else(|| format!("Session in {}", folder(&cwd))),
            cwd,
            model,
            branch,
            tokens: total,
            cost_usd: cost,
            messages: msgs.len() as u32,
            started_ms: if started == i64::MAX { last } else { started },
            last_ms: last,
            transcript_path: path.to_string_lossy().into_owned(),
        },
        msgs,
        codex_limits: None,
    })
}

fn parse_codex(path: &Path) -> Option<FileSummary> {
    let mut msgs = Vec::new();
    let (mut id, mut cwd, mut model, mut title) = (String::new(), String::new(), String::new(), None::<String>);
    let mut total = Tokens::default();
    let mut cost = 0.0;
    let (mut started, mut last) = (i64::MAX, 0i64);
    let mut last_total_tokens = 0u64;
    let mut limits = None;
    for v in lines(path) {
        let ts = parse_iso_ms(s(&v, "timestamp"));
        if let Some(t) = ts {
            started = started.min(t);
            last = last.max(t);
        }
        let p = v.get("payload").cloned().unwrap_or(Value::Null);
        match (s(&v, "type"), s(&p, "type")) {
            ("session_meta", _) => {
                id = [s(&p, "id"), s(&p, "session_id")].into_iter().find(|k| !k.is_empty()).unwrap_or_default().to_string();
                if !s(&p, "cwd").is_empty() {
                    cwd = s(&p, "cwd").to_string();
                }
            }
            ("turn_context", _) => {
                if !s(&p, "model").is_empty() {
                    model = s(&p, "model").to_string();
                }
                if !s(&p, "cwd").is_empty() {
                    cwd = s(&p, "cwd").to_string();
                }
            }
            ("response_item", "message") if title.is_none() && s(&p, "role") == "user" => {
                title = p
                    .get("content")
                    .and_then(Value::as_array)
                    .and_then(|items| items.iter().find_map(|i| title_from(s(i, "text"))));
            }
            ("event_msg", "user_message") if title.is_none() => title = title_from(s(&p, "message")),
            ("event_msg", "token_count") => {
                if let Some(info) = p.get("info").filter(|i| !i.is_null()) {
                    let running = info.get("total_token_usage").map(|t| u(t, "total_tokens")).unwrap_or(0);
                    if running != last_total_tokens {
                        last_total_tokens = running;
                        if let Some(lu) = info.get("last_token_usage") {
                            let cached = u(lu, "cached_input_tokens");
                            let tokens = Tokens {
                                input: u(lu, "input_tokens").saturating_sub(cached),
                                output: u(lu, "output_tokens"),
                                cache_read: cached,
                                cache_write: u(lu, "cache_write_input_tokens"),
                            };
                            let c = codex_cost(&model, &tokens);
                            total.add(&tokens);
                            cost += c;
                            if let Some(t) = ts {
                                msgs.push(Msg { ts_ms: t, tokens, cost: c });
                            }
                        }
                    }
                }
                if let (Some(rl), Some(t)) = (p.get("rate_limits").filter(|r| r.is_object()), ts) {
                    let window = |w: Option<&Value>| {
                        let w = w.cloned().unwrap_or(Value::Null);
                        let resets = w.get("resets_at").and_then(Value::as_i64).map(|r| if r < 10_000_000_000 { r * 1000 } else { r });
                        LimitWindow {
                            used_tokens: 0,
                            limit_tokens: 0,
                            used_percent: w.get("used_percent").and_then(Value::as_f64).unwrap_or(0.0),
                            resets_at_ms: resets,
                            estimated: false,
                        }
                    };
                    limits = Some(CodexLimits {
                        five_hour: window(rl.get("primary")),
                        weekly: window(rl.get("secondary")),
                        plan: rl.get("plan_type").and_then(Value::as_str).map(str::to_string),
                        observed_ms: t,
                    });
                }
            }
            _ => {}
        }
    }
    if msgs.is_empty() && limits.is_none() {
        return None;
    }
    if id.is_empty() {
        id = path.file_stem().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    }
    Some(FileSummary {
        session: SessionUsage {
            id,
            agent: Agent::Codex,
            project: folder(&cwd),
            title: if model.contains("auto-review") {
                "Automatic review".into()
            } else {
                title.unwrap_or_else(|| format!("Session in {}", folder(&cwd)))
            },
            cwd,
            model,
            branch: None,
            tokens: total,
            cost_usd: cost,
            messages: msgs.len() as u32,
            started_ms: if started == i64::MAX { last } else { started },
            last_ms: last,
            transcript_path: path.to_string_lossy().into_owned(),
        },
        msgs,
        codex_limits: limits,
    })
}

/// Estimated API-equivalent cost in USD. Prices per million tokens by model family.
pub fn claude_cost(model: &str, t: &Tokens) -> f64 {
    let m = model.to_lowercase();
    let (input, output, write, read) = if m.contains("opus") {
        (5.0, 25.0, 6.25, 0.50)
    } else if m.contains("haiku") {
        (1.0, 5.0, 1.25, 0.10)
    } else {
        (3.0, 15.0, 3.75, 0.30)
    };
    per_million(t.input, input) + per_million(t.output, output) + per_million(t.cache_write, write) + per_million(t.cache_read, read)
}

pub fn codex_cost(model: &str, t: &Tokens) -> f64 {
    let m = model.to_lowercase();
    let (input, output, cached) = if m.contains("nano") {
        (0.05, 0.40, 0.005)
    } else if m.contains("mini") {
        (0.25, 2.00, 0.025)
    } else {
        (1.25, 10.0, 0.125)
    };
    per_million(t.input + t.cache_write, input) + per_million(t.output, output) + per_million(t.cache_read, cached)
}

fn per_million(n: u64, price: f64) -> f64 {
    n as f64 * price / 1_000_000.0
}

fn build_report(files: Vec<FileSummary>, o: ReportOptions) -> UsageReport {
    let offset = o.utc_offset_seconds as i64 * 1000;
    let local_day = |ts: i64| (ts + offset).div_euclid(DAY_MS);
    let today = local_day(o.now_ms);
    let first_day = today - (REPORT_DAYS - 1);

    let mut days: Vec<DayUsage> = (first_day..=today)
        .map(|d| DayUsage { day: format_day(d), claude_tokens: 0, codex_tokens: 0, cost_usd: 0.0, sessions: 0, cache_read_tokens: 0, prompt_tokens: 0 })
        .collect();
    let mut heatmap = vec![0u32; 7 * 24];
    let mut claude_msgs: Vec<(i64, u64)> = Vec::new();
    let (year, month, _) = civil_from_days(today);
    let month_start = days_from_civil(year, month, 1);
    let days_in_month = (days_from_civil(if month == 12 { year + 1 } else { year }, if month == 12 { 1 } else { month + 1 }, 1) - month_start) as u32;
    let mut m = MonthSummary { days_in_month, ..Default::default() };
    let mut month_tokens = Tokens::default();
    let mut active = HashSet::new();
    let mut codex: Option<CodexLimits> = None;

    for f in &files {
        let mut counted_days = HashSet::new();
        let mut in_month = false;
        for msg in &f.msgs {
            let d = local_day(msg.ts_ms);
            if d >= first_day && d <= today {
                let slot = &mut days[(d - first_day) as usize];
                match f.session.agent {
                    Agent::ClaudeCode => slot.claude_tokens += msg.tokens.total(),
                    Agent::Codex => slot.codex_tokens += msg.tokens.total(),
                }
                slot.cost_usd += msg.cost;
                slot.cache_read_tokens += msg.tokens.cache_read;
                slot.prompt_tokens += msg.tokens.input + msg.tokens.cache_read + msg.tokens.cache_write;
                if counted_days.insert(d) {
                    slot.sessions += 1;
                }
            }
            if d > today - 28 && d <= today {
                let local = msg.ts_ms + offset;
                let weekday = ((local.div_euclid(DAY_MS) + 3).rem_euclid(7)) as usize; // 1970-01-01 was a Thursday
                let hour = (local.rem_euclid(DAY_MS) / HOUR_MS) as usize;
                heatmap[weekday * 24 + hour] += 1;
            }
            if d >= month_start && d <= today {
                month_tokens.add(&msg.tokens);
                m.cost_usd += msg.cost;
                active.insert(d);
                in_month = true;
            }
            if f.session.agent == Agent::ClaudeCode {
                claude_msgs.push((msg.ts_ms, msg.tokens.billable()));
            }
        }
        if in_month {
            m.sessions += 1;
        }
        if let Some(l) = &f.codex_limits {
            if codex.as_ref().is_none_or(|c| l.observed_ms > c.observed_ms) {
                codex = Some(l.clone());
            }
        }
    }
    m.tokens = month_tokens.total();
    m.active_days = active.len() as u32;
    let elapsed = (today - month_start + 1).max(1) as f64;
    m.forecast_usd = m.cost_usd / elapsed * days_in_month as f64;
    let prompt_tokens = month_tokens.input + month_tokens.cache_read + month_tokens.cache_write;
    m.cache_hit_rate = if prompt_tokens == 0 { 0.0 } else { month_tokens.cache_read as f64 / prompt_tokens as f64 };

    claude_msgs.sort_unstable();
    let (claude_five_hour, claude_weekly) = claude_windows(&claude_msgs, o);

    let mut sessions: Vec<SessionUsage> = files.into_iter().map(|f| f.session).filter(|s| s.messages > 0).collect();
    sessions.sort_by(|a, b| b.last_ms.cmp(&a.last_ms));
    sessions.truncate(MAX_SESSIONS);

    UsageReport { sessions, days, heatmap, claude_five_hour, claude_weekly, codex, month: m, generated_ms: o.now_ms }
}

/// Claude's limits reset in 5-hour blocks that start with the first message after the
/// previous block ends, plus a rolling week. Without a user limit, the busiest past
/// window is treated as 100%.
fn claude_windows(msgs: &[(i64, u64)], o: ReportOptions) -> (LimitWindow, LimitWindow) {
    let mut blocks: Vec<(i64, u64)> = Vec::new();
    for &(ts, tokens) in msgs {
        match blocks.last_mut() {
            Some((start, sum)) if ts < *start + BLOCK_MS => *sum += tokens,
            _ => blocks.push((ts - ts.rem_euclid(HOUR_MS), tokens)),
        }
    }
    let current = blocks.last().filter(|(start, _)| o.now_ms < start + BLOCK_MS);
    let five_used = current.map(|(_, sum)| *sum).unwrap_or(0);
    let busiest_block = blocks.iter().map(|(_, sum)| *sum).max().unwrap_or(0);

    let week_used: u64 = msgs.iter().filter(|(ts, _)| *ts > o.now_ms - WEEK_MS).map(|(_, t)| t).sum();
    let mut busiest_week = 0u64;
    let mut window_sum = 0u64;
    let mut left = 0;
    for right in 0..msgs.len() {
        window_sum += msgs[right].1;
        while msgs[right].0 - msgs[left].0 >= WEEK_MS {
            window_sum -= msgs[left].1;
            left += 1;
        }
        busiest_week = busiest_week.max(window_sum);
    }
    let oldest_in_week = msgs.iter().find(|(ts, _)| *ts > o.now_ms - WEEK_MS).map(|(ts, _)| ts + WEEK_MS);

    let window = |used: u64, user_limit: u64, auto: u64, resets: Option<i64>| {
        let limit = if user_limit > 0 { user_limit } else { auto.max(1) };
        LimitWindow {
            used_tokens: used,
            limit_tokens: limit,
            used_percent: (used as f64 / limit as f64 * 100.0).min(100.0),
            resets_at_ms: resets,
            estimated: true,
        }
    };
    (
        window(five_used, o.claude_five_hour_limit, busiest_block, current.map(|(start, _)| start + BLOCK_MS)),
        window(week_used, o.claude_weekly_limit, busiest_week, oldest_in_week),
    )
}

/// Parses "2026-11-18T09:12:33.123Z" (or with a numeric offset) to Unix milliseconds.
pub fn parse_iso_ms(s: &str) -> Option<i64> {
    let b = s.as_bytes();
    if b.len() < 19 || b[4] != b'-' || b[10] != b'T' {
        return None;
    }
    let num = |r: std::ops::Range<usize>| s.get(r)?.parse::<i64>().ok();
    let (y, mo, d, h, mi, se) = (num(0..4)?, num(5..7)?, num(8..10)?, num(11..13)?, num(14..16)?, num(17..19)?);
    let mut rest = &s[19..];
    let mut ms = 0;
    if let Some(frac) = rest.strip_prefix('.') {
        let digits: String = frac.chars().take_while(char::is_ascii_digit).collect();
        ms = format!("{:0<3}", &digits[..digits.len().min(3)]).parse().unwrap_or(0);
        rest = &frac[digits.len()..];
    }
    let offset_ms = match rest.as_bytes().first() {
        Some(b'+') | Some(b'-') if rest.len() >= 6 => {
            let sign = if rest.starts_with('-') { -1 } else { 1 };
            sign * (rest[1..3].parse::<i64>().ok()? * 3600 + rest[4..6].parse::<i64>().ok()? * 60) * 1000
        }
        _ => 0,
    };
    Some((days_from_civil(y, mo as u32, d as u32) * 86_400 + h * 3600 + mi * 60 + se) * 1000 + ms - offset_ms)
}

/// Days since 1970-01-01 for a proleptic Gregorian date (Howard Hinnant's algorithm).
pub fn days_from_civil(y: i64, m: u32, d: u32) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (m as i64 + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d as i64 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

pub fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (yoe + era * 400 + if m <= 2 { 1 } else { 0 }, m, d)
}

fn format_day(days: i64) -> String {
    let (y, m, d) = civil_from_days(days);
    format!("{y:04}-{m:02}-{d:02}")
}

pub fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}
