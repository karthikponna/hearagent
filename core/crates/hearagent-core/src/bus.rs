//! Local event bus: hook processes send newline-delimited JSON events over a
//! Unix socket to the running app.

use crate::event::AgentEvent;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
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

/// Sends one event. Fails fast when no app is listening.
pub fn send_event(socket: &Path, event: &AgentEvent) -> std::io::Result<()> {
    let mut stream = UnixStream::connect(socket)?;
    stream.set_write_timeout(Some(Duration::from_millis(500)))?;
    let mut line = serde_json::to_string(event)?;
    line.push('\n');
    stream.write_all(line.as_bytes())
}

pub struct EventServer {
    path: PathBuf,
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

impl EventServer {
    pub fn start<F>(path: &Path, handler: F) -> std::io::Result<EventServer>
    where
        F: Fn(AgentEvent) + Send + Sync + 'static,
    {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let _ = std::fs::remove_file(path);
        let listener = UnixListener::bind(path)?;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;

        let stop = Arc::new(AtomicBool::new(false));
        let stop_flag = stop.clone();
        let handler = Arc::new(handler);
        let thread = std::thread::Builder::new().name("hearagent-bus".into()).spawn(move || {
            for conn in listener.incoming() {
                if stop_flag.load(Ordering::SeqCst) {
                    break;
                }
                let Ok(stream) = conn else { continue };
                let handler = handler.clone();
                std::thread::spawn(move || read_events(stream, &*handler));
            }
        })?;
        Ok(EventServer { path: path.to_path_buf(), stop, thread: Some(thread) })
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

fn read_events(stream: UnixStream, handler: &dyn Fn(AgentEvent)) {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(2)));
    for line in BufReader::new(stream).lines().map_while(Result::ok) {
        if let Ok(event) = serde_json::from_str::<AgentEvent>(&line) {
            handler(event);
        }
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
