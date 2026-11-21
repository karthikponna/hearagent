import AppKit
import Foundation
import Observation
import SwiftUI

/// Usage from Claude Code and Codex files on this Mac, refreshed in the background.
@MainActor
@Observable
final class UsageStore {
    private(set) var report: HearUsageReport?
    private(set) var isLoading = false
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private var timer: Timer?

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        let offset = Int32(TimeZone.current.secondsFromGMT())
        let five = UInt64(max(preferences.claudeFiveHourLimit, 0))
        let week = UInt64(max(preferences.claudeWeeklyLimit, 0))
        Task.detached(priority: .utility) {
            let report = usageReport(utcOffsetSeconds: offset, claudeFiveHourLimit: five, claudeWeeklyLimit: week)
            await MainActor.run {
                self.report = report
                self.isLoading = false
            }
        }
    }

    var sessions: [HearSessionUsage] { report?.sessions ?? [] }

    func session(id: String) -> HearSessionUsage? {
        report?.sessions.first { $0.id == id }
    }

    #if DEBUG
    func setPreview(_ report: HearUsageReport) { self.report = report }
    #endif
}

/// Local dev servers, refreshed while a servers view is visible.
@MainActor
@Observable
final class ServerStore {
    private(set) var servers: [HearDevServer] = []
    private(set) var lastRefresh: Date?
    @ObservationIgnored private var refreshing = false

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task.detached(priority: .utility) {
            let found = devServers()
            await MainActor.run {
                self.servers = found
                self.lastRefresh = Date()
                self.refreshing = false
            }
        }
    }

    func open(_ server: HearDevServer) {
        if let url = URL(string: "http://localhost:\(server.port)") { NSWorkspace.shared.open(url) }
    }

    func reveal(_ server: HearDevServer) {
        guard !server.cwd.isEmpty else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: server.cwd)
    }

    func stop(_ server: HearDevServer) {
        let pid = server.pid
        servers.removeAll { $0.pid == pid }
        Task.detached {
            _ = stopDevServer(pid: pid)
            try? await Task.sleep(for: .milliseconds(600))
            await MainActor.run { self.refresh() }
        }
    }

    #if DEBUG
    func setPreview(_ servers: [HearDevServer]) { self.servers = servers }
    #endif
}

struct SavedAction: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var command: String
    var directory: String
}

/// Saved shell commands that open in Terminal with one click.
@MainActor
@Observable
final class ActionStore {
    private(set) var actions: [SavedAction]
    private(set) var lastError: String?
    @ObservationIgnored private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
        actions = preferences.load([SavedAction].self, key: "actions") ?? []
    }

    func add(name: String, command: String, directory: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? trimmed : name
        actions.append(SavedAction(name: title, command: trimmed, directory: directory.trimmingCharacters(in: .whitespaces)))
        persist()
    }

    func remove(_ action: SavedAction) {
        actions.removeAll { $0.id == action.id }
        persist()
    }

    /// Opens a new Terminal window running the command in its directory.
    func run(_ action: SavedAction) {
        var script = action.command
        if !action.directory.isEmpty {
            let dir = (action.directory as NSString).expandingTildeInPath
            script = "cd \(Self.shellQuote(dir)) && \(action.command)"
        }
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        lastError = error.map { "Couldn't open Terminal: \($0[NSAppleScript.errorMessage] ?? "permission needed")" }
    }

    nonisolated static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func persist() {
        preferences.save(actions, key: "actions")
    }

    #if DEBUG
    func setPreview(_ actions: [SavedAction]) { self.actions = actions }
    #endif
}

/// Where each agent keeps its skills, commands, plugins and config.
struct AgentRoutes: Identifiable {
    struct Route: Identifiable {
        let name: String
        let symbol: String
        let path: String
        var id: String { path }
        var exists: Bool { FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath) }
    }

    let brand: AgentBrand
    let routes: [Route]
    var name: String { brand.title }
    var id: String { name }

    static func all() -> [AgentRoutes] {
        [
            AgentRoutes(brand: .claude, routes: [
                Route(name: "Skills", symbol: "sparkles", path: "~/.claude/skills"),
                Route(name: "Agents", symbol: "person.2", path: "~/.claude/agents"),
                Route(name: "Commands", symbol: "command", path: "~/.claude/commands"),
                Route(name: "Rules", symbol: "doc.text", path: "~/.claude/CLAUDE.md"),
                Route(name: "Plugins", symbol: "puzzlepiece.extension", path: "~/.claude/plugins"),
                Route(name: "Config", symbol: "gearshape", path: "~/.claude/settings.json"),
            ]),
            AgentRoutes(brand: .codex, routes: [
                Route(name: "Skills", symbol: "sparkles", path: "~/.codex/skills"),
                Route(name: "Prompts", symbol: "text.bubble", path: "~/.codex/prompts"),
                Route(name: "Rules", symbol: "doc.text", path: "~/.codex/AGENTS.md"),
                Route(name: "Plugins", symbol: "puzzlepiece.extension", path: "~/.codex/plugins"),
                Route(name: "Sessions", symbol: "clock.arrow.circlepath", path: "~/.codex/sessions"),
                Route(name: "Config", symbol: "gearshape", path: "~/.codex/config.toml"),
            ]),
            AgentRoutes(brand: .gemini, routes: [
                Route(name: "Folder", symbol: "folder", path: "~/.gemini"),
                Route(name: "Rules", symbol: "doc.text", path: "~/.gemini/GEMINI.md"),
                Route(name: "Config", symbol: "gearshape", path: "~/.gemini/settings.json"),
            ]),
            AgentRoutes(brand: .cursor, routes: [
                Route(name: "Rules", symbol: "doc.text", path: "~/.cursor/rules"),
                Route(name: "Skills", symbol: "sparkles", path: "~/.cursor/skills"),
                Route(name: "MCP", symbol: "server.rack", path: "~/.cursor/mcp.json"),
            ]),
            AgentRoutes(brand: .opencode, routes: [
                Route(name: "Folder", symbol: "folder", path: "~/.config/opencode"),
                Route(name: "Agents", symbol: "person.2", path: "~/.config/opencode/agent"),
                Route(name: "Config", symbol: "gearshape", path: "~/.config/opencode/opencode.json"),
            ]),
        ]
    }

    func open(_ route: Route) {
        let path = (route.path as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return }
        if isDir.boolValue {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        }
    }
}

/// A line Hear Agent spoke during this run. Kept in memory only.
struct SpokenUpdate: Identifiable {
    let id: UInt64
    let kind: HearSpeechKind
    let text: String
    let sessionKey: String
    let at: Date
    let audio: Data
}
