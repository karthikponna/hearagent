#![allow(dead_code)]

use hearagent_core::event::{Agent, AgentEvent};
use serde_json::Value;
use std::path::PathBuf;

pub fn fixtures_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../fixtures")
}

pub fn fixture(name: &str) -> Value {
    let raw = std::fs::read_to_string(fixtures_dir().join(name)).unwrap();
    let raw = raw.replace("FIXTURES", fixtures_dir().to_str().unwrap());
    serde_json::from_str(&raw).unwrap()
}

pub fn event(agent: Agent, name: &str) -> AgentEvent {
    AgentEvent::from_hook_payload(agent, &fixture(name)).expect("event should parse")
}
