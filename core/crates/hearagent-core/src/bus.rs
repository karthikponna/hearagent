//! Local event bus: hook processes send newline-delimited JSON events over a
//! Unix socket to the running app. An approval event can keep its connection
//! open and wait for one decision line back.

use crate::event::AgentEvent;
use serde::{Deserialize, Serialize};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::Duration;

pub fn app_support_dir() -> PathBuf {
    let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/tmp"));
    home.join("Library/Application Support/Hear Agent")
}

pub fn default_socket_path() -> PathBuf {
    match std::env::var_os("HEARAGENT_SOCKET") {
        Some(p) => PathBuf::from(p),
        None => app_support_dir().join("events.sock"),
    }
}

/// The answer to a permission request, sent from the app back to the waiting hook.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "decision", rename_all = "snake_case")]
pub enum Decision {
    Allow,
    Deny {
        #[serde(default)]
        message: String,
    },
    /// No decision: the agent shows its own prompt.
    Ask,
}

/// Sends one event. Fails fast when no app is listening.
pub fn send_event(socket: &Path, event: &AgentEvent) -> std::io::Result<()> {
    let mut stream = UnixStream::connect(socket)?;
    stream.set_write_timeout(Some(Duration::from_millis(500)))?;
    let mut line = serde_json::to_string(event)?;
    line.push('\n');
    stream.write_all(line.as_bytes())
}

/// Sends an approval event and waits up to `wait` for the app's decision.
/// `None` when no app is listening, the wait runs out, or the reply is unreadable.
pub fn request_decision(socket: &Path, event: &AgentEvent, wait: Duration) -> Option<Decision> {
    let mut event = event.clone();
    event.extra.awaits_decision = true;
    let mut stream = UnixStream::connect(socket).ok()?;
    stream.set_write_timeout(Some(Duration::from_millis(500))).ok()?;
    let mut line = serde_json::to_string(&event).ok()?;
    line.push('\n');
    stream.write_all(line.as_bytes()).ok()?;
    stream.set_read_timeout(Some(wait)).ok()?;
    let mut reply = String::new();
    BufReader::new(stream).read_line(&mut reply).ok()?;
    serde_json::from_str(reply.trim()).ok()
}

/// The open connection of a hook that waits for a decision.
pub struct Reply {
    pub id: u64,
    stream: Mutex<Option<UnixStream>>,
}

impl Reply {
    /// Sends the decision; later calls do nothing.
    pub fn send(&self, decision: &Decision) -> bool {
        let Some(mut stream) = self.stream.lock().unwrap().take() else { return false };
        let mut line = serde_json::to_string(decision).unwrap_or_default();
        line.push('\n');
        stream.write_all(line.as_bytes()).is_ok()
    }
}

pub trait BusHandler: Send + Sync {
    fn event(&self, event: AgentEvent);
    /// An approval whose hook is waiting. Answer through `reply`.
    fn approval(&self, event: AgentEvent, reply: Arc<Reply>);
    /// The waiting hook went away (answered in the terminal, timed out, or killed).
    fn approval_closed(&self, reply_id: u64);
}

struct ClosureHandler<F: Fn(AgentEvent) + Send + Sync>(F);

impl<F: Fn(AgentEvent) + Send + Sync> BusHandler for ClosureHandler<F> {
    fn event(&self, event: AgentEvent) {
        (self.0)(event)
    }
    fn approval(&self, event: AgentEvent, reply: Arc<Reply>) {
        reply.send(&Decision::Ask);
        (self.0)(event)
    }
    fn approval_closed(&self, _reply_id: u64) {}
}

pub struct EventServer {
    path: PathBuf,
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

impl EventServer {
    /// Delivers every event, approvals included, to one closure. Approvals get no decision.
    pub fn start<F>(path: &Path, handler: F) -> std::io::Result<EventServer>
    where
        F: Fn(AgentEvent) + Send + Sync + 'static,
    {
        Self::start_with(path, Arc::new(ClosureHandler(handler)))
    }

    pub fn start_with(path: &Path, handler: Arc<dyn BusHandler>) -> std::io::Result<EventServer> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let _ = std::fs::remove_file(path);
        let listener = UnixListener::bind(path)?;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;

        let stop = Arc::new(AtomicBool::new(false));
        let stop_flag = stop.clone();
        let next_id = Arc::new(AtomicU64::new(1));
        let thread = std::thread::Builder::new().name("hearagent-bus".into()).spawn(move || {
            for conn in listener.incoming() {
                if stop_flag.load(Ordering::SeqCst) {
                    break;
                }
                let Ok(stream) = conn else { continue };
                let handler = handler.clone();
                let next_id = next_id.clone();
                std::thread::spawn(move || read_events(stream, &*handler, &next_id));
            }
        })?;
        Ok(EventServer { path: path.to_path_buf(), stop, thread: Some(thread) })
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

fn read_events(stream: UnixStream, handler: &dyn BusHandler, next_id: &AtomicU64) {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(2)));
    let Ok(write_half) = stream.try_clone() else { return };
    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    loop {
        line.clear();
        match reader.read_line(&mut line) {
            Ok(0) | Err(_) => return,
            Ok(_) => {}
        }
        let Ok(event) = serde_json::from_str::<AgentEvent>(line.trim()) else { continue };
        if !event.extra.awaits_decision {
            handler.event(event);
            continue;
        }
        let id = next_id.fetch_add(1, Ordering::SeqCst);
        let reply = Arc::new(Reply { id, stream: Mutex::new(Some(write_half)) });
        handler.approval(event, reply);
        // Hold the connection until the hook exits, then say so.
        let _ = reader.get_ref().set_read_timeout(None);
        let mut rest = String::new();
        while matches!(reader.read_line(&mut rest), Ok(n) if n > 0) {
            rest.clear();
        }
        handler.approval_closed(id);
        return;
    }
}

impl Drop for EventServer {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        // Wake the blocking accept() so the thread can observe the stop flag.
        let _ = UnixStream::connect(&self.path);
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
        let _ = std::fs::remove_file(&self.path);
    }
}
