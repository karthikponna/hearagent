use hearagent_core::location::{speakable, Location};
use std::fs;
use std::path::Path;

fn repo(root: &Path, branch: &str) {
    fs::create_dir_all(root.join(".git")).unwrap();
    fs::write(root.join(".git/HEAD"), format!("ref: refs/heads/{branch}\n")).unwrap();
}

#[test]
fn plain_folder_uses_folder_name() {
    let dir = tempfile::tempdir().unwrap();
    let cwd = dir.path().join("scratch-pad");
    fs::create_dir_all(&cwd).unwrap();
    let loc = Location::detect(&cwd);
    assert_eq!(loc, Location { project: "scratch-pad".into(), worktree: None, branch: None });
    assert_eq!(loc.spoken_name(), "scratch pad");
}

#[test]
fn main_branch_is_not_spoken() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("auth-service");
    repo(&root, "main");
    let sub = root.join("src/handlers");
    fs::create_dir_all(&sub).unwrap();
    let loc = Location::detect(&sub);
    assert_eq!(loc.project, "auth-service", "subfolders resolve to the repo root");
    assert_eq!(loc.spoken_name(), "auth service");
    assert_eq!(loc.display_name(), "auth-service");
}

#[test]
fn feature_branch_is_spoken() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("auth-service");
    repo(&root, "feature/tool-timeout-mcp");
    let loc = Location::detect(&root);
    assert_eq!(loc.spoken_name(), "auth service, feature tool timeout mcp branch");
    assert_eq!(loc.display_name(), "auth-service · feature/tool-timeout-mcp");
}

#[test]
fn linked_worktree_uses_worktree_name() {
    let dir = tempfile::tempdir().unwrap();
    let main = dir.path().join("auth-service");
    repo(&main, "main");
    let gitdir = main.join(".git/worktrees/tool-timeout-mcp");
    fs::create_dir_all(&gitdir).unwrap();
    fs::write(gitdir.join("HEAD"), "ref: refs/heads/tool-timeout-mcp\n").unwrap();
    let wt = dir.path().join("tool-timeout-mcp");
    fs::create_dir_all(&wt).unwrap();
    fs::write(wt.join(".git"), format!("gitdir: {}\n", gitdir.display())).unwrap();

    let loc = Location::detect(&wt);
    assert_eq!(loc.project, "auth-service");
    assert_eq!(loc.worktree.as_deref(), Some("tool-timeout-mcp"));
    assert_eq!(loc.branch.as_deref(), Some("tool-timeout-mcp"));
    assert_eq!(loc.spoken_name(), "tool timeout mcp");
}

#[test]
fn speakable_names() {
    assert_eq!(speakable("feature/tool-timeout_mcp"), "feature tool timeout mcp");
}
