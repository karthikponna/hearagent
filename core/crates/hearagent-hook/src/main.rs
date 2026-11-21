//! Invoked by agent hooks as `hearagent-hook <agent>` with the hook payload on stdin.
//! Must never fail the agent: it always exits 0. It prints nothing, because Claude
//! Code feeds hook stdout back into the conversation, except for a permission
//! request answered from the notch, where it prints the allow or deny decision.
//!
//! Also: `hearagent-hook install|uninstall|status <agent>` for setup from a terminal.

use hearagent_core::bus::{default_socket_path, request_decision, send_event, Decision};
use hearagent_core::event::{Agent, AgentEvent, EventKind};
use hearagent_core::installer;
use std::io::Read;
use std::path::PathBuf;
use std::time::Duration;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some(cmd @ ("install" | "uninstall" | "status")) => std::process::exit(admin(cmd, &args[1..])),
        _ => relay(&args),
    }
}

fn relay(args: &[String]) {
    let dry_run = args.iter().any(|a| a == "--dry-run");
    let Some(agent) = args.iter().find_map(|a| Agent::from_arg(a)) else { return };

    let mut raw = String::new();
    if std::io::stdin().read_to_string(&mut raw).is_err() {
        return;
    }
    let Ok(payload) = serde_json::from_str(&raw) else { return };
    let Some(event) = AgentEvent::from_hook_payload(agent, &payload) else { return };

    if dry_run {
        println!("{}", serde_json::to_string(&event).unwrap_or_default());
        return;
    }
    if matches!(event.kind, EventKind::ApprovalNeeded { .. }) {
        let wait = match agent {
            Agent::ClaudeCode => installer::CLAUDE_APPROVAL_WAIT_SECS,
            Agent::Codex => installer::CODEX_APPROVAL_WAIT_SECS,
        };
        if let Some(output) = request_decision(&default_socket_path(), &event, Duration::from_secs(wait)).and_then(|d| decision_output(&d)) {
            println!("{output}");
        }
        return;
    }
    let _ = send_event(&default_socket_path(), &event);
}

/// The PermissionRequest output Claude Code and Codex both read. `None` lets the agent ask as usual.
fn decision_output(decision: &Decision) -> Option<String> {
    let decision = match decision {
        Decision::Allow => serde_json::json!({ "behavior": "allow" }),
        Decision::Deny { message } => serde_json::json!({
            "behavior": "deny",
            "message": if message.is_empty() { "Denied from Hear Agent." } else { message.as_str() },
        }),
        Decision::Ask => return None,
    };
    Some(serde_json::json!({ "hookSpecificOutput": { "hookEventName": "PermissionRequest", "decision": decision } }).to_string())
}

fn admin(cmd: &str, rest: &[String]) -> i32 {
    let Some(agent) = rest.first().and_then(|a| Agent::from_arg(a)) else {
        eprintln!("usage: hearagent-hook {cmd} claude-code|codex");
        return 2;
    };
    let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/tmp"));
    let result = match cmd {
        "install" => std::env::current_exe().and_then(|exe| installer::install(agent, &home, &exe)).map(|p| {
            println!("installed hooks in {}", p.display());
        }),
        "uninstall" => installer::uninstall(agent, &home).map(|removed| {
            println!("{}", if removed { "removed Hear Agent hooks" } else { "no Hear Agent hooks found" });
        }),
        _ => {
            match installer::installed_hook_command(agent, &home) {
                Some(c) => println!("installed: {c}"),
                None => println!("not installed"),
            }
            Ok(())
        }
    };
    match result {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("error: {e}");
            1
        }
    }
}
