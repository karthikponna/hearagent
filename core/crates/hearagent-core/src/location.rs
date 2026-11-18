//! Works out what to call a session: its worktree, or its project and branch.

use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct Location {
    /// Repository folder name (or the plain folder when not in git).
    pub project: String,
    /// Linked worktree folder name, when the session runs inside one.
    pub worktree: Option<String>,
    pub branch: Option<String>,
}

impl Location {
    pub fn detect(cwd: &Path) -> Location {
        let fallback = folder_name(cwd).unwrap_or_else(|| "your project".into());
        let Some((root, git)) = find_git(cwd) else {
            return Location { project: fallback, worktree: None, branch: None };
        };
        let root_name = folder_name(&root).unwrap_or(fallback);
        match git {
            Git::Dir(dir) => Location { project: root_name, worktree: None, branch: read_branch(&dir) },
            Git::Worktree(gitdir) => {
                // gitdir: <main repo>/.git/worktrees/<name>
                let main_repo = gitdir.parent().and_then(Path::parent).and_then(Path::parent);
                let project = main_repo.and_then(folder_name).unwrap_or_else(|| root_name.clone());
                Location { project, worktree: Some(root_name), branch: read_branch(&gitdir) }
            }
        }
    }

    /// Name spoken at the start of every line, e.g. "auth service, tool timeout mcp branch".
    pub fn spoken_name(&self) -> String {
        if let Some(w) = &self.worktree {
            return speakable(w);
        }
        match self.branch.as_deref() {
            Some(b) if !is_default_branch(b) => format!("{}, {} branch", speakable(&self.project), speakable(b)),
            _ => speakable(&self.project),
        }
    }

    /// Short label for the UI, e.g. "auth-service · tool-timeout-mcp".
    pub fn display_name(&self) -> String {
        if let Some(w) = &self.worktree {
            return w.clone();
        }
        match self.branch.as_deref() {
            Some(b) if !is_default_branch(b) => format!("{} · {b}", self.project),
            _ => self.project.clone(),
        }
    }
}

fn is_default_branch(b: &str) -> bool {
    matches!(b, "main" | "master")
}

/// "feature/tool-timeout_mcp" -> "feature tool timeout mcp".
pub fn speakable(name: &str) -> String {
    name.replace(['-', '_', '.', '/'], " ").split_whitespace().collect::<Vec<_>>().join(" ")
}

fn folder_name(p: &Path) -> Option<String> {
    p.file_name().map(|n| n.to_string_lossy().into_owned()).filter(|n| !n.is_empty())
}

enum Git {
    Dir(PathBuf),
    Worktree(PathBuf),
}

fn find_git(cwd: &Path) -> Option<(PathBuf, Git)> {
    for dir in cwd.ancestors() {
        let dot_git = dir.join(".git");
        if dot_git.is_dir() {
            return Some((dir.to_path_buf(), Git::Dir(dot_git)));
        }
        if dot_git.is_file() {
            let text = std::fs::read_to_string(&dot_git).ok()?;
            let gitdir = text.trim().strip_prefix("gitdir:")?.trim();
            let gitdir = if Path::new(gitdir).is_absolute() { PathBuf::from(gitdir) } else { dir.join(gitdir) };
            // Submodules also use a .git file; only linked worktrees live under /worktrees/.
            let is_worktree = gitdir.parent().and_then(folder_name).as_deref() == Some("worktrees");
            return Some((dir.to_path_buf(), if is_worktree { Git::Worktree(gitdir) } else { Git::Dir(gitdir) }));
        }
    }
    None
}

fn read_branch(gitdir: &Path) -> Option<String> {
    let head = std::fs::read_to_string(gitdir.join("HEAD")).ok()?;
    head.trim().strip_prefix("ref: refs/heads/").map(str::to_string)
}
