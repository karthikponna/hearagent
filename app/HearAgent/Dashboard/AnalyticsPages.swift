import Charts
import SwiftUI

struct UsagePage: View {
    @Bindable var model: AppModel

    var body: some View {
        let report = model.usage.report
        let days = report?.days ?? []
        let months = Self.months(days)
        let total = days.reduce(0) { $0 + $1.costUsd }
        let peak = days.max { $0.costUsd < $1.costUsd }
        let tokens = days.reduce(UInt64(0)) { $0 + $1.claudeTokens + $1.codexTokens }

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                sparkCard(title: "Total spend", value: Format.usd(total), note: "Last 6 months", values: days.suffix(60).map(\.costUsd), color: Theme.claude)
                sparkCard(title: "Peak day", value: Format.usd(peak?.costUsd ?? 0), note: peak.map { "on \(Self.dayLabel($0.day))" } ?? "—", values: days.suffix(60).map(\.costUsd), color: Theme.success)
                sparkCard(title: "Cache hit rate", value: Format.percent((report?.month.cacheHitRate ?? 0) * 100), note: "This month", values: days.suffix(60).map { Double($0.claudeTokens) }, color: Theme.warning)
                sparkCard(title: "Tokens", value: Format.tokens(tokens), note: "Last 6 months", values: days.suffix(60).map { Double($0.claudeTokens + $0.codexTokens) }, color: Theme.danger)
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Spend by month").font(.cardTitle)
                        Spacer()
                        Text("Estimated API cost").font(.label).foregroundStyle(Theme.faint)
                    }
                    Text(Format.usd(months.last?.cost ?? 0)).font(.bigNumber)
                    Chart(months, id: \.label) { m in
                        BarMark(x: .value("Month", m.label), y: .value("Spend", m.cost))
                            .foregroundStyle(m.isCurrent ? Theme.claude : Color(red: 0.93, green: 0.9, blue: 0.85))
                            .cornerRadius(5)
                            .annotation(position: .top) {
                                if m.isCurrent { Text(Format.usd(m.cost)).font(.system(size: 10, weight: .bold)) }
                            }
                    }
                    .chartYAxis { AxisMarks(position: .leading) { AxisGridLine().foregroundStyle(Theme.line); AxisValueLabel() } }
                    .frame(height: 220)
                }
                .card()
                .frame(maxWidth: .infinity)

                LimitsCard(report: report, warning: model.preferences.limitWarningPercent)
                    .frame(width: 330)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Daily tokens").font(.cardTitle)
                    Spacer()
                    legend("Claude", Theme.claude)
                    legend("Codex", Theme.codex)
                }
                Chart {
                    ForEach(days.suffix(30), id: \.day) { d in
                        let date = DateFormatter.yearMonthDay.date(from: d.day) ?? Date()
                        BarMark(x: .value("Day", date, unit: .day), y: .value("Tokens", Double(d.claudeTokens)))
                            .foregroundStyle(Theme.claude)
                        BarMark(x: .value("Day", date, unit: .day), y: .value("Tokens", Double(d.codexTokens)))
                            .foregroundStyle(Theme.codex)
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 5)) { AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .chartYAxis { AxisMarks(position: .leading) { v in AxisGridLine().foregroundStyle(Theme.line); AxisValueLabel { if let n = v.as(Double.self) { Text(Format.tokens(UInt64(n))) } } } }
                .frame(height: 180)
            }
            .card()
        }
    }

    private func sparkCard(title: String, value: String, note: String, values: [Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.cardTitle)
            HStack(alignment: .bottom) {
                Text(value).font(.bigNumber)
                Spacer()
                Chart(Array(values.enumerated()), id: \.offset) { item in
                    LineMark(x: .value("i", item.offset), y: .value("v", item.element)).foregroundStyle(color).interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(width: 80, height: 30)
            }
            Text(note).font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .card()
    }

    private func legend(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name).font(.label).foregroundStyle(Theme.muted)
        }
    }

    struct MonthSpend { let label: String; let cost: Double; let isCurrent: Bool }

    static func months(_ days: [HearDayUsage]) -> [MonthSpend] {
        var order: [String] = []
        var sums: [String: Double] = [:]
        for d in days {
            let key = String(d.day.prefix(7))
            if sums[key] == nil { order.append(key) }
            sums[key, default: 0] += d.costUsd
        }
        let recent = order.suffix(6)
        return recent.map { key in
            let date = DateFormatter.yearMonth.date(from: key) ?? Date()
            return MonthSpend(label: date.formatted(.dateTime.month(.abbreviated)), cost: sums[key] ?? 0, isCurrent: key == recent.last)
        }
    }

    static func dayLabel(_ day: String) -> String {
        guard let date = DateFormatter.yearMonthDay.date(from: day) else { return day }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct LimitsCard: View {
    let report: HearUsageReport?
    let warning: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Limits").font(.cardTitle)
                Spacer()
                Text("warning at \(Int(warning))%").font(.label).foregroundStyle(Theme.faint)
            }
            agentBlock(.claudeCode, five: report?.claudeFiveHour, week: report?.claudeWeekly, note: "Estimated from your transcripts")
            Divider()
            if let codex = report?.codex {
                agentBlock(.codex, five: codex.fiveHour, week: codex.weekly, note: "From Codex\(codex.plan.map { " · \($0) plan" } ?? "")")
            } else {
                HStack(spacing: 8) {
                    AgentBadge(agent: .codex)
                    Text("Codex limits appear after your next Codex session.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
        }
        .card()
    }

    private func agentBlock(_ agent: AgentKind, five: HearLimitWindow?, week: HearLimitWindow?, note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AgentBadge(agent: agent)
                Text(agent.shortName).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(note).font(.system(size: 10)).foregroundStyle(Theme.faint)
            }
            limitRow("5H", five)
            limitRow("7D", week)
        }
    }

    private func limitRow(_ label: String, _ w: HearLimitWindow?) -> some View {
        let used = w?.usedPercent ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(label)  \(Format.percent(100 - used)) remaining")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                Spacer()
                Text(w?.resetsAtMs.map { "resets \(Format.time($0))" } ?? "").font(.system(size: 10)).foregroundStyle(Theme.faint)
            }
            LimitBar(fraction: used / 100)
        }
    }
}

extension DateFormatter {
    static let yearMonth: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM"; return f }()
    static let yearMonthDay: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()
}

struct SessionsPage: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var agentFilter: AgentKind?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !model.needsAttention.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Needs you")
                    ForEach(model.needsAttention, id: \.key) { s in
                        HStack(spacing: 10) {
                            Image(systemName: s.status == .failed ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(s.status == .failed ? Theme.danger : Theme.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(s.name) · \(s.agent)").font(.system(size: 12, weight: .semibold))
                                Text(s.lastUpdate).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Button("Open Terminal") { TerminalLauncher.focus(cwd: s.cwd) }.buttonStyle(PrimaryButtonStyle())
                        }
                        .padding(12)
                        .background(Theme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.warning.opacity(0.3)))
                    }
                }
            }

            VStack(spacing: 0) {
                HStack {
                    Text("All sessions").font(.cardTitle)
                    Spacer()
                    Picker("Agent", selection: $agentFilter) {
                        Text("All agents").tag(AgentKind?.none)
                        Text("Claude").tag(AgentKind?.some(.claudeCode))
                        Text("Codex").tag(AgentKind?.some(.codex))
                    }
                    .labelsHidden().fixedSize()
                    TextField("Search sessions, projects…", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 230)
                }
                .padding(.bottom, 12)

                tableHeader
                let rows = filtered
                if rows.isEmpty {
                    Text(model.usage.report == nil ? "Reading your sessions…" : "No sessions found.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(30)
                }
                ForEach(rows.prefix(150), id: \.id) { s in
                    SessionRow(model: model, session: s)
                    Divider().overlay(Theme.line)
                }
            }
            .card()
        }
    }

    private var filtered: [HearSessionUsage] {
        model.usage.sessions.filter { s in
            (agentFilter == nil || s.agent == agentFilter)
                && (search.isEmpty || s.title.localizedCaseInsensitiveContains(search) || s.project.localizedCaseInsensitiveContains(search))
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text("Date").frame(width: 120, alignment: .leading)
            Text("Session").frame(maxWidth: .infinity, alignment: .leading)
            Text("Model").frame(width: 120, alignment: .leading)
            Text("Tokens").frame(width: 70, alignment: .trailing)
            Text("Spend").frame(width: 70, alignment: .trailing)
            Text("Status").frame(width: 92, alignment: .leading)
            Text("").frame(width: 30)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Theme.faint)
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SessionRow: View {
    @Bindable var model: AppModel
    let session: HearSessionUsage

    var body: some View {
        let live = model.liveSession(for: session)
        HStack(spacing: 12) {
            Text(Format.dateTime(session.lastMs)).font(.system(size: 11)).foregroundStyle(Theme.muted).frame(width: 120, alignment: .leading)
            HStack(spacing: 8) {
                AgentBadge(agent: session.agent, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text("\(session.project)\(session.branch.map { " · \($0)" } ?? "") · \(session.agent.shortName)")
                        .font(.system(size: 10)).foregroundStyle(Theme.faint).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Format.shortModel(session.model)).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1).frame(width: 120, alignment: .leading)
            Text(Format.tokens(session.tokens.total)).font(.system(size: 11).monospacedDigit()).frame(width: 70, alignment: .trailing)
            Text(Format.usd(session.costUsd)).font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(live?.status == .needsYou ? Theme.danger : Theme.ink)
                .frame(width: 70, alignment: .trailing)
            StatusPill(status: live?.status).frame(width: 92, alignment: .leading)
            Menu {
                Button("Open folder") { NSWorkspace.shared.open(URL(fileURLWithPath: session.cwd)) }
                Button("Resume in Terminal") { TerminalLauncher.resume(session) }
                Button("Copy session ID") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.id, forType: .string)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 30)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 8)
    }
}

struct BoardPage: View {
    @Bindable var model: AppModel

    var body: some View {
        let recent = model.usage.sessions.filter { Double($0.lastMs) / 1000 > Date().timeIntervalSince1970 - 86_400 }
        let liveKeys = Set(model.sessions.map(\.key))
        let doneHistory = recent.filter { u in !liveKeys.contains((u.agent == .claudeCode ? "claude-code:" : "codex:") + u.id) }
        HStack(alignment: .top, spacing: 14) {
            column("Working", color: Theme.success, items: model.sessions.filter { $0.status == .working }.map { .live($0) })
            column("Needs you", color: Theme.warning, items: model.needsAttention.map { .live($0) })
            column("Done", color: Theme.codex, items: model.sessions.filter { $0.status == .done }.map { .live($0) } + doneHistory.map { .history($0) })
        }
    }

    enum Item: Identifiable {
        case live(HearSession)
        case history(HearSessionUsage)
        var id: String {
            switch self {
            case .live(let s): s.key
            case .history(let u): u.id
            }
        }
    }

    private func column(_ title: String, color: Color, items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title.uppercased()).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                Spacer()
                Text("\(items.count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            if items.isEmpty {
                Text("Nothing here").font(.system(size: 12)).foregroundStyle(Theme.faint).frame(maxWidth: .infinity, minHeight: 80)
            }
            ForEach(items.prefix(20)) { item in
                BoardCard(model: model, item: item)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

private struct BoardCard: View {
    @Bindable var model: AppModel
    let item: BoardPage.Item

    var body: some View {
        let (agent, title, line, usage): (AgentKind, String, String, HearSessionUsage?) = {
            switch item {
            case .live(let s):
                let u = model.usage(for: s)
                return (AgentKind(agentName: s.agent) ?? .claudeCode, u?.title ?? s.name, s.lastUpdate, u)
            case .history(let u):
                return (u.agent, u.title, "Session complete", u)
            }
        }()
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                AgentBadge(agent: agent, size: 16)
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer()
                if case .live(let s) = item { Text(Format.relative(Int64(s.lastEventMs))).font(.system(size: 10)).foregroundStyle(Theme.faint) }
            }
            Text(line).font(.system(size: 11)).foregroundStyle(lineColor).lineLimit(2)
            if let usage {
                HStack(spacing: 10) {
                    Label(Format.shortModel(usage.model), systemImage: "cpu").lineLimit(1)
                    if let branch = usage.branch { Label(branch, systemImage: "arrow.triangle.branch").lineLimit(1) }
                }
                .font(.system(size: 10)).foregroundStyle(Theme.muted)
                HStack {
                    Text(Format.tokens(usage.tokens.total)).font(.system(size: 10).monospacedDigit()).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(Format.usd(usage.costUsd)).font(.system(size: 11, weight: .semibold).monospacedDigit())
                }
            }
        }
        .card(padding: 10)
    }

    private var lineColor: Color {
        if case .live(let s) = item {
            switch s.status {
            case .needsYou: return Theme.warning
            case .failed: return Theme.danger
            case .working: return Theme.success
            case .done: return Theme.muted
            }
        }
        return Theme.success
    }
}

/// Brings the user to their terminal. Sessions can't be addressed directly, so this
/// focuses the running terminal app, or opens Terminal in the session's folder.
@MainActor
enum TerminalLauncher {
    static let terminals = ["com.mitchellh.ghostty", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.apple.Terminal"]

    static func focus(cwd: String) {
        if let running = terminals.lazy.compactMap({ NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }).first {
            running.activate()
        } else if !cwd.isEmpty {
            NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration())
        }
    }

    static func resume(_ session: HearSessionUsage) {
        let command = session.agent == .claudeCode ? "claude --resume \(session.id)" : "codex resume \(session.id)"
        let action = SavedAction(name: "Resume", command: command, directory: session.cwd)
        let source = "tell application \"Terminal\"\nactivate\ndo script \"cd \(ActionStore.shellQuote(action.directory).replacingOccurrences(of: "\"", with: "\\\"")) && \(command)\"\nend tell"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}
