use hearagent_core::rules::{any_matches, glob, matches, suggest, AllowRule};

fn rule(tool: &str, pattern: &str) -> AllowRule {
    AllowRule { tool: tool.into(), pattern: pattern.into() }
}

#[test]
fn commands_match_exactly_or_by_prefix() {
    assert!(matches(&rule("Bash", "pnpm test"), "Bash", "pnpm test", "/w"));
    assert!(!matches(&rule("Bash", "pnpm test"), "Bash", "pnpm test --watch", "/w"));
    assert!(matches(&rule("Bash", "git *"), "Bash", "git status", "/w"));
    assert!(!matches(&rule("Bash", "git *"), "Bash", "rm -rf /", "/w"));
    assert!(!matches(&rule("Bash", "pnpm test"), "Edit", "pnpm test", "/w"));
}

#[test]
fn paths_match_relative_to_the_session_folder() {
    assert!(matches(&rule("Edit", "src/**"), "Edit", "/w/app/src/ui/button.tsx", "/w/app"));
    assert!(!matches(&rule("Edit", "src/**"), "Edit", "/w/app/package.json", "/w/app"));
    assert!(matches(&rule("Write", "*.md"), "Write", "/w/app/README.md", "/w/app"));
    assert!(!matches(&rule("Write", "*.md"), "Write", "/w/app/docs/a.md", "/w/app"));
}

#[test]
fn empty_pattern_allows_the_whole_tool() {
    assert!(any_matches(&[rule("WebFetch", "")], "WebFetch", "https://example.com", "/w"));
}

#[test]
fn globs() {
    assert!(glob("**/*.ts", "a/b/c.ts"));
    assert!(glob("**/*.ts", "c.ts"));
    assert!(!glob("src/*", "src/a/b"));
}

#[test]
fn suggestions() {
    assert_eq!(suggest("Bash", "pnpm lint --fix", "/w"), rule("Bash", "pnpm lint --fix"));
    assert_eq!(suggest("Edit", "/w/app/src/ui/button.tsx", "/w/app"), rule("Edit", "src/ui/**"));
    assert_eq!(suggest("Write", "/w/app/README.md", "/w/app"), rule("Write", "README.md"));
    assert_eq!(suggest("WebFetch", "https://x.dev", "/w"), rule("WebFetch", ""));
}
