#if DEBUG
import Foundation

/// Realistic sample data for snapshots and previews.
enum SampleData {
    static let now = Int64(Date().timeIntervalSince1970 * 1000)

    static func usage() -> HearUsageReport {
        var days: [HearDayUsage] = []
        let calendar = Calendar.current
        for offset in (0..<365).reversed() {
            let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
            let weekday = calendar.component(.weekday, from: date)
            let weekend = weekday == 1 || weekday == 7
            let wave = 0.6 + 0.4 * sin(Double(offset) / 9)
            let growth = 1.0 + Double(365 - offset) / 420
            let jitter = Double((offset * 37) % 11) / 10
            let claude = UInt64((weekend ? 0.9 : 4.2) * wave * growth * (0.7 + jitter * 0.5) * 1_000_000)
            let codex = UInt64((weekend ? 0.2 : 1.1) * wave * growth * 1_000_000)
            let prompt = (claude + codex) * 9 / 10
            let cacheShare = 0.74 + 0.05 * sin(Double(offset) / 4)
            days.append(HearDayUsage(day: DateFormatter.yearMonthDay.string(from: date), claudeTokens: claude, codexTokens: codex,
                                     costUsd: Double(claude) / 1_000_000 * 0.95 + Double(codex) / 1_000_000 * 0.8,
                                     sessions: weekend ? 1 : UInt32(2 + offset % 3),
                                     cacheReadTokens: UInt64(Double(prompt) * cacheShare), promptTokens: prompt))
        }
        var heat = [UInt32](repeating: 0, count: 168)
        for d in 0..<7 {
            for h in 0..<24 where (9...23).contains(h) && (d < 5 || h > 13) {
                heat[d * 24 + h] = UInt32(((h * 7 + d * 3) % 11) + (d < 5 ? 4 : 0))
            }
        }
        heat[1 * 24 + 0] = 9; heat[1 * 24 + 3] = 10; heat[3 * 24 + 0] = 2; heat[4 * 24 + 1] = 5
        func s(_ id: String, _ agent: AgentKind, _ project: String, _ title: String, _ model: String, _ branch: String?, _ tokens: UInt64, _ cost: Double, _ minsAgo: Int64) -> HearSessionUsage {
            HearSessionUsage(id: id, agent: agent, project: project, cwd: "/Users/dev/code/\(project)", title: title, model: model, branch: branch,
                             tokens: HearTokens(input: tokens / 10, output: tokens / 66, cacheRead: tokens * 8 / 10, cacheWrite: tokens / 20, total: tokens),
                             costUsd: cost, messages: 42, startedMs: now - (minsAgo + 50) * 60_000, lastMs: now - minsAgo * 60_000, transcriptPath: "")
        }
        let sessions = [
            s("s1a2f9", .claudeCode, "storefront", "Add passkey sign-in to checkout", "claude-opus-5-5", "feat/passkeys", 12_300_000, 8.42, 1),
            s("s2c7d1", .codex, "billing-api", "Migrate billing to usage-based plans", "gpt-5.5-codex", "usage-pricing", 6_200_000, 3.91, 2),
            s("s3e4b8", .claudeCode, "mobile-app", "Fix flaky upload tests", "claude-sonnet-5-5", "fix/upload-retry", 3_800_000, 1.86, 4),
            s("s4f0a3", .claudeCode, "tool-timeout-mcp", "Add a timeout to the MCP client", "claude-opus-5-5", "tool-timeout-mcp", 9_400_000, 6.12, 38),
            s("s5b6c2", .codex, "search-service", "Speed up product search", "gpt-5.5-codex", "main", 977_000, 2.37, 190),
            s("s6d9e7", .claudeCode, "admin-dashboard", "Add dark mode to dashboard", "claude-opus-5-5", "dark-mode", 14_500_000, 9.84, 420),
            s("s7a1f4", .claudeCode, "docs-site", "Write docs for the public API", "claude-sonnet-5-5", "docs", 481_000, 0.94, 600),
            s("s8c3d5", .codex, "admin-dashboard", "Upgrade to React 20", "gpt-5.5-codex", "react-20", 554_000, 0.71, 720),
        ]
        let resetIn = { (mins: Int64) in Optional(now + mins * 60_000) }
        return HearUsageReport(
            sessions: sessions,
            days: days,
            heatmap: heat,
            claudeFiveHour: HearLimitWindow(usedTokens: 5_220_000, limitTokens: 9_000_000, usedPercent: 58, resetsAtMs: resetIn(134), estimated: true),
            claudeWeekly: HearLimitWindow(usedTokens: 12_700_000, limitTokens: 31_000_000, usedPercent: 47, resetsAtMs: resetIn(3 * 24 * 60), estimated: true),
            codex: HearCodexLimits(
                fiveHour: HearLimitWindow(usedTokens: 0, limitTokens: 0, usedPercent: 34, resetsAtMs: resetIn(210), estimated: false),
                weekly: HearLimitWindow(usedTokens: 0, limitTokens: 0, usedPercent: 41, resetsAtMs: resetIn(5 * 24 * 60), estimated: false),
                plan: "plus", observedMs: now
            ),
            month: HearMonthSummary(tokens: 127_100_000, costUsd: 130.78, forecastUsd: 301.80, sessions: 9, activeDays: 13, daysInMonth: 30, cacheHitRate: 0.78),
            generatedMs: now
        )
    }

    static func liveSessions() -> [HearSession] {
        let todos = [
            HearTodo(id: "1", content: "Generate WebAuthn challenge on the server", status: .completed),
            HearTodo(id: "2", content: "Add PasskeyButton to checkout", status: .inProgress),
            HearTodo(id: "3", content: "Keep email magic-link fallback", status: .pending),
            HearTodo(id: "4", content: "Write Playwright tests", status: .pending),
        ]
        func live(_ key: String, _ agent: String, _ name: String, _ project: String, _ status: HearSessionStatus, _ update: String, _ secsAgo: Int64,
                  prompt: String = "", message: String = "", activity: HearActivity? = nil, todos: [HearTodo] = [], pending: HearPendingApproval? = nil) -> HearSession {
            HearSession(key: key, agent: agent, name: name, cwd: "/Users/dev/code/\(project)", status: status, lastUpdate: update,
                        lastEventMs: UInt64(now - secsAgo * 1000), pinned: false, sessionId: String(key.split(separator: ":").last ?? ""),
                        transcriptPath: "", lastPrompt: prompt, lastMessage: message, activity: activity, todos: todos, pending: pending)
        }
        return [
            live("codex:s2c7d1", "Codex", "billing-api · usage-pricing", "billing-api", .needsYou, "Needs approval to run pnpm prisma migrate deploy", 20,
                 prompt: "Move billing to usage-based plans", pending: HearPendingApproval(id: 7, tool: "Bash", subject: "pnpm prisma migrate deploy", action: "run pnpm prisma migrate deploy", atMs: UInt64(now - 20_000))),
            live("claude-code:s1a2f9", "Claude", "storefront · feat/passkeys", "storefront", .working, "Working…", 9,
                 prompt: "Add passkey sign-in to checkout and keep the email fallback",
                 message: "Wiring the WebAuthn challenge into the checkout form. Tests for the fallback are next.",
                 activity: HearActivity(tool: "Edit", line: "Edit app/checkout/PasskeyButton.tsx", atMs: UInt64(now - 9_000)), todos: todos),
            live("claude-code:s3e4b8", "Claude", "mobile-app · fix/upload-retry", "mobile-app", .working, "Working…", 15,
                 prompt: "The upload tests are flaky on CI, fix them",
                 activity: HearActivity(tool: "Bash", line: "Bash pnpm test upload", atMs: UInt64(now - 15_000))),
            live("claude-code:s4f0a3", "Claude", "tool-timeout-mcp", "tool-timeout-mcp", .done, "Added a 30 second timeout to the MCP client.", 38 * 60,
                 message: "Added a 30 second timeout to the MCP client. All tests pass."),
        ]
    }

    static func history() -> [SpokenUpdate] {
        [
            SpokenUpdate(id: 3, kind: .approval, text: "billing api, usage pricing branch, needs approval to run pnpm prisma migrate deploy.", sessionKey: "codex:s2c7d1", at: Date().addingTimeInterval(-20), audio: Data()),
            SpokenUpdate(id: 2, kind: .summary, text: "Hey, tool timeout mcp just wrapped up: the MCP client now times out after 30 seconds, and all tests pass after one fix.", sessionKey: "claude-code:s4f0a3", at: Date().addingTimeInterval(-2280), audio: Data()),
            SpokenUpdate(id: 1, kind: .stopFailure, text: "Heads up, search service stopped: Codex hit a rate limit.", sessionKey: "codex:s5b6c2", at: Date().addingTimeInterval(-11_000), audio: Data()),
        ]
    }

    static func servers() -> [HearDevServer] {
        [
            HearDevServer(pid: 101, port: 3000, process: "node", framework: "Next.js", cwd: "/Users/dev/code/storefront", command: "next dev", uptimeSeconds: 8040),
            HearDevServer(pid: 102, port: 5173, process: "node", framework: "Vite", cwd: "/Users/dev/code/admin-dashboard", command: "vite", uptimeSeconds: 2880),
            HearDevServer(pid: 103, port: 8081, process: "node", framework: "Expo", cwd: "/Users/dev/code/mobile-app", command: "expo start", uptimeSeconds: 1320),
            HearDevServer(pid: 104, port: 8000, process: "python", framework: "FastAPI", cwd: "/Users/dev/code/search-service", command: "uvicorn main:app", uptimeSeconds: 18_120),
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

    static let allowRules = [
        AllowRuleItem(tool: "Bash", pattern: "pnpm test"),
        AllowRuleItem(tool: "Bash", pattern: "git status"),
        AllowRuleItem(tool: "Bash", pattern: "pnpm lint --fix"),
        AllowRuleItem(tool: "Edit", pattern: "src/**"),
    ]

    static let account = HearAccount(
        email: "karthik@hearagent.app", name: "Karthik",
        subscription: HearSubscription(status: "active", active: true, planId: "yearly", planName: "Yearly", creditsTotal: 150_000, creditsUsed: 7_700,
                                       creditsRemaining: 142_300, periodEnd: ISO8601DateFormatter().string(from: Date().addingTimeInterval(29 * 86_400)),
                                       renewsAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(312 * 86_400)), cancelAtPeriodEnd: false)
    )
}
#endif
