//! Finds local dev servers listening on this Mac (Next.js, Vite, FastAPI, ...).

use serde::Serialize;
use std::collections::{BTreeMap, HashMap};
use std::process::Command;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct DevServer {
    pub pid: u32,
    pub port: u16,
    pub process: String,
    pub framework: String,
    pub cwd: String,
    pub command: String,
    pub uptime_seconds: u64,
}

/// Lists listening TCP ports owned by the user's dev processes, lowest port first.
pub fn list() -> Vec<DevServer> {
    let Some(listen) = run("lsof", &["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]) else { return vec![] };
    let sockets = parse_lsof_listen(&listen);
    if sockets.is_empty() {
        return vec![];
    }
    let pids: Vec<String> = sockets.iter().map(|s| s.0.to_string()).collect::<std::collections::BTreeSet<_>>().into_iter().collect();
    let joined = pids.join(",");
    let cwds = run("lsof", &["-a", "-d", "cwd", "-p", &joined, "-Fpn"]).map(|o| parse_lsof_cwd(&o)).unwrap_or_default();
    let ps = run("ps", &["-o", "pid=,etime=,command=", "-p", &joined]).map(|o| parse_ps(&o)).unwrap_or_default();

    let mut out: Vec<DevServer> = sockets
        .into_iter()
        .filter_map(|(pid, process, port)| {
            let cwd = cwds.get(&pid).cloned().unwrap_or_default();
            let (uptime, command) = ps.get(&pid).cloned().unwrap_or_default();
            is_dev_server(&process, &cwd, &command, port).then(|| DevServer {
                framework: detect_framework(&process, &command, port),
                pid,
                port,
                process,
                cwd,
                command,
                uptime_seconds: uptime,
            })
        })
        .collect();
    out.sort_by_key(|s| s.port);
    out
}

/// Sends SIGTERM to the server's process.
pub fn stop(pid: u32) -> bool {
    Command::new("kill").arg(pid.to_string()).status().map(|s| s.success()).unwrap_or(false)
}

fn run(cmd: &str, args: &[&str]) -> Option<String> {
    let out = Command::new(cmd).args(args).output().ok()?;
    Some(String::from_utf8_lossy(&out.stdout).into_owned())
}

/// `lsof -F pcn` output: p<pid>, c<command>, then n<addr:port> lines. Deduplicates IPv4/IPv6.
pub fn parse_lsof_listen(output: &str) -> Vec<(u32, String, u16)> {
    let mut seen = BTreeMap::new();
    let (mut pid, mut cmd) = (0u32, String::new());
    for line in output.lines() {
        let (tag, value) = line.split_at(line.len().min(1));
        match tag {
            "p" => pid = value.parse().unwrap_or(0),
            "c" => cmd = value.to_string(),
            "n" => {
                if let Some(port) = value.rsplit(':').next().and_then(|p| p.parse::<u16>().ok()) {
                    seen.entry((pid, port)).or_insert_with(|| cmd.clone());
                }
            }
            _ => {}
        }
    }
    seen.into_iter().map(|((pid, port), cmd)| (pid, cmd, port)).collect()
}

pub fn parse_lsof_cwd(output: &str) -> HashMap<u32, String> {
    let mut map = HashMap::new();
    let mut pid = 0u32;
    for line in output.lines() {
        if let Some(p) = line.strip_prefix('p') {
            pid = p.parse().unwrap_or(0);
        } else if let Some(n) = line.strip_prefix('n') {
            map.insert(pid, n.to_string());
        }
    }
    map
}

/// `ps -o pid=,etime=,command=` rows -> pid -> (uptime seconds, command line).
pub fn parse_ps(output: &str) -> HashMap<u32, (u64, String)> {
    output
        .lines()
        .filter_map(|line| {
            let mut parts = line.split_whitespace();
            let pid = parts.next()?.parse().ok()?;
            let etime = parse_etime(parts.next()?)?;
            Some((pid, (etime, parts.collect::<Vec<_>>().join(" "))))
        })
        .collect()
}

/// "[[dd-]hh:]mm:ss" -> seconds.
pub fn parse_etime(s: &str) -> Option<u64> {
    let (days, rest) = match s.split_once('-') {
        Some((d, r)) => (d.parse::<u64>().ok()?, r),
        None => (0, s),
    };
    let parts: Vec<u64> = rest.split(':').map(|p| p.parse().ok()).collect::<Option<_>>()?;
    let (h, m, sec) = match parts.as_slice() {
        [m, s] => (0, *m, *s),
        [h, m, s] => (*h, *m, *s),
        _ => return None,
    };
    Some(days * 86_400 + h * 3600 + m * 60 + sec)
}

const RUNTIMES: &[&str] = &["node", "bun", "deno", "python", "python3", "ruby", "java", "php", "go", "uvicorn", "gunicorn", "workerd", "esbuild", "beam.smp", "dotnet", "cargo"];

pub fn is_dev_server(process: &str, cwd: &str, command: &str, port: u16) -> bool {
    if port < 1024 {
        return false;
    }
    let name = process.to_lowercase();
    if name.contains("helper") || command.contains(".app/Contents/") {
        return false;
    }
    let known = RUNTIMES.iter().any(|r| name == *r || name.starts_with(&format!("{r}.")) || name.starts_with(&format!("{r}3")))
        || ["postgres", "redis", "mysql", "mongod"].iter().any(|d| name.contains(d));
    let in_project = cwd.starts_with("/Users/") && cwd.matches('/').count() > 2;
    known || (in_project && !command.starts_with("/System/") && !command.starts_with("/usr/libexec/"))
}

pub fn detect_framework(process: &str, command: &str, port: u16) -> String {
    let c = command.to_lowercase();
    let rules: &[(&str, &str)] = &[
        ("next", "Next.js"),
        ("vite", "Vite"),
        ("expo", "Expo"),
        ("astro", "Astro"),
        ("nuxt", "Nuxt"),
        ("remix", "Remix"),
        ("storybook", "Storybook"),
        ("remotion", "Remotion"),
        ("wrangler", "Wrangler"),
        ("workerd", "Wrangler"),
        ("uvicorn", "FastAPI"),
        ("fastapi", "FastAPI"),
        ("manage.py", "Django"),
        ("flask", "Flask"),
        ("gunicorn", "Gunicorn"),
        ("rails", "Rails"),
        ("puma", "Rails"),
        ("webpack", "Webpack"),
        ("postgres", "Postgres"),
        ("redis", "Redis"),
        ("jupyter", "Jupyter"),
        ("streamlit", "Streamlit"),
    ];
    if let Some((_, name)) = rules.iter().find(|(needle, _)| c.contains(needle)) {
        return name.to_string();
    }
    if port == 8081 {
        return "Metro".into();
    }
    let mut p = process.to_string();
    if let Some(first) = p.get_mut(0..1) {
        first.make_ascii_uppercase();
    }
    p
}
