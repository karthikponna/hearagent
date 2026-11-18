use hearagent_core::event::Agent;
use hearagent_core::installer::{backup_path, config_path, install, installed_hook_command, is_installed, uninstall};
use serde_json::{json, Value};
use std::path::Path;

const HOOK: &str = "/Applications/Hear Agent.app/Contents/MacOS/hearagent-hook";

fn read(path: &Path) -> Value {
    serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
}

fn write(path: &Path, v: &Value) {
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, serde_json::to_string_pretty(v).unwrap()).unwrap();
}

fn existing_claude_settings() -> Value {
    json!({
        "model": "opus",
        "permissions": { "allow": ["Bash(npm test)"] },
        "hooks": {
            "Stop": [{ "hooks": [{ "type": "command", "command": "afplay /System/Library/Sounds/Glass.aiff" }] }],
            "PreToolUse": [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "~/bin/guard.sh" }] }]
        }
    })
}

#[test]
fn install_into_empty_home_creates_config() {
    let home = tempfile::tempdir().unwrap();
    let path = install(Agent::ClaudeCode, home.path(), Path::new(HOOK)).unwrap();
    assert_eq!(path, config_path(Agent::ClaudeCode, home.path()));
    assert!(is_installed(Agent::ClaudeCode, home.path()));
    assert!(!backup_path(&path).exists(), "nothing to back up");

    let v = read(&path);
    let stop = &v["hooks"]["Stop"][0]["hooks"][0];
    assert_eq!(stop["command"], format!("'{HOOK}' claude-code"));
    assert_eq!(stop["async"], true);
    for event in ["SessionStart", "SessionEnd", "UserPromptSubmit", "PermissionRequest", "Stop", "StopFailure"] {
        assert!(v["hooks"][event].is_array(), "{event} installed");
    }
}

#[test]
fn install_keeps_user_settings_and_backs_up_once() {
    let home = tempfile::tempdir().unwrap();
    let path = config_path(Agent::ClaudeCode, home.path());
    let original = existing_claude_settings();
    write(&path, &original);

    install(Agent::ClaudeCode, home.path(), Path::new(HOOK)).unwrap();
    install(Agent::ClaudeCode, home.path(), Path::new("/new/place/hearagent-hook")).unwrap();

    let v = read(&path);
    assert_eq!(v["model"], "opus");
    assert_eq!(v["permissions"], original["permissions"]);
    let stop = v["hooks"]["Stop"].as_array().unwrap();
    assert_eq!(stop.len(), 2, "user's hook group plus exactly one of ours");
    assert_eq!(stop[0], original["hooks"]["Stop"][0]);
    assert_eq!(stop[1]["hooks"][0]["command"], "'/new/place/hearagent-hook' claude-code");
    assert_eq!(v["hooks"]["PreToolUse"][0], original["hooks"]["PreToolUse"][0]);

    assert_eq!(read(&backup_path(&path)), original, "backup holds the untouched original");
    assert_eq!(installed_hook_command(Agent::ClaudeCode, home.path()).unwrap(), "'/new/place/hearagent-hook' claude-code");

    // Keys keep their original order.
    let text = std::fs::read_to_string(&path).unwrap();
    assert!(text.find("\"model\"").unwrap() < text.find("\"permissions\"").unwrap());
}

#[test]
fn uninstall_restores_users_hooks_exactly() {
    let home = tempfile::tempdir().unwrap();
    let path = config_path(Agent::ClaudeCode, home.path());
    let original = existing_claude_settings();
    write(&path, &original);

    install(Agent::ClaudeCode, home.path(), Path::new(HOOK)).unwrap();
    assert!(uninstall(Agent::ClaudeCode, home.path()).unwrap());
    assert_eq!(read(&path), original);
    assert!(!is_installed(Agent::ClaudeCode, home.path()));
    assert!(!uninstall(Agent::ClaudeCode, home.path()).unwrap(), "second uninstall is a no-op");
}

#[test]
fn uninstall_removes_hooks_key_it_created() {
    let home = tempfile::tempdir().unwrap();
    let path = config_path(Agent::ClaudeCode, home.path());
    write(&path, &json!({ "theme": "dark" }));
    install(Agent::ClaudeCode, home.path(), Path::new(HOOK)).unwrap();
    uninstall(Agent::ClaudeCode, home.path()).unwrap();
    assert_eq!(read(&path), json!({ "theme": "dark" }));
}

#[test]
fn codex_uses_its_own_file_and_events() {
    let home = tempfile::tempdir().unwrap();
    let path = install(Agent::Codex, home.path(), Path::new(HOOK)).unwrap();
    assert!(path.ends_with(".codex/hooks.json"));
    let v = read(&path);
    assert_eq!(v["hooks"]["Stop"][0]["hooks"][0]["command"], format!("'{HOOK}' codex"));
    assert_eq!(v["hooks"]["Stop"][0]["hooks"][0]["timeout"], 5);
    assert!(v["hooks"]["PermissionRequest"].is_array());
    assert!(v["hooks"].get("PreToolUse").is_none(), "mid-run hooks are not installed");
    assert!(!is_installed(Agent::ClaudeCode, home.path()));
}

#[test]
fn invalid_json_is_left_alone() {
    let home = tempfile::tempdir().unwrap();
    let path = config_path(Agent::ClaudeCode, home.path());
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(&path, "{ not json").unwrap();
    assert!(install(Agent::ClaudeCode, home.path(), Path::new(HOOK)).is_err());
    assert_eq!(std::fs::read_to_string(&path).unwrap(), "{ not json");
}

#[test]
fn paths_with_spaces_and_quotes_are_shell_safe() {
    let home = tempfile::tempdir().unwrap();
    install(Agent::ClaudeCode, home.path(), Path::new("/Users/me/My Apps/it's/hearagent-hook")).unwrap();
    let cmd = installed_hook_command(Agent::ClaudeCode, home.path()).unwrap();
    assert_eq!(cmd, r"'/Users/me/My Apps/it'\''s/hearagent-hook' claude-code");
}
