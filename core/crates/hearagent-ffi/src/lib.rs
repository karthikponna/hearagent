//! Swift bridge for the Hear Agent engine.
//!
//! Threading: listener callbacks arrive on Rust background threads and are
//! never invoked while the engine lock is held, so Swift may call back into
//! the engine from inside a callback.

use hearagent_core::backend::{Account, Backend, BackendError, Credits, Renderer};
use hearagent_core::bus::{default_socket_path, BusHandler, Decision, EventServer, Reply};
use hearagent_core::dispatcher::{Dispatcher, DispatcherConfig, PendingApproval, ReadySpeech, SessionInfo, SessionStatus};
use hearagent_core::event::{Agent, AgentEvent, EventKind};
use hearagent_core::installer;
use hearagent_core::rules::{self, AllowRule};
use hearagent_core::transcript::{self, ChatRole, Todo, TodoStatus};
use hearagent_core::{servers, usage};
use hearagent_core::speech::{SpeechKind, SpeechRequest};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, Weak};
use std::time::{SystemTime, UNIX_EPOCH};

uniffi::setup_scaffolding!();

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum HearSpeechKind {
    Approval,
    Summary,
    StopFailure,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum HearSessionStatus {
    Working,
    NeedsYou,
    Failed,
    Done,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HearUtterance {
    pub id: u64,
    pub session_key: String,
    pub kind: HearSpeechKind,
    pub text: String,
    /// Encoded audio (MP3) to play.
    pub audio: Vec<u8>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum HearTodoStatus {
    Pending,
    InProgress,
    Completed,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HearTodo {
    pub id: String,
    pub content: String,
    pub status: HearTodoStatus,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HearActivity {
    pub tool: String,
    /// "Edit app/page.tsx", "Bash pnpm test".
    pub line: String,
    pub at_ms: u64,
}

/// A permission request waiting for an answer from the dashboard or notch.
#[derive(Debug, Clone, uniffi::Record)]
pub struct HearPendingApproval {
    pub id: u64,
    pub tool: String,
    /// The command, file or URL the call acts on.
    pub subject: String,
    pub action: String,
    pub at_ms: u64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HearSession {
    pub key: String,
    pub agent: String,
    pub name: String,
    pub cwd: String,
    pub status: HearSessionStatus,
    pub last_update: String,
    pub last_event_ms: u64,
    pub pinned: bool,
    pub session_id: String,
    pub transcript_path: String,
    pub last_prompt: String,
    pub last_message: String,
    pub activity: Option<HearActivity>,
    pub todos: Vec<HearTodo>,
    pub pending: Option<HearPendingApproval>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum HearDecision {
    Allow,
    Deny,
    /// Leave it to the agent's own prompt in the terminal.
    Ask,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct HearAllowRule {
    pub tool: String,
    pub pattern: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum HearChatRole {
    User,
    Assistant,
    Tools,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HearChatItem {
    pub role: HearChatRole,
    pub text: String,
    pub tools: Vec<String>,
    pub ts_ms: i64,
}

/// What the backend last said about the user's ability to hear updates.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum HearAccountState {
    SignedOut,
    NoSubscription,
    CreditsExhausted { period_end: Option<String> },
    Offline { message: String },
    Active { credits_remaining: i64, credits_total: i64, period_end: Option<String> },
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HearSubscription {
    pub status: String,
    pub active: bool,
    pub plan_id: String,
    pub plan_name: String,
    pub credits_total: i64,
    pub credits_used: i64,
    pub credits_remaining: i64,
    /// When credits next refill.
    pub period_end: Option<String>,
    /// When the plan renews; none for lifetime.
    pub renews_at: Option<String>,
    pub cancel_at_period_end: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HearAccount {
    pub email: String,
    pub name: String,
    pub subscription: Option<HearSubscription>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HearSignIn {
    pub url: String,
    pub verifier: String,
}

/// Supabase Auth providers the app offers.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum HearAuthProvider {
    Google,
    Apple,
}

#[derive(Debug, uniffi::Error)]
pub enum HearError {
    Io { message: String },
    SignedOut,
    NoSubscription,
    CreditsExhausted,
    Offline { message: String },
    Server { message: String },
}

impl std::error::Error for HearError {}

impl std::fmt::Display for HearError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            HearError::Io { message } | HearError::Offline { message } | HearError::Server { message } => write!(f, "{message}"),
            HearError::SignedOut => write!(f, "Signed out"),
            HearError::NoSubscription => write!(f, "No active subscription"),
            HearError::CreditsExhausted => write!(f, "Monthly credits used up"),
        }
    }
}

impl From<std::io::Error> for HearError {
    fn from(e: std::io::Error) -> Self {
        HearError::Io { message: e.to_string() }
    }
}

impl From<BackendError> for HearError {
    fn from(e: BackendError) -> Self {
        match e {
            BackendError::SignedOut => HearError::SignedOut,
            BackendError::NoSubscription => HearError::NoSubscription,
            BackendError::CreditsExhausted { .. } => HearError::CreditsExhausted,
            BackendError::Offline(message) => HearError::Offline { message },
            BackendError::Server(message) => HearError::Server { message },
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum AgentKind {
    ClaudeCode,
    Codex,
}

impl From<AgentKind> for Agent {
    fn from(a: AgentKind) -> Self {
        match a {
            AgentKind::ClaudeCode => Agent::ClaudeCode,
            AgentKind::Codex => Agent::Codex,
        }
    }
}

fn home_dir() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/tmp"))
}

/// Adds Hear Agent's hooks to the agent's config file. Returns the file path.
#[uniffi::export]
pub fn install_hooks(agent: AgentKind, hook_binary: String) -> Result<String, HearError> {
    let path = installer::install(agent.into(), &home_dir(), std::path::Path::new(&hook_binary))?;
    Ok(path.to_string_lossy().into_owned())
}

#[uniffi::export]
pub fn uninstall_hooks(agent: AgentKind) -> Result<bool, HearError> {
    Ok(installer::uninstall(agent.into(), &home_dir())?)
}

#[uniffi::export]
pub fn hooks_installed(agent: AgentKind) -> bool {
    installer::is_installed(agent.into(), &home_dir())
}

#[uniffi::export]
pub fn installed_hook_command(agent: AgentKind) -> Option<String> {
    installer::installed_hook_command(agent.into(), &home_dir())
}

#[uniffi::export]
pub fn agent_config_path(agent: AgentKind) -> String {
    installer::config_path(agent.into(), &home_dir()).to_string_lossy().into_owned()
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HearTokens {
    pub input: u64,
    pub output: u64,
    pub cache_read: u64,
    pub cache_write: u64,
    pub total: u64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HearSessionUsage {
    pub id: String,
    pub agent: AgentKind,
    pub project: String,
    pub cwd: String,
    pub title: String,
    pub model: String,
    pub branch: Option<String>,
    pub tokens: HearTokens,
    pub cost_usd: f64,
    pub messages: u32,
    pub started_ms: i64,
    pub last_ms: i64,
    pub transcript_path: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HearDayUsage {
    pub day: String,
    pub claude_tokens: u64,
    pub codex_tokens: u64,
    pub cost_usd: f64,
    pub sessions: u32,
    pub cache_read_tokens: u64,
    pub prompt_tokens: u64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HearLimitWindow {
    pub used_tokens: u64,
    pub limit_tokens: u64,
    pub used_percent: f64,
    pub resets_at_ms: Option<i64>,
    pub estimated: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HearCodexLimits {
    pub five_hour: HearLimitWindow,
    pub weekly: HearLimitWindow,
    pub plan: Option<String>,
    pub observed_ms: i64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HearMonthSummary {
    pub tokens: u64,
    pub cost_usd: f64,
    pub forecast_usd: f64,
    pub sessions: u32,
    pub active_days: u32,
    pub days_in_month: u32,
    pub cache_hit_rate: f64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HearUsageReport {
    pub sessions: Vec<HearSessionUsage>,
    pub days: Vec<HearDayUsage>,
    pub heatmap: Vec<u32>,
    pub claude_five_hour: HearLimitWindow,
    pub claude_weekly: HearLimitWindow,
    pub codex: Option<HearCodexLimits>,
    pub month: HearMonthSummary,
    pub generated_ms: i64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HearDevServer {
    pub pid: u32,
    pub port: u16,
    pub process: String,
    pub framework: String,
    pub cwd: String,
    pub command: String,
    pub uptime_seconds: u64,
}

/// Reads Claude Code and Codex session files on this Mac. Blocking; call off the main thread.
#[uniffi::export]
pub fn usage_report(utc_offset_seconds: i32, claude_five_hour_limit: u64, claude_weekly_limit: u64) -> HearUsageReport {
    let r = usage::scan(
        &home_dir(),
        usage::ReportOptions { now_ms: usage::now_ms(), utc_offset_seconds, claude_five_hour_limit, claude_weekly_limit },
    );
    let window = |w: usage::LimitWindow| HearLimitWindow {
        used_tokens: w.used_tokens,
        limit_tokens: w.limit_tokens,
        used_percent: w.used_percent,
        resets_at_ms: w.resets_at_ms,
        estimated: w.estimated,
    };
    HearUsageReport {
        sessions: r
            .sessions
            .into_iter()
            .map(|s| HearSessionUsage {
                id: s.id,
                agent: match s.agent {
                    Agent::ClaudeCode => AgentKind::ClaudeCode,
                    Agent::Codex => AgentKind::Codex,
                },
                project: s.project,
                cwd: s.cwd,
                title: s.title,
                model: s.model,
                branch: s.branch,
                tokens: HearTokens {
                    input: s.tokens.input,
                    output: s.tokens.output,
                    cache_read: s.tokens.cache_read,
                    cache_write: s.tokens.cache_write,
                    total: s.tokens.total(),
                },
                cost_usd: s.cost_usd,
                messages: s.messages,
                started_ms: s.started_ms,
                last_ms: s.last_ms,
                transcript_path: s.transcript_path,
            })
            .collect(),
        days: r
            .days
            .into_iter()
            .map(|d| HearDayUsage {
                day: d.day,
                claude_tokens: d.claude_tokens,
                codex_tokens: d.codex_tokens,
                cost_usd: d.cost_usd,
                sessions: d.sessions,
                cache_read_tokens: d.cache_read_tokens,
                prompt_tokens: d.prompt_tokens,
            })
            .collect(),
        heatmap: r.heatmap,
        claude_five_hour: window(r.claude_five_hour),
        claude_weekly: window(r.claude_weekly),
        codex: r.codex.map(|c| HearCodexLimits { five_hour: window(c.five_hour), weekly: window(c.weekly), plan: c.plan, observed_ms: c.observed_ms }),
        month: HearMonthSummary {
            tokens: r.month.tokens,
            cost_usd: r.month.cost_usd,
            forecast_usd: r.month.forecast_usd,
            sessions: r.month.sessions,
            active_days: r.month.active_days,
            days_in_month: r.month.days_in_month,
            cache_hit_rate: r.month.cache_hit_rate,
        },
        generated_ms: r.generated_ms,
    }
}

/// Local dev servers listening on this Mac. Blocking; call off the main thread.
#[uniffi::export]
pub fn dev_servers() -> Vec<HearDevServer> {
    servers::list()
        .into_iter()
        .map(|s| HearDevServer {
            pid: s.pid,
            port: s.port,
            process: s.process,
            framework: s.framework,
            cwd: s.cwd,
            command: s.command,
            uptime_seconds: s.uptime_seconds,
        })
        .collect()
}

#[uniffi::export]
pub fn stop_dev_server(pid: u32) -> bool {
    servers::stop(pid)
}

/// True when the installed hooks are missing events this version listens to.
#[uniffi::export]
pub fn hooks_need_upgrade(agent: AgentKind) -> bool {
    installer::needs_upgrade(agent.into(), &home_dir())
}

/// A session's conversation, oldest first. Blocking; call off the main thread.
#[uniffi::export]
pub fn chat_transcript(path: String, agent: AgentKind) -> Vec<HearChatItem> {
    transcript::chat(std::path::Path::new(&path), agent.into())
        .into_iter()
        .map(|i| HearChatItem {
            role: match i.role {
                ChatRole::User => HearChatRole::User,
                ChatRole::Assistant => HearChatRole::Assistant,
                ChatRole::Tools => HearChatRole::Tools,
            },
            text: i.text,
            tools: i.tools,
            ts_ms: i.ts_ms,
        })
        .collect()
}

/// The task list at the end of a Claude transcript.
#[uniffi::export]
pub fn transcript_todos(path: String) -> Vec<HearTodo> {
    transcript::todos(std::path::Path::new(&path)).into_iter().map(Into::into).collect()
}

/// The rule "Always allow" saves for a request.
#[uniffi::export]
pub fn suggest_allow_rule(tool: String, subject: String, cwd: String) -> HearAllowRule {
    let r = rules::suggest(&tool, &subject, &cwd);
    HearAllowRule { tool: r.tool, pattern: r.pattern }
}

impl From<Todo> for HearTodo {
    fn from(t: Todo) -> Self {
        HearTodo {
            id: t.id,
            content: t.content,
            status: match t.status {
                TodoStatus::Pending => HearTodoStatus::Pending,
                TodoStatus::InProgress => HearTodoStatus::InProgress,
                TodoStatus::Completed => HearTodoStatus::Completed,
            },
        }
    }
}

#[uniffi::export(with_foreign)]
pub trait EngineListener: Send + Sync {
    fn speak(&self, utterance: HearUtterance);
    fn sessions_changed(&self, sessions: Vec<HearSession>);
    fn account_state_changed(&self, state: HearAccountState);
    /// The Supabase session as JSON whenever it changes (sign-in, refresh), or none on sign-out.
    /// The app keeps it in the Keychain and hands it back with `set_session` on launch.
    fn session_changed(&self, session: Option<String>);
}

#[derive(uniffi::Object)]
pub struct Engine {
    dispatcher: Arc<Mutex<Dispatcher>>,
    listener: Arc<dyn EngineListener>,
    backend: Arc<Backend>,
    renderer: Arc<dyn Renderer>,
    server: Mutex<Option<EventServer>>,
    /// Hooks waiting for an approval decision, by approval id.
    replies: Mutex<HashMap<u64, Arc<Reply>>>,
    allow_rules: Mutex<Vec<AllowRule>>,
}

/// Routes bus traffic to the engine without keeping it alive.
struct Bus(Weak<Engine>);

impl BusHandler for Bus {
    fn event(&self, event: AgentEvent) {
        if let Some(engine) = self.0.upgrade() {
            engine.handle(event);
        }
    }
    fn approval(&self, event: AgentEvent, reply: Arc<Reply>) {
        if let Some(engine) = self.0.upgrade() {
            engine.handle_approval(event, reply);
        }
    }
    fn approval_closed(&self, reply_id: u64) {
        if let Some(engine) = self.0.upgrade() {
            engine.approval_closed(reply_id);
        }
    }
}

fn now_ms() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0)
}

#[uniffi::export]
impl Engine {
    #[uniffi::constructor]
    pub fn new(listener: Arc<dyn EngineListener>, api_base_url: String, supabase_url: String, supabase_key: String) -> Arc<Engine> {
        let backend = Arc::new(Backend::new(&api_base_url, &supabase_url, &supabase_key));
        Engine::build(listener, backend.clone(), backend)
    }

    /// Starts listening for hook events. Returns the socket path in use.
    pub fn start(self: Arc<Self>, socket_path: Option<String>) -> Result<String, HearError> {
        let path = socket_path.map(PathBuf::from).unwrap_or_else(default_socket_path);
        let server = EventServer::start_with(&path, Arc::new(Bus(Arc::downgrade(&self))))?;
        *self.server.lock().unwrap() = Some(server);
        Ok(path.to_string_lossy().into_owned())
    }

    pub fn stop(&self) {
        self.server.lock().unwrap().take();
    }

    /// Restores the session JSON saved from `session_changed`.
    pub fn set_session(&self, session: Option<String>) {
        self.backend.set_session(session);
    }

    pub fn start_sign_in(&self, provider: HearAuthProvider) -> HearSignIn {
        let s = self.backend.start_sign_in(match provider {
            HearAuthProvider::Google => "google",
            HearAuthProvider::Apple => "apple",
        });
        HearSignIn { url: s.url, verifier: s.verifier }
    }

    /// Completes sign-in with the code from `hearagent://auth?code=…`; the new session arrives via `session_changed`.
    pub fn finish_sign_in(&self, code: String, verifier: String) -> Result<(), HearError> {
        Ok(self.backend.finish_sign_in(&code, &verifier)?)
    }

    pub fn sign_out(&self) {
        self.backend.sign_out();
        self.listener.account_state_changed(HearAccountState::SignedOut);
    }

    pub fn fetch_account(&self) -> Result<HearAccount, HearError> {
        let account = self.backend.account().inspect_err(|e| self.report(e))?;
        if let Some(s) = &account.subscription {
            self.listener.account_state_changed(if !s.active {
                HearAccountState::NoSubscription
            } else if s.credits_remaining <= 0 {
                HearAccountState::CreditsExhausted { period_end: s.period_end.clone() }
            } else {
                HearAccountState::Active {
                    credits_remaining: s.credits_remaining,
                    credits_total: s.credits_total,
                    period_end: s.period_end.clone(),
                }
            });
        } else {
            self.listener.account_state_changed(HearAccountState::NoSubscription);
        }
        Ok(account.into())
    }

    /// `plan`: "monthly", "yearly" or "lifetime".
    pub fn checkout_url(&self, plan: String) -> Result<String, HearError> {
        Ok(self.backend.checkout_url(&plan)?)
    }

    pub fn portal_url(&self) -> Result<String, HearError> {
        Ok(self.backend.portal_url()?)
    }

    /// Feeds a raw hook payload directly, as if a hook had sent it.
    pub fn inject_payload(self: Arc<Self>, agent: String, payload_json: String) -> bool {
        let Some(agent) = Agent::from_arg(&agent) else { return false };
        let Ok(payload) = serde_json::from_str(&payload_json) else { return false };
        match AgentEvent::from_hook_payload(agent, &payload) {
            Some(event) => {
                self.handle(event);
                true
            }
            None => false,
        }
    }

    /// Call when playback finishes (or is skipped), so the next line can play.
    pub fn speech_finished(&self) {
        self.dispatcher.lock().unwrap().speech_finished();
        self.pump();
    }

    pub fn set_muted(&self, muted: bool) {
        self.dispatcher.lock().unwrap().set_muted(muted);
    }

    /// Turns approvals, summaries or stop alerts on or off.
    pub fn set_kind_enabled(&self, kind: HearSpeechKind, enabled: bool) {
        let kind = match kind {
            HearSpeechKind::Approval => SpeechKind::Approval,
            HearSpeechKind::Summary => SpeechKind::Summary,
            HearSpeechKind::StopFailure => SpeechKind::StopFailure,
        };
        self.dispatcher.lock().unwrap().set_kind_enabled(kind, enabled);
    }

    pub fn is_muted(&self) -> bool {
        self.dispatcher.lock().unwrap().is_muted()
    }

    pub fn set_pinned(&self, session_key: Option<String>) {
        let sessions = {
            let mut d = self.dispatcher.lock().unwrap();
            d.set_pinned(session_key.as_deref());
            d.sessions()
        };
        self.listener.sessions_changed(sessions.into_iter().map(Into::into).collect());
    }

    pub fn sessions(&self) -> Vec<HearSession> {
        self.dispatcher.lock().unwrap().sessions().into_iter().map(Into::into).collect()
    }

    /// Answers a waiting permission request. Returns false when its hook is already gone.
    pub fn decide(&self, approval_id: u64, decision: HearDecision) -> bool {
        let reply = self.replies.lock().unwrap().remove(&approval_id);
        let sent = reply.is_some_and(|r| {
            r.send(&match decision {
                HearDecision::Allow => Decision::Allow,
                HearDecision::Deny => Decision::Deny { message: String::new() },
                HearDecision::Ask => Decision::Ask,
            })
        });
        let changed = self.dispatcher.lock().unwrap().clear_pending(approval_id, decision != HearDecision::Ask, now_ms());
        if changed {
            self.notify_sessions();
        }
        sent
    }

    /// Requests matching one of these are allowed without asking.
    pub fn set_allow_rules(&self, rules: Vec<HearAllowRule>) {
        *self.allow_rules.lock().unwrap() = rules.into_iter().map(|r| AllowRule { tool: r.tool, pattern: r.pattern }).collect();
    }
}

impl Engine {
    /// Engine with a custom renderer (tests use a fake backend).
    pub fn build(listener: Arc<dyn EngineListener>, backend: Arc<Backend>, renderer: Arc<dyn Renderer>) -> Arc<Engine> {
        let sessions = listener.clone();
        backend.on_session_changed(Box::new(move |session| sessions.session_changed(session)));
        Arc::new(Engine {
            dispatcher: Arc::new(Mutex::new(Dispatcher::new(DispatcherConfig::default()))),
            listener,
            backend,
            renderer,
            server: Mutex::new(None),
            replies: Mutex::new(HashMap::new()),
            allow_rules: Mutex::new(Vec::new()),
        })
    }

    fn notify_sessions(&self) {
        let sessions = self.dispatcher.lock().unwrap().sessions();
        self.listener.sessions_changed(sessions.into_iter().map(Into::into).collect());
    }

    fn handle_approval(self: &Arc<Self>, event: AgentEvent, reply: Arc<Reply>) {
        let EventKind::ApprovalNeeded { tool, action } = &event.kind else {
            self.handle(event);
            return;
        };
        let subject = event.extra.subject.clone();
        if rules::any_matches(&self.allow_rules.lock().unwrap(), tool, &subject, &event.cwd) {
            reply.send(&Decision::Allow);
            return;
        }
        let pending = PendingApproval { id: reply.id, tool: tool.clone(), subject, action: action.clone(), at_ms: now_ms() };
        let key = Dispatcher::session_key(event.agent, &event.session_id);
        self.replies.lock().unwrap().insert(reply.id, reply);
        let request = {
            let mut d = self.dispatcher.lock().unwrap();
            let request = d.ingest(event, now_ms());
            d.set_pending(&key, pending);
            request
        };
        self.notify_sessions();
        self.speak_later(request);
    }

    fn approval_closed(&self, reply_id: u64) {
        let waiting = self.replies.lock().unwrap().remove(&reply_id).is_some();
        if waiting && self.dispatcher.lock().unwrap().clear_pending(reply_id, false, now_ms()) {
            self.notify_sessions();
        }
    }

    fn speak_later(self: &Arc<Self>, request: Option<SpeechRequest>) {
        if let Some(request) = request {
            let engine = Arc::downgrade(self);
            std::thread::spawn(move || {
                if let Some(engine) = engine.upgrade() {
                    engine.render(request);
                }
            });
        }
    }

    fn handle(self: &Arc<Self>, event: AgentEvent) {
        let (request, sessions) = {
            let mut d = self.dispatcher.lock().unwrap();
            let request = d.ingest(event, now_ms());
            (request, d.sessions())
        };
        self.listener.sessions_changed(sessions.into_iter().map(Into::into).collect());
        if let Some(request) = request {
            let engine = Arc::downgrade(self);
            std::thread::spawn(move || {
                if let Some(engine) = engine.upgrade() {
                    engine.render(request);
                }
            });
        }
    }

    fn render(&self, request: SpeechRequest) {
        match self.renderer.render(&request) {
            Ok(rendered) => {
                if let Some(c) = rendered.credits.clone() {
                    self.listener.account_state_changed(active_state(c));
                }
                let ready = ReadySpeech {
                    request_id: request.id,
                    session_key: request.session_key.clone(),
                    session_seq: request.session_seq,
                    kind: request.kind,
                    priority: request.priority,
                    text: rendered.text,
                    audio: rendered.audio,
                };
                self.dispatcher.lock().unwrap().enqueue(ready, now_ms());
                self.pump();
            }
            Err(e) => self.report(&e),
        }
    }

    fn report(&self, e: &BackendError) {
        self.listener.account_state_changed(match e {
            BackendError::SignedOut => HearAccountState::SignedOut,
            BackendError::NoSubscription => HearAccountState::NoSubscription,
            BackendError::CreditsExhausted { period_end } => HearAccountState::CreditsExhausted { period_end: period_end.clone() },
            BackendError::Offline(m) | BackendError::Server(m) => HearAccountState::Offline { message: m.clone() },
        });
    }

    fn pump(&self) {
        let next = self.dispatcher.lock().unwrap().next(now_ms());
        if let Some(s) = next {
            self.listener.speak(HearUtterance {
                id: s.request_id,
                session_key: s.session_key,
                kind: s.kind.into(),
                text: s.text,
                audio: s.audio,
            });
        }
    }
}

fn active_state(c: Credits) -> HearAccountState {
    if c.credits_remaining <= 0 {
        HearAccountState::CreditsExhausted { period_end: c.period_end }
    } else {
        HearAccountState::Active { credits_remaining: c.credits_remaining, credits_total: c.credits_total, period_end: c.period_end }
    }
}

impl From<SpeechKind> for HearSpeechKind {
    fn from(k: SpeechKind) -> Self {
        match k {
            SpeechKind::Approval => HearSpeechKind::Approval,
            SpeechKind::Summary => HearSpeechKind::Summary,
            SpeechKind::StopFailure => HearSpeechKind::StopFailure,
        }
    }
}

impl From<SessionInfo> for HearSession {
    fn from(s: SessionInfo) -> Self {
        HearSession {
            key: s.key,
            agent: s.agent.display_name().to_string(),
            name: s.name,
            cwd: s.cwd,
            status: match s.status {
                SessionStatus::Working => HearSessionStatus::Working,
                SessionStatus::NeedsYou => HearSessionStatus::NeedsYou,
                SessionStatus::Failed => HearSessionStatus::Failed,
                SessionStatus::Done => HearSessionStatus::Done,
            },
            last_update: s.last_update,
            last_event_ms: s.last_event_ms,
            pinned: s.pinned,
            session_id: s.session_id,
            transcript_path: s.transcript_path,
            last_prompt: s.last_prompt,
            last_message: s.last_message,
            activity: s.activity.map(|a| HearActivity { tool: a.tool, line: a.line, at_ms: a.at_ms }),
            todos: s.todos.into_iter().map(Into::into).collect(),
            pending: s.pending.map(|p| HearPendingApproval { id: p.id, tool: p.tool, subject: p.subject, action: p.action, at_ms: p.at_ms }),
        }
    }
}

impl From<Account> for HearAccount {
    fn from(a: Account) -> Self {
        HearAccount {
            email: a.email,
            name: a.name,
            subscription: a.subscription.map(|s| HearSubscription {
                status: s.status,
                active: s.active,
                plan_id: s.plan_id,
                plan_name: s.plan_name,
                credits_total: s.credits_total,
                credits_used: s.credits_used,
                credits_remaining: s.credits_remaining,
                period_end: s.period_end,
                renews_at: s.renews_at,
                cancel_at_period_end: s.cancel_at_period_end,
            }),
        }
    }
}
