import Charts
import SwiftUI

// MARK: Usage

struct UsagePage: View {
    @Bindable var model: AppModel

    var body: some View {
        let days = model.usage.report?.days ?? []
        let range = model.usageRange
        let custom = model.usageCustom
        let w = custom.map { Metrics.windows(days, in: $0) } ?? Metrics.windows(days, last: range.days)
        let window = Array(w.current)
        let now = PeriodStats(w.current)
        let before = PeriodStats(w.previous)
        let peak = window.max { $0.costUsd < $1.costUsd }
        let buckets = Self.buckets(window, target: 24)
        let comparison = custom == nil ? "Compared with the previous \(range.rawValue)" : "Compared with the period before"

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                let labels = buckets.map(Self.label)
                SparkCard(title: "Total spend", value: now.cost, format: { Format.usdWhole($0) },
                          points: buckets.map { .init(date: Self.date($0.first!.day), value: Self.sum($0) { $0.costUsd }) },
                          label: { labels[$0] }) {
                    Delta(value: Metrics.change(now.cost, before.cost), invert: true, decimals: 0).help(comparison)
                }
                let peaks = buckets.map { $0.max { $0.costUsd < $1.costUsd } }
                SparkCard(title: "Peak day", value: peak?.costUsd ?? 0, format: { Format.usd($0) },
                          points: zip(buckets, peaks).map { .init(date: Self.date($0.first!.day), value: $1?.costUsd ?? 0) },
                          label: { peaks[$0].map { Metrics.dayLabel($0.day) } ?? "" }) {
                    if let peak {
                        Text(Metrics.dayLabel(peak.day)).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                    }
                }
                let rate = cacheRate(window)
                let rates = buckets.map { cacheRate($0) }
                SparkCard(title: "Cache hit rate", value: rate * 100, format: { Format.percent($0, decimals: 1) },
                          points: zip(buckets, rates).map { .init(date: Self.date($0.first!.day), value: $1 * 100) },
                          floor: max(0, ((rates.min() ?? 0) * 100 - 4).rounded(.down)),
                          label: { labels[$0] }) {
                    Delta(value: (rate - cacheRate(Array(w.previous))) * 100, suffix: " pts").help(comparison)
                }
                SparkCard(title: "Tokens", value: Double(now.tokens), format: { Format.tokens(UInt64($0)) },
                          points: buckets.map { .init(date: Self.date($0.first!.day), value: Self.sum($0) { Double($0.claudeTokens + $0.codexTokens) }) },
                          label: { labels[$0] }) {
                    Delta(value: Metrics.change(Double(now.tokens), Double(before.tokens)), invert: true, decimals: 0).help(comparison)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 14) {
                SpendGrowthCard(days: window, total: now.cost, change: Metrics.change(now.cost, before.cost), comparison: comparison)
                DailyTokensCard(days: window)
            }
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                Text("Recent sessions").font(.system(size: 15, weight: .semibold))
                SessionsTable(model: model, rows: Array(model.usage.sessions.prefix(8)), selectable: false)
            }
            .card()
        }
    }

    private func cacheRate(_ days: [HearDayUsage]) -> Double {
        let read = days.reduce(UInt64(0)) { $0 + $1.cacheReadTokens }
        let prompt = days.reduce(UInt64(0)) { $0 + $1.promptTokens }
        return prompt == 0 ? (model.usage.report?.month.cacheHitRate ?? 0) : Double(read) / Double(prompt)
    }

    /// Equal runs of days counted back from today, so the newest point is never a stub.
    static func buckets(_ days: [HearDayUsage], target: Int) -> [[HearDayUsage]] {
        guard !days.isEmpty else { return [] }
        let size = max(1, Int((Double(days.count) / Double(target)).rounded(.up)))
        var out: [[HearDayUsage]] = []
        var end = days.count
        while end - size >= 0 || out.isEmpty {
            out.append(Array(days[max(0, end - size)..<end]))
            end -= size
        }
        return out.reversed()
    }

    static func date(_ day: String) -> Date { DateFormatter.yearMonthDay.date(from: day) ?? Date() }

    static func sum(_ days: [HearDayUsage], _ value: (HearDayUsage) -> Double) -> Double { days.reduce(0) { $0 + value($1) } }

    static func label(_ days: [HearDayUsage]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        if first.day == last.day { return date(first.day).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
        return DayRange(date(first.day), date(last.day)).label
    }

    static func dayTitle(_ day: String) -> String {
        date(day).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

/// A headline figure over a full-width trend line. Hovering the line turns the headline
/// into a readout of the point under the pointer.
struct SparkCard<Detail: View>: View {
    let title: String
    let value: Double
    let format: (Double) -> String
    let points: [TrendChart.Point]
    var floor: Double = 0
    let label: (Int) -> String
    @ViewBuilder var detail: () -> Detail
    @State private var hovered: Int?

    var body: some View {
        let reading = hovered.flatMap { points.indices.contains($0) ? $0 : nil }
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                let shown = reading.map { points[$0].value } ?? value
                ViewThatFits(in: .horizontal) {
                    RollingNumber(value: shown, format: format, size: 28)
                    RollingNumber(value: shown, format: format, size: 22)
                }
                .layoutPriority(1)
                ZStack(alignment: .leading) {
                    detail().opacity(reading == nil ? 1 : 0)
                    if let reading {
                        Text(label(reading)).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                            .lineLimit(1).fixedSize()
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: reading == nil)
                Spacer(minLength: 0)
            }
            .padding(.top, 10)
            TrendChart(points: points.count > 1 ? points : Self.flat, axes: false, floor: floor, onHover: { i in withAnimation(.snappy(duration: 0.25)) { hovered = i } })
                .frame(height: 58)
                .padding(.top, 14)
        }
        .card()
    }

    private static var flat: [TrendChart.Point] {
        let now = Date()
        return [.init(date: now.addingTimeInterval(-86_400), value: 0), .init(date: now, value: 0)]
    }
}

/// Spend adding up day by day across the range, ending at the range's total.
struct SpendGrowthCard: View {
    let days: [HearDayUsage]
    let total: Double
    let change: Double
    let comparison: String

    var body: some View {
        var running = 0.0
        let points: [TrendChart.Point] = days.map { d in
            running += d.costUsd
            return .init(date: UsagePage.date(d.day), value: running)
        }
        return ChartCard(title: "Spend growth", badge: UsagePage.label(days)) {
            RollingNumber(value: total, format: { Format.usdWhole($0) }, size: 24)
            ChangeChip(value: change).help(comparison)
        } chart: {
            TrendChart(points: points, tip: { i in
                ChartTip(title: UsagePage.dayTitle(days[i].day), rows: [
                    .init(label: "Spent so far", value: Format.usd(points[i].value)),
                    .init(label: "That day", value: Format.usd(days[i].costUsd)),
                ])
            })
        }
    }
}

/// Tokens per day across the range, every day hoverable.
struct DailyTokensCard: View {
    let days: [HearDayUsage]

    var body: some View {
        let points: [TrendChart.Point] = days.map { .init(date: UsagePage.date($0.day), value: Double($0.claudeTokens + $0.codexTokens)) }
        let average = days.isEmpty ? 0 : points.reduce(0) { $0 + $1.value } / Double(days.count)
        return ChartCard(title: "Daily tokens", badge: nil) {
            RollingNumber(value: average, format: { Format.tokens(UInt64($0)) }, size: 24)
            Text("a day on average").font(.system(size: 13)).foregroundStyle(Theme.muted)
        } chart: {
            TrendChart(points: points, yLabel: { Format.tokens(UInt64($0)) }, tip: { i in
                ChartTip(title: UsagePage.dayTitle(days[i].day), rows: [
                    .init(label: "Tokens", value: Format.tokens(UInt64(points[i].value))),
                    .init(label: "Claude Code", value: Format.tokens(days[i].claudeTokens)),
                    .init(label: "Codex", value: Format.tokens(days[i].codexTokens)),
                ])
            })
        }
    }
}

/// A chart card: title and optional range badge, a headline row, then the chart.
private struct ChartCard<Headline: View, Plot: View>: View {
    let title: String
    let badge: String?
    @ViewBuilder var headline: () -> Headline
    @ViewBuilder var chart: () -> Plot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink2)
                        .contentTransition(.numericText())
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(Theme.well, in: Capsule())
                }
            }
            .frame(height: 24)
            HStack(alignment: .firstTextBaseline, spacing: 10) { headline() }
            chart().frame(height: 220).padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// "↑ 33%" in a soft capsule; spend going up reads red, like the Total spend card.
private struct ChangeChip: View {
    let value: Double

    var body: some View {
        let up = value >= 0
        let good = !up || abs(value) < 0.05
        HStack(spacing: 3) {
            Image(systemName: up ? "arrow.up" : "arrow.down").font(.system(size: 10, weight: .bold))
            Text(Format.percent(abs(value))).contentTransition(.numericText(value: value))
        }
        .font(.system(size: 12, weight: .bold).monospacedDigit())
        .foregroundStyle(good ? Theme.green : Theme.red)
        .padding(.horizontal, 8).frame(height: 22)
        .background(good ? Theme.greenSoft : Theme.redSoft, in: Capsule())
    }
}

/// The sessions table: date, session, id, model, tokens, spend, status and actions.
struct SessionsTable: View {
    @Bindable var model: AppModel
    let rows: [HearSessionUsage]
    var selectable = true
    @State private var sort: Sort = .date
    @State private var ascending = false
    @State private var selected: Set<String> = []
    @State private var compact = false

    enum Sort { case date, spend, tokens }

    var body: some View {
        VStack(spacing: 0) {
            header
            if rows.isEmpty {
                Text(model.usage.report == nil ? "Reading your sessions…" : "No sessions yet.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).padding(40)
            }
            ForEach(Array(sorted.prefix(200).enumerated()), id: \.element.id) { i, s in
                if i > 0 { Divider().overlay(Theme.line) }
                SessionRow(model: model, session: s, selectable: selectable, compact: compact, selected: Binding(
                    get: { selected.contains(s.id) },
                    set: { if $0 { selected.insert(s.id) } else { selected.remove(s.id) } }
                ))
            }
            if selectable && !selected.isEmpty {
                HStack {
                    Text("\(selected.count) selected").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Button("Clear") { selected.removeAll() }.buttonStyle(SoftButtonStyle(height: 28))
                }
                .padding(.top, 12)
            }
        }
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { compact = g.size.width < 900 }
                    .onChange(of: g.size.width) { _, w in compact = w < 900 }
            }
        }
    }

    private var sorted: [HearSessionUsage] {
        let list: [HearSessionUsage]
        switch sort {
        case .date: list = rows.sorted { $0.lastMs > $1.lastMs }
        case .spend: list = rows.sorted { $0.costUsd > $1.costUsd }
        case .tokens: list = rows.sorted { $0.tokens.total > $1.tokens.total }
        }
        return ascending ? list.reversed() : list
    }

    private var header: some View {
        HStack(spacing: 14) {
            if selectable {
                Checkbox(isOn: Binding(get: { !rows.isEmpty && selected.count == rows.count }, set: { selected = $0 ? Set(rows.map(\.id)) : [] }))
            }
            sortButton("Date", .date).frame(width: compact ? 92 : 110, alignment: .leading)
            Text("Session").frame(maxWidth: .infinity, alignment: .leading)
            if !compact { Text("ID").frame(width: 56, alignment: .leading) }
            Text("Model").frame(width: compact ? 104 : 120, alignment: .leading)
            sortButton("Tokens", .tokens).frame(width: 70, alignment: .trailing)
            sortButton("Spend", .spend).frame(width: 74, alignment: .trailing)
            Text("Status").frame(width: 90, alignment: .center)
            Text("Action").frame(width: 50, alignment: .center)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func sortButton(_ title: String, _ key: Sort) -> some View {
        Button {
            if sort == key { ascending.toggle() } else { sort = key; ascending = false }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: sort == key ? (ascending ? "chevron.up" : "chevron.down") : "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(sort == key ? Theme.ink2 : Theme.faint)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SessionRow: View {
    @Bindable var model: AppModel
    let session: HearSessionUsage
    let selectable: Bool
    var compact = false
    @Binding var selected: Bool

    var body: some View {
        let live = model.liveSession(for: session)
        HStack(spacing: 14) {
            if selectable { Checkbox(isOn: $selected) }
            VStack(alignment: .leading, spacing: 1) {
                Text(Format.date(session.lastMs)).font(.system(size: 13.5)).foregroundStyle(Theme.ink)
                Text(Format.clock(session.lastMs)).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            .frame(width: compact ? 92 : 110, alignment: .leading)
            HStack(spacing: 11) {
                InitialsAvatar(text: session.project, tint: session.agent.color, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text("\(session.project) · \(session.agent.shortName)").font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !compact {
                Text(String(session.id.prefix(6))).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Theme.faint)
                    .frame(width: 56, alignment: .leading).help(session.id)
            }
            Text(Format.shortModel(session.model)).font(.system(size: 13.5)).foregroundStyle(Theme.ink).lineLimit(1)
                .frame(width: compact ? 104 : 120, alignment: .leading)
            Text(Format.tokens(session.tokens.total)).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(Theme.ink)
                .frame(width: 70, alignment: .trailing)
            Text(Format.usd(session.costUsd)).font(.system(size: 13.5, weight: .bold).monospacedDigit())
                .foregroundStyle(live?.status == .needsYou ? Theme.red : Theme.ink)
                .frame(width: 74, alignment: .trailing)
            statusPill(live).frame(width: 90, alignment: .center)
            Menu {
                Button("Resume in Terminal") { TerminalLauncher.resume(session) }
                Button("Open folder") { NSWorkspace.shared.open(URL(fileURLWithPath: session.cwd)) }
                Divider()
                Button("Copy session ID") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.id, forType: .string)
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink2).frame(width: 30, height: 26)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 50)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .hoverRow()
    }

    @ViewBuilder
    private func statusPill(_ live: HearSession?) -> some View {
        if let live, live.status == .needsYou, live.pending == nil {
            Text("Waiting").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.blue)
                .padding(.horizontal, 10).frame(height: 22).background(Theme.blueSoft, in: Capsule())
        } else {
            StatusPill(status: live?.status)
        }
    }
}

struct Checkbox: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isOn ? Theme.ink : Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(isOn ? Theme.ink : Color.black.opacity(0.15)))
                .overlay { if isOn { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white) } }
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
    }
}

// MARK: Board

struct BoardPage: View {
    @Bindable var model: AppModel

    var body: some View {
        let recent = model.usage.sessions.filter { Double($0.lastMs) / 1000 > Date().timeIntervalSince1970 - 86_400 }
        let liveKeys = Set(model.sessions.map(\.key))
        let history = recent.filter { !liveKeys.contains(AppModel.key(for: $0)) }
        HStack(alignment: .top, spacing: 14) {
            column("Working", color: Theme.green, items: model.sessions.filter { $0.status == .working }.map { item(live: $0) })
            column("Needs you", color: Theme.orange, items: model.needsAttention.map { item(live: $0) })
            column("Done", color: Theme.blue, items: model.sessions.filter { $0.status == .done }.map { item(live: $0) } + history.map { item(history: $0) })
        }
    }

    private func item(live s: HearSession) -> BoardItem {
        let u = model.usage(for: s)
        let line: BoardItem.Line
        switch s.status {
        case .working:
            line = s.activity.map { BoardItem.Line(icon: Self.toolIcon($0.tool), text: $0.line, color: Theme.green) }
                ?? BoardItem.Line(icon: "ellipsis", text: "Working…", color: Theme.green)
        case .needsYou:
            line = s.pending != nil
                ? BoardItem.Line(icon: "exclamationmark.circle", text: "Permission pending", color: Theme.orange)
                : BoardItem.Line(icon: "hourglass", text: "Waiting for you", color: Theme.blue)
        case .failed:
            line = BoardItem.Line(icon: "exclamationmark.octagon", text: s.lastUpdate, color: Theme.red)
        case .done:
            line = BoardItem.Line(icon: "checkmark", text: "Session complete", color: Theme.green)
        }
        return BoardItem(id: s.key, agent: s.agent, title: u?.title ?? s.name, line: line, model: u?.model, branch: u?.branch ?? s.name.components(separatedBy: " · ").dropFirst().first,
                         tokens: u?.tokens, cost: u?.costUsd, time: Int64(s.lastEventMs), cwd: s.cwd, usage: u)
    }

    private func item(history u: HearSessionUsage) -> BoardItem {
        BoardItem(id: AppModel.key(for: u), agent: u.agent.shortName, title: u.title, line: .init(icon: "checkmark", text: "Session complete", color: Theme.green),
                  model: u.model, branch: u.branch, tokens: u.tokens, cost: u.costUsd, time: u.lastMs, cwd: u.cwd, usage: u)
    }

    static func toolIcon(_ tool: String) -> String {
        switch tool {
        case "Edit", "MultiEdit", "Write", "NotebookEdit", "apply_patch": "pencil.line"
        case "Read", "Grep", "Glob": "doc.text.magnifyingglass"
        case "WebFetch", "WebSearch": "globe"
        case "Task", "Agent": "person.2"
        default: "terminal"
        }
    }

    private func column(_ title: String, color: Color, items: [BoardItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title.uppercased()).font(.system(size: 12.5, weight: .semibold, design: .monospaced)).foregroundStyle(color)
                Spacer()
                Text("\(items.count)").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            if items.isEmpty {
                Text("Nothing here").font(.system(size: 13)).foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity, minHeight: 90)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            ForEach(items.prefix(30)) { item in
                BoardCard(model: model, item: item)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.palette.column, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline))
    }
}

struct BoardItem: Identifiable {
    struct Line { let icon: String; let text: String; let color: Color }
    let id: String
    let agent: String
    let title: String
    let line: Line
    let model: String?
    let branch: String?
    let tokens: HearTokens?
    let cost: Double?
    let time: Int64
    let cwd: String
    let usage: HearSessionUsage?
}

private struct BoardCard: View {
    @Bindable var model: AppModel
    let item: BoardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                AgentMark(name: item.agent, size: 20)
                Text(item.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    if let u = item.usage { TerminalLauncher.resume(u) } else { TerminalLauncher.focus(cwd: item.cwd) }
                } label: { Image(systemName: "apple.terminal").font(.system(size: 12)) }
                    .buttonStyle(IconButtonStyle(size: 24))
                    .help("Open in Terminal")
            }
            HStack(spacing: 6) {
                Image(systemName: item.line.icon).font(.system(size: 11, weight: .semibold))
                Text(item.line.text).lineLimit(1)
                Spacer(minLength: 4)
                Text(Format.ago(item.time)).foregroundStyle(Theme.faint)
            }
            .font(.system(size: 13))
            .foregroundStyle(item.line.color)
            if let m = item.model, !m.isEmpty {
                meta("cpu", Format.shortModel(m))
            }
            if let b = item.branch, !b.isEmpty {
                meta("arrow.triangle.branch", b)
            }
            HStack {
                if let t = item.tokens {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up").font(.system(size: 10, weight: .semibold))
                        Text("\(Format.tokens(t.total)) / \(Format.tokens(t.output))")
                    }
                }
                Spacer()
                if let c = item.cost { Text(Format.usd(c)) }
            }
            .font(.system(size: 12.5, design: .monospaced))
            .foregroundStyle(Theme.ink2)
        }
        .padding(13)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
        .contentShape(Rectangle())
        .onTapGesture {
            if let u = item.usage { model.openSession(u) } else { TerminalLauncher.focus(cwd: item.cwd) }
        }
    }

    private func meta(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Theme.muted).frame(width: 14)
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.ink2).lineLimit(1)
        }
    }
}
