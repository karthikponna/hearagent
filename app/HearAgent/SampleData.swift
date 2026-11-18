#if DEBUG
import Foundation

/// Realistic sample data for snapshots and previews.
enum SampleData {
    static let now = Int64(Date().timeIntervalSince1970 * 1000)

    static func usage() -> HearUsageReport {
        var days: [HearDayUsage] = []
        let calendar = Calendar.current
        for offset in (0..<180).reversed() {
            let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
            let weekday = calendar.component(.weekday, from: date)
            let weekend = weekday == 1 || weekday == 7
            let wave = 0.6 + 0.4 * sin(Double(offset) / 9)
            let claude = UInt64((weekend ? 0.9 : 4.2) * wave * 1_000_000) + UInt64(offset % 7) * 180_000
            let codex = UInt64((weekend ? 0.2 : 1.1) * wave * 1_000_000)
            days.append(HearDayUsage(day: DateFormatter.yearMonthDay.string(from: date), claudeTokens: claude, codexTokens: codex,
                                     costUsd: Double(claude) / 1_000_000 * 1.05 + Double(codex) / 1_000_000 * 0.9, sessions: weekend ? 1 : 3))
        }
        var heat = [UInt32](repeating: 0, count: 168)
        for d in 0..<7 {
            for h in 0..<24 where (9...23).contains(h) && (d < 5 || h > 13) {
                heat[d * 24 + h] = UInt32(((h * 7 + d * 3) % 11) + (d < 5 ? 4 : 0))
            }
        }
        func s(_ id: String, _ agent: AgentKind, _ project: String, _ title: String, _ model: String, _ branch: String?, _ tokens: UInt64, _ cost: Double, _ minsAgo: Int64) -> HearSessionUsage {
            HearSessionUsage(id: id, agent: agent, project: project, cwd: "/Users/dev/code/\(project)", title: title, model: model, branch: branch,
                             tokens: HearTokens(input: tokens / 10, output: tokens / 20, cacheRead: tokens * 8 / 10, cacheWrite: tokens / 20, total: tokens),
                             costUsd: cost, messages: 42, startedMs: now - (minsAgo + 50) * 60_000, lastMs: now - minsAgo * 60_000)
        }
        let sessions = [
            s("s1", .claudeCode, "storefront", "Add passkey sign-in to checkout", "claude-opus-5-5", "feat/passkeys", 12_300_000, 8.42, 1),
            s("s2", .codex, "billing-api", "Migrate billing to usage-based plans", "gpt-5.5-codex", "usage-pricing", 6_200_000, 3.91, 2),
            s("s3", .claudeCode, "mobile-app", "Fix flaky upload tests", "claude-sonnet-5-5", "fix/upload-retry", 3_800_000, 1.86, 4),
            s("s4", .claudeCode, "tool-timeout-mcp", "Add a timeout to the MCP client", "claude-opus-5-5", "tool-timeout-mcp", 9_400_000, 6.12, 38),
            s("s5", .codex, "search-service", "Speed up product search", "gpt-5.5-codex", "main", 977_000, 2.37, 190),
            s("s6", .claudeCode, "admin-dashboard", "Add dark mode to dashboard", "claude-opus-5-5", "dark-mode", 14_500_000, 9.84, 420),
            s("s7", .claudeCode, "docs-site", "Write docs for the public API", "claude-sonnet-5-5", "docs", 481_000, 0.94, 600),
        ]
        let resetIn = { (mins: Int64) in Optional(now + mins * 60_000) }
        return HearUsageReport(
            sessions: sessions,
            days: days,
            heatmap: heat,
            claudeFiveHour: HearLimitWindow(usedTokens: 5_220_000, limitTokens: 9_000_000, usedPercent: 58, resetsAtMs: resetIn(134), estimated: true),
            claudeWeekly: HearLimitWindow(usedTokens: 12_700_000, limitTokens: 31_000_000, usedPercent: 41, resetsAtMs: resetIn(3 * 24 * 60), estimated: true),
            codex: HearCodexLimits(
                fiveHour: HearLimitWindow(usedTokens: 0, limitTokens: 0, usedPercent: 34, resetsAtMs: resetIn(210), estimated: false),
                weekly: HearLimitWindow(usedTokens: 0, limitTokens: 0, usedPercent: 41, resetsAtMs: resetIn(5 * 24 * 60), estimated: false),
                plan: "plus", observedMs: now
            ),
            month: HearMonthSummary(tokens: 127_100_000, costUsd: 130.78, forecastUsd: 301.80, sessions: 36, activeDays: 13, daysInMonth: 30, cacheHitRate: 0.78),
            generatedMs: now
        )
    }

    static func liveSessions() -> [HearSession] {
        [
            HearSession(key: "codex:s2", agent: "Codex", name: "billing-api · usage-pricing", cwd: "/Users/dev/code/billing-api", status: .needsYou,
                        lastUpdate: "Needs approval to run pnpm prisma migrate deploy", lastEventMs: UInt64(now - 20_000), pinned: false),
            HearSession(key: "claude-code:s1", agent: "Claude", name: "storefront · feat/passkeys", cwd: "/Users/dev/code/storefront", status: .working,
                        lastUpdate: "Working…", lastEventMs: UInt64(now - 60_000), pinned: false),
            HearSession(key: "claude-code:s3", agent: "Claude", name: "mobile-app · fix/upload-retry", cwd: "/Users/dev/code/mobile-app", status: .working,
                        lastUpdate: "Working…", lastEventMs: UInt64(now - 240_000), pinned: false),
            HearSession(key: "claude-code:s4", agent: "Claude", name: "tool-timeout-mcp", cwd: "/Users/dev/code/tool-timeout-mcp", status: .done,
                        lastUpdate: "Added a 30 second timeout to the MCP client.", lastEventMs: UInt64(now - 38 * 60_000), pinned: false),
        ]
    }

    static func history() -> [SpokenUpdate] {
        [
            SpokenUpdate(id: 3, kind: .approval, text: "billing api, usage pricing branch, needs approval to run pnpm prisma migrate deploy.", sessionKey: "codex:s2", at: Date().addingTimeInterval(-20), audio: Data()),
            SpokenUpdate(id: 2, kind: .summary, text: "Hey, tool timeout mcp just wrapped up: the MCP client now times out after 30 seconds, and all tests pass after one fix.", sessionKey: "claude-code:s4", at: Date().addingTimeInterval(-2280), audio: Data()),
            SpokenUpdate(id: 1, kind: .stopFailure, text: "Heads up, search service stopped: Codex hit a rate limit.", sessionKey: "codex:s5", at: Date().addingTimeInterval(-11_000), audio: Data()),
        ]
    }

    static func servers() -> [HearDevServer] {
        [
            HearDevServer(pid: 101, port: 3000, process: "node", framework: "Next.js", cwd: "/Users/dev/code/storefront", command: "next dev", uptimeSeconds: 8040),
            HearDevServer(pid: 102, port: 5173, process: "node", framework: "Vite", cwd: "/Users/dev/code/admin-dashboard", command: "vite", uptimeSeconds: 2880),
            HearDevServer(pid: 103, port: 8081, process: "node", framework: "Expo", cwd: "/Users/dev/code/mobile-app", command: "expo start", uptimeSeconds: 1320),
            HearDevServer(pid: 104, port: 8000, process: "Python", framework: "FastAPI", cwd: "/Users/dev/code/search-service", command: "uvicorn main:app", uptimeSeconds: 18_120),
        ]
    }

    static func actions() -> [SavedAction] {
        [
            SavedAction(name: "Start dev server", command: "pnpm dev", directory: "~/code/storefront"),
            SavedAction(name: "Run tests", command: "pnpm test", directory: ""),
            SavedAction(name: "Deploy preview", command: "vercel deploy --prebuilt", directory: ""),
            SavedAction(name: "Reset database", command: "pnpm db:reset && pnpm db:seed", directory: "~/code/billing-api"),
        ]
    }

    static let account = HearAccount(
        email: "karthik@hearagent.app", name: "Karthik",
        subscription: HearSubscription(status: "active", active: true, planName: "Pro", creditsTotal: 150_000, creditsUsed: 7_700,
                                       creditsRemaining: 142_300, periodEnd: ISO8601DateFormatter().string(from: Date().addingTimeInterval(29 * 86_400)), cancelAtPeriodEnd: false)
    )
}
#endif
