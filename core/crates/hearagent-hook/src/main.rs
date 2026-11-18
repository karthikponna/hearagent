//! Invoked by agent hooks as `hearagent-hook <agent>` with the hook payload on stdin.
//! Must never block or fail the agent: it always exits 0 and prints nothing,
//! because Claude Code feeds hook stdout back into the conversation.
//!
//! Also: `hearagent-hook install|uninstall|status <agent>` for setup from a terminal.

use hearagent_core::bus::{default_socket_path, send_event};
use hearagent_core::event::{Agent, AgentEvent};
use hearagent_core::installer;
use std::io::Read;
use std::path::PathBuf;

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
    let _ = send_event(&default_socket_path(), &event);
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
