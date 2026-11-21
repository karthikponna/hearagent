//! What Hear Agent asks the backend to say for each event worth speaking.

use crate::digest::TurnDigest;
use crate::event::{AgentEvent, EventKind};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Priority {
    Done,
    Failed,
    NeedsYou,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SpeechKind {
    /// Fixed sentence; the backend only voices it.
    Approval,
    /// The backend writes a summary of the finished turn, then voices it.
    Summary,
    /// The backend writes a short "this run stopped" line, then voices it.
    StopFailure,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct SpeechRequest {
    #[serde(skip)]
    pub id: u64,
    #[serde(skip)]
    pub session_key: String,
    /// Session event counter when this was created; later events make approvals stale.
    #[serde(skip)]
    pub session_seq: u64,
    #[serde(skip)]
    pub priority: Priority,
    pub kind: SpeechKind,
    pub agent: String,
    /// Spoken session name every line must start with.
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub final_message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub digest: Option<TurnDigest>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// Builds the request for an event, or `None` when the event is not spoken.
pub fn speech_for(event: &AgentEvent) -> Option<SpeechRequest> {
    let name = event.location.spoken_name();
    let base = |kind, priority| SpeechRequest {
        id: 0,
        session_key: String::new(),
        session_seq: 0,
        priority,
        kind,
        agent: event.agent.display_name().to_string(),
        name: name.clone(),
        text: None,
        final_message: None,
        digest: None,
        error: None,
    };
    match &event.kind {
        EventKind::ApprovalNeeded { action, .. } => Some(SpeechRequest {
            text: Some(format!("{name} needs approval to {action}.")),
            ..base(SpeechKind::Approval, Priority::NeedsYou)
        }),
        EventKind::Finished { message, digest } => {
            let priority = if asks_user(message) { Priority::NeedsYou } else { Priority::Done };
            Some(SpeechRequest {
                final_message: Some(message.clone()),
                digest: digest.clone(),
                ..base(SpeechKind::Summary, priority)
            })
        }
        EventKind::StoppedWithError { error, details, message } => {
            let reason = [error.as_str(), details.as_str(), message.as_str()]
                .iter()
                .filter(|s| !s.trim().is_empty())
                .cloned()
                .collect::<Vec<_>>()
                .join(" | ");
            Some(SpeechRequest { error: Some(reason), ..base(SpeechKind::StopFailure, Priority::Failed) })
        }
        EventKind::SessionStarted | EventKind::SessionEnded | EventKind::PromptSubmitted | EventKind::ToolStarted { .. } => None,
    }
}

/// True when the reply ends by asking the user something that blocks progress.
pub fn asks_user(message: &str) -> bool {
    let trimmed = message.trim().trim_end_matches(['*', '`', ' ']);
    if !trimmed.ends_with('?') {
        return false;
    }
    let last = trimmed.rsplit(['.', '!', '\n']).next().unwrap_or(trimmed).to_lowercase();
    let courtesy = ["want me to", "would you like", "should i also", "let me know", "anything else", "shall i also"];
    !courtesy.iter().any(|p| last.contains(p))
}

/// One short line for the session card in the menu.
pub fn display_update(event: &AgentEvent) -> Option<String> {
    let first_sentence = |s: &str| {
        let s = s.trim().replace(['*', '`', '#'], "");
        let s = s.split_whitespace().collect::<Vec<_>>().join(" ");
        let end = s.find(". ").map(|i| i + 1).unwrap_or(s.len());
        let line: String = s[..end].chars().take(140).collect();
        line
    };
    match &event.kind {
        EventKind::PromptSubmitted => Some("Working…".into()),
        EventKind::ApprovalNeeded { action, .. } => Some(format!("Needs approval to {action}")),
        EventKind::Finished { message, .. } => Some(if message.trim().is_empty() { "Finished".into() } else { first_sentence(message) }),
        EventKind::StoppedWithError { error, details, .. } => {
            let why = if details.is_empty() { error.clone() } else { details.clone() };
            Some(format!("Stopped: {}", if why.is_empty() { "API error".into() } else { why }))
        }
        EventKind::SessionStarted => Some("Session started".into()),
        EventKind::SessionEnded | EventKind::ToolStarted { .. } => None,
    }
}
