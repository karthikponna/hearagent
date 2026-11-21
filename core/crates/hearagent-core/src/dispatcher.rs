//! Tracks live agent sessions and decides which rendered line to play next.
//! Pure state machine: callers pass the current time, so every rule is testable.
//!
//! Flow: `ingest` turns an event into a `SpeechRequest`; the caller renders it
//! (text + audio from the backend) and hands it back via `enqueue`; `next`
//! picks what to play whenever the speaker is idle.

use crate::event::{Agent, AgentEvent, EventKind};
use crate::speech::{display_update, speech_for, Priority, SpeechKind, SpeechRequest};
use crate::transcript::{apply_task_tool, tool_line, Todo};
use serde::Serialize;
use std::collections::HashMap;

/// The tool call a session is running right now.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Activity {
    pub tool: String,
    /// "Edit app/page.tsx", "Bash pnpm test".
    pub line: String,
    pub at_ms: u64,
}

/// A permission request whose hook is waiting for an answer.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct PendingApproval {
    pub id: u64,
    pub tool: String,
    pub subject: String,
    pub action: String,
    pub at_ms: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SessionStatus {
    Working,
    NeedsYou,
    Failed,
    Done,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct SessionInfo {
    pub key: String,
    pub agent: Agent,
    /// UI label, e.g. "auth-service · tool-timeout-mcp".
    pub name: String,
    pub cwd: String,
    pub status: SessionStatus,
    pub last_update: String,
    pub last_event_ms: u64,
    pub pinned: bool,
    pub session_id: String,
    pub transcript_path: String,
    pub last_prompt: String,
    pub last_message: String,
    pub activity: Option<Activity>,
    pub todos: Vec<Todo>,
    pub pending: Option<PendingApproval>,
    #[serde(skip)]
    seq: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ReadySpeech {
    pub request_id: u64,
    pub session_key: String,
    pub session_seq: u64,
    pub kind: SpeechKind,
    pub priority: Priority,
    pub text: String,
    pub audio: Vec<u8>,
}

#[derive(Debug, Clone)]
pub struct DispatcherConfig {
    pub done_stale_ms: u64,
    pub needs_you_stale_ms: u64,
    pub session_expiry_ms: u64,
}

impl Default for DispatcherConfig {
    fn default() -> Self {
        DispatcherConfig { done_stale_ms: 5 * 60_000, needs_you_stale_ms: 10 * 60_000, session_expiry_ms: 6 * 60 * 60_000 }
    }
}

#[derive(Debug, Clone)]
struct Queued {
    speech: ReadySpeech,
    queued_ms: u64,
}

pub struct Dispatcher {
    pub config: DispatcherConfig,
    sessions: HashMap<String, SessionInfo>,
    queue: Vec<Queued>,
    next_id: u64,
    muted: bool,
    speaking: bool,
    disabled_kinds: Vec<SpeechKind>,
}

impl Dispatcher {
    pub fn new(config: DispatcherConfig) -> Self {
        Dispatcher {
            config,
            sessions: HashMap::new(),
            queue: Vec::new(),
            next_id: 1,
            muted: false,
            speaking: false,
            disabled_kinds: Vec::new(),
        }
    }

    pub fn session_key(agent: Agent, session_id: &str) -> String {
        let a = match agent {
            Agent::ClaudeCode => "claude-code",
            Agent::Codex => "codex",
        };
        format!("{a}:{session_id}")
    }

    /// Updates session state. Returns what to render, if this event is spoken.
    pub fn ingest(&mut self, event: AgentEvent, now_ms: u64) -> Option<SpeechRequest> {
        let key = Self::session_key(event.agent, &event.session_id);
        if event.kind == EventKind::SessionEnded {
            self.sessions.remove(&key);
            self.queue.retain(|q| q.speech.session_key != key);
            return None;
        }
        let session = self.sessions.entry(key.clone()).or_insert_with(|| SessionInfo {
            key: key.clone(),
            agent: event.agent,
            name: event.location.display_name(),
            cwd: event.cwd.clone(),
            status: SessionStatus::Working,
            last_update: String::new(),
            last_event_ms: now_ms,
            pinned: false,
            session_id: event.session_id.clone(),
            transcript_path: String::new(),
            last_prompt: String::new(),
            last_message: String::new(),
            activity: None,
            todos: Vec::new(),
            pending: None,
            seq: 0,
        });
        session.last_event_ms = now_ms;
        if !event.cwd.is_empty() {
            session.cwd = event.cwd.clone();
            session.name = event.location.display_name();
        }
        if !event.extra.transcript_path.is_empty() {
            session.transcript_path = event.extra.transcript_path.clone();
        }

        // Tool calls update what the session is doing but are never spoken, and
        // don't count as "newer" for a waiting approval line.
        if let EventKind::ToolStarted { tool, input } = &event.kind {
            if !apply_task_tool(&mut session.todos, tool, input) {
                session.activity = Some(Activity { tool: tool.clone(), line: tool_line(tool, Some(input)), at_ms: now_ms });
            }
            if session.pending.is_none() {
                session.status = SessionStatus::Working;
            }
            return None;
        }

        session.seq += 1;
        if let Some(update) = display_update(&event) {
            session.last_update = update;
        }
        match &event.kind {
            EventKind::PromptSubmitted => {
                if !event.extra.prompt.trim().is_empty() {
                    session.last_prompt = event.extra.prompt.trim().to_string();
                }
                session.last_message.clear();
                session.activity = None;
                session.pending = None;
            }
            EventKind::Finished { message, .. } => {
                session.last_message = message.trim().to_string();
                session.activity = None;
                session.pending = None;
            }
            EventKind::StoppedWithError { .. } => {
                session.activity = None;
                session.pending = None;
            }
            _ => {}
        }

        let mut request = speech_for(&event);
        session.status = match request.as_ref().map(|r| r.priority) {
            Some(Priority::NeedsYou) => SessionStatus::NeedsYou,
            Some(Priority::Failed) => SessionStatus::Failed,
            Some(Priority::Done) => SessionStatus::Done,
            None => SessionStatus::Working,
        };
        let seq = session.seq;
        // Anything newer from a session makes its unplayed approval prompt out of date.
        self.queue.retain(|q| !(q.speech.session_key == key && q.speech.kind == SpeechKind::Approval));

        if self.muted || request.as_ref().is_some_and(|r| self.disabled_kinds.contains(&r.kind)) {
            return None;
        }
        if let Some(r) = request.as_mut() {
            r.id = self.next_id;
            self.next_id += 1;
            r.session_key = key;
            r.session_seq = seq;
        }
        request
    }

    /// Adds a rendered line, unless the session has moved on since it was requested.
    pub fn enqueue(&mut self, speech: ReadySpeech, now_ms: u64) {
        if self.muted {
            return;
        }
        let Some(session) = self.sessions.get(&speech.session_key) else { return };
        if speech.kind == SpeechKind::Approval && session.seq != speech.session_seq {
            return;
        }
        self.queue.retain(|q| !(q.speech.session_key == speech.session_key && q.speech.priority <= speech.priority));
        self.queue.push(Queued { speech, queued_ms: now_ms });
    }

    /// The next line to play, if the speaker is idle.
    pub fn next(&mut self, now_ms: u64) -> Option<ReadySpeech> {
        if self.muted || self.speaking {
            return None;
        }
        self.drop_stale(now_ms);
        let pinned = self.pinned_key();
        let idx = self
            .queue
            .iter()
            .enumerate()
            .max_by(|(_, a), (_, b)| {
                let a_pin = pinned.as_ref() == Some(&a.speech.session_key);
                let b_pin = pinned.as_ref() == Some(&b.speech.session_key);
                a.speech
                    .priority
                    .cmp(&b.speech.priority)
                    .then(a_pin.cmp(&b_pin))
                    .then(b.queued_ms.cmp(&a.queued_ms))
                    .then(b.speech.request_id.cmp(&a.speech.request_id))
            })
            .map(|(i, _)| i)?;
        self.speaking = true;
        Some(self.queue.remove(idx).speech)
    }

    pub fn speech_finished(&mut self) {
        self.speaking = false;
    }

    fn drop_stale(&mut self, now_ms: u64) {
        let c = &self.config;
        self.queue.retain(|q| {
            let age = now_ms.saturating_sub(q.queued_ms);
            match q.speech.priority {
                Priority::NeedsYou => age < c.needs_you_stale_ms,
                Priority::Done | Priority::Failed => age < c.done_stale_ms,
            }
        });
        let expiry = c.session_expiry_ms;
        self.sessions.retain(|_, s| now_ms.saturating_sub(s.last_event_ms) < expiry);
    }

    fn pinned_key(&self) -> Option<String> {
        self.sessions.values().find(|s| s.pinned).map(|s| s.key.clone())
    }

    /// Records that a session's approval hook is waiting on `approval.id`.
    pub fn set_pending(&mut self, session_key: &str, approval: PendingApproval) {
        if let Some(s) = self.sessions.get_mut(session_key) {
            s.pending = Some(approval);
            s.status = SessionStatus::NeedsYou;
        }
    }

    /// The session waiting on an approval id.
    pub fn pending_session(&self, approval_id: u64) -> Option<SessionInfo> {
        self.sessions.values().find(|s| s.pending.as_ref().is_some_and(|p| p.id == approval_id)).cloned()
    }

    /// Clears a waiting approval once it is answered or its hook goes away.
    /// `answered` moves the session back to working and drops its unplayed approval line.
    pub fn clear_pending(&mut self, approval_id: u64, answered: bool, now_ms: u64) -> bool {
        let Some(s) = self.sessions.values_mut().find(|s| s.pending.as_ref().is_some_and(|p| p.id == approval_id)) else {
            return false;
        };
        s.pending = None;
        if answered {
            s.status = SessionStatus::Working;
            s.last_update = "Working…".into();
            s.last_event_ms = now_ms;
            s.seq += 1;
            let key = s.key.clone();
            self.queue.retain(|q| !(q.speech.session_key == key && q.speech.kind == SpeechKind::Approval));
        }
        true
    }

    /// Pins one session (or none); a pinned session's lines win ties.
    pub fn set_pinned(&mut self, key: Option<&str>) {
        for s in self.sessions.values_mut() {
            s.pinned = Some(s.key.as_str()) == key;
        }
    }

    pub fn set_muted(&mut self, muted: bool) {
        self.muted = muted;
        if muted {
            self.queue.clear();
        }
    }

    /// Turns one kind of spoken line on or off. Off means it is never sent to the backend.
    pub fn set_kind_enabled(&mut self, kind: SpeechKind, enabled: bool) {
        self.disabled_kinds.retain(|k| *k != kind);
        if !enabled {
            self.disabled_kinds.push(kind);
        }
    }

    pub fn is_muted(&self) -> bool {
        self.muted
    }

    pub fn pending_len(&self) -> usize {
        self.queue.len()
    }

    /// Sessions ordered by who needs attention first, then most recent.
    pub fn sessions(&self) -> Vec<SessionInfo> {
        let rank = |s: &SessionStatus| match s {
            SessionStatus::NeedsYou => 0,
            SessionStatus::Failed => 1,
            SessionStatus::Working => 2,
            SessionStatus::Done => 3,
        };
        let mut v: Vec<SessionInfo> = self.sessions.values().cloned().collect();
        v.sort_by(|a, b| rank(&a.status).cmp(&rank(&b.status)).then(b.last_event_ms.cmp(&a.last_event_ms)));
        v
    }
}
