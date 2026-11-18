//! Adds and removes Hear Agent's hook entries in agent config files, leaving
//! everything else in those files untouched.

use crate::event::Agent;
use serde_json::{json, Map, Value};
use std::io;
use std::path::{Path, PathBuf};

const MARKER: &str = "hearagent-hook";
/// Entries written before the rename are still recognised so they get replaced.
const LEGACY_MARKERS: &[&str] = &["murmur-hook"];
const CLAUDE_EVENTS: &[&str] = &["SessionStart", "SessionEnd", "UserPromptSubmit", "PermissionRequest", "Stop", "StopFailure"];
const CODEX_EVENTS: &[&str] = &["UserPromptSubmit", "PermissionRequest", "Stop"];

pub fn config_path(agent: Agent, home: &Path) -> PathBuf {
    match agent {
        Agent::ClaudeCode => home.join(".claude/settings.json"),
        Agent::Codex => home.join(".codex/hooks.json"),
    }
}

pub fn backup_path(config: &Path) -> PathBuf {
    let mut name = config.file_name().unwrap_or_default().to_os_string();
    name.push(".hearagent-backup");
    config.with_file_name(name)
}

fn events(agent: Agent) -> &'static [&'static str] {
    match agent {
        Agent::ClaudeCode => CLAUDE_EVENTS,
        Agent::Codex => CODEX_EVENTS,
    }
}

fn hook_command(agent: Agent, hook_binary: &Path) -> String {
    let arg = match agent {
        Agent::ClaudeCode => "claude-code",
        Agent::Codex => "codex",
    };
    let quoted = hook_binary.to_string_lossy().replace('\'', r"'\''");
    format!("'{quoted}' {arg}")
}

fn hook_entry(agent: Agent, hook_binary: &Path) -> Value {
    let command = hook_command(agent, hook_binary);
    match agent {
        // async: Claude Code continues without waiting for the hook.
        Agent::ClaudeCode => json!({ "type": "command", "command": command, "async": true }),
        Agent::Codex => json!({ "type": "command", "command": command, "timeout": 5 }),
    }
}

fn load(path: &Path) -> io::Result<Map<String, Value>> {
    match std::fs::read_to_string(path) {
        Ok(text) if text.trim().is_empty() => Ok(Map::new()),
        Ok(text) => match serde_json::from_str::<Value>(&text) {
            Ok(Value::Object(map)) => Ok(map),
            _ => Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!("{} is not a JSON object; leaving it unchanged", path.display()),
            )),
        },
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(Map::new()),
        Err(e) => Err(e),
    }
}

fn save(path: &Path, map: &Map<String, Value>) -> io::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let mut text = serde_json::to_string_pretty(map)?;
    text.push('\n');
    let tmp = path.with_extension("hearagent-tmp");
    std::fs::write(&tmp, text)?;
    std::fs::rename(&tmp, path)
}

fn is_ours(hook: &Value) -> bool {
    hook.get("command")
        .and_then(Value::as_str)
        .is_some_and(|c| c.contains(MARKER) || LEGACY_MARKERS.iter().any(|m| c.contains(m)))
}

/// Removes our hook entries, dropping groups and events that become empty.
fn strip_ours(hooks: &mut Map<String, Value>) {
    let events: Vec<String> = hooks.keys().cloned().collect();
    for event in events {
        let Some(groups) = hooks.get_mut(&event).and_then(Value::as_array_mut) else { continue };
        groups.retain_mut(|group| {
            let Some(list) = group.get_mut("hooks").and_then(Value::as_array_mut) else { return true };
            let before = list.len();
            list.retain(|h| !is_ours(h));
            !(before > 0 && list.is_empty())
        });
        if groups.is_empty() {
            hooks.remove(&event);
        }
    }
}

/// Installs hooks. Safe to call repeatedly; a previous Hear Agent entry is replaced.
pub fn install(agent: Agent, home: &Path, hook_binary: &Path) -> io::Result<PathBuf> {
    let path = config_path(agent, home);
    let mut root = load(&path)?;
    let backup = backup_path(&path);
    if path.exists() && !backup.exists() {
        std::fs::copy(&path, &backup)?;
    }
    let hooks = root.entry("hooks").or_insert_with(|| Value::Object(Map::new()));
    let Value::Object(hooks) = hooks else {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "\"hooks\" is not an object; leaving it unchanged"));
    };
    strip_ours(hooks);
    for event in events(agent) {
        let groups = hooks.entry(event.to_string()).or_insert_with(|| Value::Array(vec![]));
        if let Value::Array(groups) = groups {
            groups.push(json!({ "hooks": [hook_entry(agent, hook_binary)] }));
        }
    }
    save(&path, &root)?;
    Ok(path)
}

/// Removes only Hear Agent's entries. Returns whether anything was removed.
pub fn uninstall(agent: Agent, home: &Path) -> io::Result<bool> {
    let path = config_path(agent, home);
    if !path.exists() {
        return Ok(false);
    }
    let mut root = load(&path)?;
    let was_installed = installed_in(&root);
    if let Some(Value::Object(hooks)) = root.get_mut("hooks") {
        strip_ours(hooks);
        if hooks.is_empty() {
            root.remove("hooks");
        }
    }
    if was_installed {
        save(&path, &root)?;
    }
    Ok(was_installed)
}

fn installed_in(root: &Map<String, Value>) -> bool {
    root.get("hooks")
        .and_then(Value::as_object)
        .and_then(|h| h.get("Stop"))
        .and_then(Value::as_array)
        .is_some_and(|groups| {
            groups.iter().any(|g| g.get("hooks").and_then(Value::as_array).is_some_and(|l| l.iter().any(is_ours)))
        })
}

pub fn is_installed(agent: Agent, home: &Path) -> bool {
    load(&config_path(agent, home)).map(|root| installed_in(&root)).unwrap_or(false)
}

/// The hook binary path currently written into the config, if any.
pub fn installed_hook_command(agent: Agent, home: &Path) -> Option<String> {
    let root = load(&config_path(agent, home)).ok()?;
    root.get("hooks")?
        .get("Stop")?
        .as_array()?
        .iter()
        .filter_map(|g| g.get("hooks")?.as_array())
        .flatten()
        .find(|h| is_ours(h))
        .and_then(|h| h.get("command")?.as_str().map(str::to_string))
}
