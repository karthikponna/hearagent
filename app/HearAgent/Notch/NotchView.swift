import SwiftUI

struct NotchView: View {
    @Bindable var model: AppModel
    @Bindable var state: NotchState
    let controller: NotchController?

    /// Opening and closing morph the outline out of the notch and back: both layers stay laid out
    /// at their own full size, centred under the camera, and the moving outline reveals or hides
    /// them, so nothing reflows mid-animation. Content fades in just behind the edge and out ahead of it.
    var body: some View {
        let expanded = state.expanded
        let size = expanded ? state.expandedSize : state.collapsedSize
        let shape = NotchShape(ear: expanded ? NotchShape.expandedEar : NotchShape.collapsedEar, bottomRadius: expanded ? 30 : 12)
        ZStack(alignment: .top) {
            expandedContent
                .padding(.horizontal, NotchShape.expandedEar)
                .frame(width: state.expandedSize.width, height: state.expandedSize.height)
                .geometryGroup()
                .opacity(expanded ? 1 : 0)
                .animation(expanded ? .easeOut(duration: 0.22).delay(0.05) : .easeIn(duration: 0.1), value: expanded)
                .allowsHitTesting(expanded)
            collapsedContent
                .padding(.horizontal, NotchShape.collapsedEar)
                .frame(width: state.collapsedSize.width, height: state.collapsedSize.height)
                .geometryGroup()
                .contentShape(Rectangle())
                .onTapGesture { controller?.expand() }
                .opacity(expanded ? 0 : 1)
                .animation(expanded ? .easeIn(duration: 0.08) : .easeOut(duration: 0.2).delay(0.12), value: expanded)
                .allowsHitTesting(!expanded)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(shape.fill(Theme.notchBackground))
        .clipShape(shape)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Collapsed: an agent mark, a few dots and a badge

    private var collapsedContent: some View {
        let lead = model.sessions.first
        return HStack(spacing: 0) {
            HStack(spacing: 7) {
                PixelCat(mood: !model.needsAttention.isEmpty ? .needsYou : lead?.status == .working ? .working : .idle,
                         gaze: state.gaze, paused: state.expanded)
                HStack(spacing: 3) {
                    ForEach(Array(model.sessions.prefix(4).enumerated()), id: \.offset) { i, s in
                        Circle().fill(StatusPill.color(s.status).opacity(i == 0 ? 1 : 0.45)).frame(width: 5, height: 5)
                    }
                    if model.sessions.isEmpty {
                        Circle().fill(Theme.notchMuted.opacity(0.5)).frame(width: 4, height: 4)
                    }
                }
            }
            .frame(width: 58, alignment: .leading)
            .padding(.leading, 12)
            Spacer(minLength: state.notchSize.width - 34)
            Group {
                if !model.needsAttention.isEmpty {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Theme.orange, in: Circle())
                } else if model.isPlaying {
                    Image(systemName: "waveform").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.amber).symbolEffect(.variableColor.iterative)
                } else if model.muted {
                    Image(systemName: "speaker.slash.fill").font(.system(size: 10)).foregroundStyle(Theme.notchMuted)
                }
            }
            .frame(width: 30, alignment: .trailing)
            .padding(.trailing, 12)
        }
        .frame(height: state.notchSize.height)
    }

    // MARK: Expanded panel

    private var expandedContent: some View {
        VStack(spacing: 12) {
            header
                .padding(.top, state.notchSize.height + 8)
            ScrollView {
                VStack(spacing: 10) {
                    switch state.tab {
                    case .sessions: NotchSessions(model: model)
                    case .usage: NotchUsage(model: model)
                    case .servers: NotchServers(model: model)
                    case .routes: NotchRoutes()
                    case .voice: NotchUpdates(model: model)
                    }
                }
                .padding(.bottom, 64)
            }
            .scrollIndicators(.never)
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 36)
                    Color.clear.frame(height: 30)
                }
            }
        }
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) { tabBar.padding(.bottom, 14) }
        .foregroundStyle(Theme.notchText)
    }

    private var header: some View {
        let report = model.usage.report
        return HStack(spacing: 8) {
            Text(state.tab.title).font(.system(size: 17, weight: .bold))
            RefreshButton(spinning: model.usage.isLoading) { model.usage.refresh(); model.servers.refresh() }
            TimelineView(.everyMinute) { context in
                HStack(spacing: 9) {
                    LimitWing(kind: .claudeCode, window: report?.claudeFiveHour, now: context.date)
                        .help("Claude Code's 5-hour window, estimated from local transcripts")
                    if let codex = report?.codex {
                        Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 12)
                        LimitWing(kind: .codex, window: codex.fiveHour, now: context.date)
                            .help("Codex's 5-hour window")
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(Theme.notchCard, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
            }
            chip(Image(systemName: "calendar").font(.system(size: 10)).foregroundStyle(Theme.notchMuted), "MO", Format.usdWhole(report?.month.costUsd ?? 0))
            Spacer()
            iconButton(state.pinned ? "pin.fill" : "pin", active: state.pinned) { state.pinned.toggle() }
                .help(state.pinned ? "Unpin" : "Keep open")
            iconButton(model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", active: false) { model.muted.toggle() }
                .contentTransition(.symbolEffect(.replace))
                .help(model.muted ? "Unmute spoken updates" : "Mute spoken updates")
            iconButton("gearshape", active: false) { controller?.openDashboard(.settings) }
                .help("Settings")
        }
    }

    private func chip(_ icon: some View, _ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            icon
            Text("\(label) \(value)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.notchText.opacity(0.9))
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Theme.notchCard, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
    }

    private func iconButton(_ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(active ? Theme.notchCardRaised : .clear, in: Circle())
                .foregroundStyle(active ? Color.white : Theme.notchText.opacity(0.85))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var tabBar: some View {
        NotchTabBar(selection: $state.tab, alert: !model.needsAttention.isEmpty)
    }
}

/// The notch outline: square top corners that flare into the menu bar with concave "ears",
/// straight sides, rounded bottom corners. Both radii animate.
struct NotchShape: Shape {
    static let collapsedEar: CGFloat = 6
    static let expandedEar: CGFloat = 14

    var ear: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(ear, bottomRadius) }
        set { ear = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let e = min(ear, rect.width / 4, rect.height / 2)
        let r = min(bottomRadius, (rect.width - 2 * e) / 2, rect.height - e)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + e, y: rect.minY + e), control: CGPoint(x: rect.minX + e, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + e, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + e + r, y: rect.maxY), control: CGPoint(x: rect.minX + e, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - e - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - e, y: rect.maxY - r), control: CGPoint(x: rect.maxX - e, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - e, y: rect.minY + e))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - e, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// Where the cat looks: each axis is -1, 0 or 1 (left/up, centre, right/down).
struct Gaze: Equatable {
    var x = 0
    var y = 0
    static let center = Gaze()

    /// Toward `target` from `origin`, in screen points (y up). Only a clear lean along an axis
    /// moves the eyes that way, so a cursor straight below looks down rather than down-left.
    init(from origin: CGPoint, to target: CGPoint) {
        let dx = target.x - origin.x, dy = origin.y - target.y
        let lean = max(12, 0.38 * hypot(dx, dy))
        x = dx > lean ? 1 : dx < -lean ? -1 : 0
        y = dy > lean ? 1 : dy < -lean ? -1 : 0
    }

    init() {}
}

/// Hear Agent's pixel cat beside the camera. Its eyes follow the cursor, it blinks every few
/// seconds, flicks its ears while an agent works, and squashes down when one needs you.
struct PixelCat: View {
    enum Mood { case idle, working, needsYou }
    let mood: Mood
    var gaze = Gaze.center
    var paused = false
    var pixel: CGFloat = 1.5

    static let color = Color(hex: 0x3DDC84)
    private static let head: [String] = [
        ".XX........XX.",
        ".XXX......XXX.",
        ".XXX......XXX.",
        ".XXXX....XXXX.",
        ".XXXXXXXXXXXX.",
        ".XXXXXXXXXXXX.",
        "XXXXXXXXXXXXXX",
        "XXXXXXXXXXXXXX",
        "XXXXXXXXXXXXXX",
        "XXXXXXXXXXXXXX",
        "XXXXXXXXXXXXXX",
        ".XXXXXXXXXXXX.",
        ".XXXXXXXXXXXX.",
        "..XXXXXXXXXX..",
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: paused)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let blinking = t.truncatingRemainder(dividingBy: 6) < 0.17
            // Ears fold in two steps, then spring back: 0.05s thin, 0.05s flat.
            let fold: Int = switch mood {
            case .needsYou: Self.foldStep(t.truncatingRemainder(dividingBy: 1.2))
            case .working: Self.foldStep(t.truncatingRemainder(dividingBy: 2.6))
            case .idle: 0
            }
            Canvas { ctx, _ in
                var rows = Self.head
                if fold > 0 {
                    rows[0] = fold == 1 ? ".X..........X." : ".............."
                    if mood == .needsYou { rows[11] = "XXXXXXXXXXXXXX" }
                }
                let eyes = Self.eyes(gaze, blinking: blinking)
                // One path, so neighbouring pixels share edges instead of showing seams at odd sizes.
                var path = Path()
                for (y, row) in rows.enumerated() {
                    for (x, cell) in row.enumerated() where cell == "X" && !eyes.contains(y * 14 + x) {
                        path.addRect(CGRect(x: CGFloat(x) * pixel, y: CGFloat(y) * pixel, width: pixel, height: pixel))
                    }
                }
                ctx.fill(path, with: .color(Self.color))
            }
            .frame(width: 14 * pixel, height: 14 * pixel)
            .shadow(color: Self.color.opacity(0.5), radius: 3)
        }
    }

    private static func foldStep(_ phase: Double) -> Int {
        phase < 0.05 ? 1 : phase < 0.1 ? 2 : 0
    }

    /// The eye holes, as `row * 14 + column`. Open eyes are 2×3; looking sideways, the eye on
    /// that side narrows to one column, as if the head had turned. A blink keeps only the bottom row.
    private static func eyes(_ gaze: Gaze, blinking: Bool) -> Set<Int> {
        let (left, right): ([Int], [Int]) = switch gaze.x {
        case 1: ([4, 5], [11])
        case -1: ([2], [8, 9])
        default: ([3, 4], [9, 10])
        }
        let bottom = 9 + gaze.y
        let rows = blinking ? [bottom] : [bottom - 2, bottom - 1, bottom]
        return Set(rows.flatMap { r in (left + right).map { r * 14 + $0 } })
    }
}

/// "✳ 5h 11% 4h1m": the agent, how much of its window is used, and the time until it resets.
private struct LimitWing: View {
    let kind: AgentKind
    let window: HearLimitWindow?
    let now: Date

    var body: some View {
        let used = window?.used(at: now) ?? 0
        HStack(spacing: 5) {
            AgentMark(kind: kind, size: 13)
            Text("5h").foregroundStyle(Theme.notchText.opacity(0.9))
            Text(Format.percent(used)).foregroundStyle(used >= 90 ? Theme.red : used >= 70 ? Theme.amber : Theme.notchGreen)
            Text(Self.left(window?.resetsAtMs, now: now) ?? "idle").foregroundStyle(Theme.notchMuted)
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .lineLimit(1)
        .fixedSize()
    }

    /// "4h1m", "38m", "2d3h".
    static func left(_ ms: Int64?, now: Date) -> String? {
        guard let ms else { return nil }
        let minutes = Int((Double(ms) / 1000 - now.timeIntervalSince1970) / 60)
        guard minutes > 0 else { return nil }
        let (d, h, m) = (minutes / 1440, (minutes % 1440) / 60, minutes % 60)
        if d > 0 { return "\(d)d\(h)h" }
        return h > 0 ? "\(h)h\(m)m" : "\(m)m"
    }
}

/// The month as an 8-bit level meter, in the critter's pixels: one segmented column per day,
/// lit by that day's tokens. Days still to come sit faint, and today carries a blinking pixel.
struct MonthMeter: View {
    let days: [HearDayUsage]
    let daysInMonth: Int

    private static let segments = 6
    @State private var lit: Bool
    @State private var blink = false

    init(days: [HearDayUsage], daysInMonth: Int, animated: Bool = true) {
        self.days = days
        self.daysInMonth = daysInMonth
        _lit = State(initialValue: !animated)
    }

    var body: some View {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.component(.day, from: now)
        let prefix = String(DateFormatter.yearMonthDay.string(from: now).prefix(8))
        let tokens = Dictionary(days.compactMap { d -> (Int, UInt64)? in
            guard d.day.hasPrefix(prefix), let day = Int(d.day.suffix(2)) else { return nil }
            return (day, d.claudeTokens + d.codexTokens)
        }, uniquingKeysWith: +)
        let peak = Double(max(tokens.values.max() ?? 0, 1))
        let month = now.formatted(.dateTime.month(.abbreviated))

        HStack(alignment: .top, spacing: 4) {
            ForEach(1...max(daysInMonth, 1), id: \.self) { day in
                let used = tokens[day] ?? 0
                let level = used == 0 ? 0 : max(1, Int((Double(used) / peak * Double(Self.segments)).rounded(.up)))
                VStack(spacing: 5) {
                    column(level: level, future: day > today, today: day == today)
                        .animation(.easeOut(duration: 0.28).delay(Double(day) * 0.014), value: lit)
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color(hex: 0x3DDC84))
                        .frame(width: 4, height: 4)
                        .shadow(color: Color(hex: 0x3DDC84).opacity(0.8), radius: 3)
                        .opacity(day == today ? (blink ? 1 : 0.3) : 0)
                }
                .help(day > today ? "\(month) \(day)" : "\(month) \(day) · \(Format.tokens(used)) tokens")
            }
        }
        .task {
            lit = false
            try? await Task.sleep(for: .milliseconds(80))
            lit = true
            withAnimation(.easeInOut(duration: 0.8).repeatForever()) { blink = true }
        }
    }

    private func column(level: Int, future: Bool, today: Bool) -> some View {
        VStack(spacing: 2.5) {
            ForEach((0..<Self.segments).reversed(), id: \.self) { segment in
                let on = lit && segment < level
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(on ? Self.green(segment, today: today) : Color.white.opacity(future ? 0.035 : 0.08))
                    .frame(height: 4.5)
            }
        }
        .shadow(color: today && level > 0 && lit ? Color(hex: 0x3DDC84).opacity(0.45) : .clear, radius: 5)
    }

    /// Deep green at the floor, brightening toward the top, like an LED meter.
    private static func green(_ segment: Int, today: Bool) -> Color {
        let t = Double(segment) / Double(segments - 1)
        let (dim, bright): (Double, Double) = today ? (0.75, 1) : (0.42, 0.78)
        return Color(hex: 0x3DDC84).opacity(dim + (bright - dim) * t)
    }
}

extension HearLimitWindow {
    /// Percent used right now. A window whose reset time has passed has started over, even if
    /// the last reading (Codex's, say, from a session days ago) still shows usage.
    func used(at now: Date) -> Double {
        if let resetsAtMs, Double(resetsAtMs) / 1000 <= now.timeIntervalSince1970 { return 0 }
        return usedPercent
    }

    /// When it resets, or nil once that moment has passed.
    func upcomingReset(at now: Date) -> Int64? {
        resetsAtMs.flatMap { Double($0) / 1000 > now.timeIntervalSince1970 ? $0 : nil }
    }
}

/// A refresh arrow that turns a full circle on every press, and keeps turning while loading.
private struct RefreshButton: View {
    let spinning: Bool
    let action: () -> Void
    @State private var turns = 0.0

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.7)) { turns += 1 }
            action()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .rotationEffect(.degrees(turns * 360))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.notchMuted)
        .help("Refresh")
        .onChange(of: spinning) { _, loading in
            if loading { withAnimation(.easeInOut(duration: 0.7)) { turns += 1 } }
        }
    }
}

/// A floating glass bar: icons, with the selected tab opening into an icon-and-name pill.
private struct NotchTabBar: View {
    @Binding var selection: NotchTab
    let alert: Bool
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NotchTab.allCases) { tab in
                if tab.secondary {
                    Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 16).padding(.horizontal, 5)
                }
                let selected = selection == tab
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { selection = tab }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 13.5, weight: selected ? .semibold : .medium))
                            .symbolVariant(selected ? .fill : .none)
                            .frame(width: 18)
                        if selected {
                            Text(tab.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).fixedSize()
                                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                        }
                    }
                    .padding(.horizontal, selected ? 13 : 11)
                    .frame(height: 34)
                    .foregroundStyle(selected ? Color.white : Theme.notchMuted)
                    .background {
                        if selected {
                            Capsule().fill(Color.white.opacity(0.15))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if tab == .sessions && alert {
                            Circle().fill(Theme.orange).frame(width: 7, height: 7)
                                .overlay(Circle().strokeBorder(Color(hex: 0x2C2C2E), lineWidth: 1.5))
                                .offset(x: -6, y: 5)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(NotchPressStyle())
                .help(tab.title)
            }
        }
        .padding(4)
        .background(Color(hex: 0x2C2C2E).opacity(0.94), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.09)))
        .shadow(color: .black.opacity(0.55), radius: 14, y: 4)
    }
}

// MARK: Sessions

private struct NotchSessions: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.sessions.isEmpty {
            NotchEmpty(icon: "moon.zzz", text: "No agents running. Start Claude Code or Codex.")
        }
        ForEach(model.sessions, id: \.key) { s in
            if s.status == .needsYou || s.status == .failed {
                AttentionCard(model: model, session: s, showsShortcuts: model.pendingApprovals.first?.key == s.key)
            } else {
                RunningCard(model: model, session: s)
            }
        }
    }
}

private struct AttentionCard: View {
    @Bindable var model: AppModel
    let session: HearSession
    /// Only the first waiting request answers to ⌘Y / ⇧⌘Y / ⌘N.
    var showsShortcuts = true

    var body: some View {
        let u = model.usage(for: session)
        let failed = session.status == .failed
        let pending = session.pending
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                AgentMark(name: session.agent, size: 22)
                Text(u?.title ?? session.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(failed ? "Stopped" : "Needs you").font(.system(size: 13, weight: .semibold)).foregroundStyle(failed ? Theme.red : Theme.orange)
            }
            Label {
                Text(failed ? "RUN STOPPED" : (pending.map { "PERMISSION PENDING · \($0.tool.uppercased())" } ?? "WAITING FOR YOU"))
            } icon: {
                Image(systemName: failed ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
            }
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(failed ? Theme.red : Theme.orange)
            Text(pending.map { $0.subject.isEmpty ? $0.action : $0.subject } ?? session.lastUpdate)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(3)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0x2A2A2C), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if pending != nil {
                HStack(spacing: 8) {
                    decision("Deny", showsShortcuts ? "⌘N" : "", Color(hex: 0xC8463F)) { model.decide(session, .deny) }
                    decision("Always allow", showsShortcuts ? "⇧⌘Y" : "", Color(hex: 0xD49A2A)) { model.decide(session, .alwaysAllow) }
                        .help(model.suggestedRule(for: session).map { "Allow \($0.tool) \($0.pattern) from now on" } ?? "")
                    decision("Allow", showsShortcuts ? "⌘Y" : "", Color(hex: 0x2E9862)) { model.decide(session, .allow) }
                }
            }
            HStack {
                Spacer()
                Button { model.decide(session, .terminal) } label: {
                    Label("Open Terminal", systemImage: "apple.terminal").font(.system(size: 12.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.notchMuted)
            }
        }
        .padding(14)
        .background(Theme.notchCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder((failed ? Theme.red : Theme.orange).opacity(0.55), lineWidth: 1))
    }

    private func decision(_ title: String, _ shortcut: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 13.5, weight: .bold))
                if !shortcut.isEmpty {
                    Text(shortcut).font(.system(size: 11, weight: .semibold)).opacity(0.6)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(color, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(NotchPressStyle())
    }
}

private struct RunningCard: View {
    @Bindable var model: AppModel
    let session: HearSession

    var body: some View {
        let u = model.usage(for: session)
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                AgentMark(name: session.agent, size: 22)
                Text(u?.title ?? session.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 6)
                Text(Format.ago(Int64(session.lastEventMs))).font(.system(size: 12.5)).foregroundStyle(Theme.notchMuted)
                Button { if let u { TerminalLauncher.resume(u) } else { TerminalLauncher.focus(cwd: session.cwd) } } label: {
                    Image(systemName: "apple.terminal").font(.system(size: 12)).notchHitArea()
                }
                .buttonStyle(.plain).foregroundStyle(Theme.notchMuted)
            }
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 10.5))
                Text([u?.branch ?? session.name.components(separatedBy: " · ").dropFirst().first, u.map { Format.shortModel($0.model) }].compactMap { $0 }.joined(separator: " · "))
                    .lineLimit(1)
                Spacer()
                if let u {
                    Text(Format.usd(u.costUsd)).font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                    Text("\(Format.tokens(u.tokens.total))").font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.notchGreen)
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Theme.notchMuted)
            if !session.lastPrompt.isEmpty {
                HStack {
                    Spacer(minLength: 60)
                    Text(session.lastPrompt).font(.system(size: 13)).lineLimit(2)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color(hex: 0x3A3A3C), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            if !session.lastMessage.isEmpty || session.status == .done {
                Text(session.lastMessage.isEmpty ? session.lastUpdate : session.lastMessage)
                    .font(.system(size: 13)).foregroundStyle(Theme.notchText.opacity(0.88)).lineLimit(2)
            }
            HStack(spacing: 6) {
                Text(">_").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.notchMuted)
                Text(session.activity?.line ?? (session.status == .done ? "Session complete" : "Thinking…"))
                    .font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Theme.notchMuted).lineLimit(1)
                Spacer()
                if session.status == .working {
                    HStack(spacing: 5) {
                        RunningDots()
                        Text("Running").font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(Theme.notchGreen)
                } else {
                    Text("Done").font(.system(size: 12.5, weight: .medium, design: .monospaced)).foregroundStyle(Theme.notchMuted)
                }
            }
        }
        .padding(14)
        .background(Theme.notchCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
    }
}

/// Three green dots that pulse in turn.
struct RunningDots: View {
    @State private var phase = 0
    let timer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { i in
                Circle().frame(width: 4, height: 4).opacity(phase == i ? 1 : 0.35)
            }
        }
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}

private struct NotchPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: Usage

private struct NotchUsage: View {
    @Bindable var model: AppModel

    var body: some View {
        let r = model.usage.report
        limitCard(.claudeCode, five: r?.claudeFiveHour, week: r?.claudeWeekly)
            .help("Estimated from local transcripts: your busiest past window counts as 100%.")
        if let c = r?.codex {
            limitCard(.codex, five: c.fiveHour, week: c.weekly)
        }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activity").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(Date().formatted(.dateTime.month(.wide).year())).font(.system(size: 12.5)).foregroundStyle(Theme.notchMuted)
            }
            HStack {
                stat(Format.tokens(r?.month.tokens ?? 0), "Tokens")
                stat(Format.usd(r?.month.costUsd ?? 0), "Cost")
                stat(Format.usd(r?.month.forecastUsd ?? 0), "By month end")
                    .help("What this month will cost if you keep spending at this month's daily pace")
                stat("\(r?.month.activeDays ?? 0)/\(r?.month.daysInMonth ?? 30)", "Active days")
            }
            MonthMeter(days: r?.days ?? [], daysInMonth: Int(r?.month.daysInMonth ?? 30))
        }
        .padding(14)
        .background(Theme.notchCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func limitCard(_ agent: AgentKind, five: HearLimitWindow?, week: HearLimitWindow?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                AgentMark(kind: agent, size: 20)
                Text(agent.shortName).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("Resets").font(.system(size: 11.5)).foregroundStyle(Theme.notchMuted)
            }
            row("5 hours", five)
            row("7 days", week)
        }
        .padding(14)
        .background(Theme.notchCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// "5 hours  ━━━━━━━━──  81% left   Nov 22, 4:07 AM"
    private func row(_ label: String, _ w: HearLimitWindow?) -> some View {
        let now = Date()
        let left = 100 - (w?.used(at: now) ?? 0)
        return HStack(spacing: 12) {
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.notchMuted)
                .frame(width: 58, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(left < 10 ? Theme.red : left < 25 ? Theme.amber : Theme.notchGreen)
                        .frame(width: geo.size.width * min(max(left / 100, 0), 1))
                }
            }
            .frame(height: 6)
            Text("\(Format.percent(left)) left").font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                .frame(width: 70, alignment: .trailing)
            Text(w?.upcomingReset(at: now).map(Self.resetDate) ?? "—").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.notchMuted)
                .frame(width: 110, alignment: .trailing)
        }
    }

    /// "Nov 22, 4:07 AM": always the date, so a weekly reset never reads as a bare weekday.
    static func resetDate(_ ms: Int64) -> String {
        Date(timeIntervalSince1970: Double(ms) / 1000).formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 17, weight: .bold).monospacedDigit())
            Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.notchMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Servers

private struct NotchServers: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.servers.servers.isEmpty {
            NotchEmpty(icon: "server.rack", text: "No dev servers listening.")
        } else {
            VStack(spacing: 0) {
                ForEach(model.servers.servers, id: \.pid) { s in
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text(":\(String(s.port))").font(.system(size: 15, weight: .bold, design: .monospaced))
                                Text(s.framework).font(.system(size: 13)).foregroundStyle(Theme.notchMuted)
                            }
                            Label(Format.path(s.cwd), systemImage: "folder")
                                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.notchMuted).lineLimit(1)
                        }
                        Spacer()
                        Text(Format.duration(s.uptimeSeconds)).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Theme.notchMuted)
                        Button { model.servers.open(s) } label: { Image(systemName: "safari").notchHitArea() }.buttonStyle(.plain).help("Open in browser")
                        Button { model.servers.reveal(s) } label: { Image(systemName: "folder").notchHitArea() }.buttonStyle(.plain).help("Show in Finder")
                        Button { model.servers.stop(s) } label: { Image(systemName: "stop.circle.fill").foregroundStyle(Theme.red).notchHitArea() }.buttonStyle(.plain).help("Stop")
                    }
                    .font(.system(size: 13))
                    .padding(.vertical, 12)
                    if s.pid != model.servers.servers.last?.pid { Divider().overlay(Color.white.opacity(0.07)) }
                }
            }
            .padding(.horizontal, 14)
            .background(Theme.notchCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: Routes

private struct NotchRoutes: View {
    private let agents = AgentRoutes.all()
    @State private var open: String? = "Claude"

    var body: some View {
        ForEach(agents) { agent in
            VStack(alignment: .leading, spacing: 12) {
                Button { withAnimation(.easeOut(duration: 0.18)) { open = open == agent.name ? nil : agent.name } } label: {
                    HStack(spacing: 9) {
                        AgentMark(agent.brand, size: 20)
                        Text(agent.name).font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Image(systemName: open == agent.name ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.notchMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if open == agent.name {
                    HStack(spacing: 8) {
                        ForEach(agent.routes) { route in
                            let exists = route.exists
                            Button { agent.open(route) } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        Image(systemName: "folder.fill").font(.system(size: 22))
                                            .foregroundStyle(agent.brand == .cursor || agent.brand == .opencode ? Color(white: 0.6) : agent.brand.color)
                                        Image(systemName: route.symbol).font(.system(size: 8, weight: .bold)).foregroundStyle(.white).offset(y: 2)
                                    }
                                    .opacity(exists ? 1 : 0.35)
                                    Text(route.name).font(.system(size: 12, weight: .medium)).foregroundStyle(exists ? .white : Theme.notchMuted)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(exists ? 0.06 : 0.03), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(!exists)
                            .help(route.path)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(14)
            .background(Theme.notchCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: Updates

private struct NotchUpdates: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.history.isEmpty {
            NotchEmpty(icon: "waveform", text: "Spoken updates from this run appear here. Replays are free.")
        }
        ForEach(model.history.prefix(8)) { update in
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(color(update.kind)).frame(width: 7, height: 7).padding(.top, 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(update.text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    Text(update.at.formatted(date: .omitted, time: .shortened)).font(.system(size: 11.5)).foregroundStyle(Theme.notchMuted)
                }
                Spacer()
                Button { model.replay(update) } label: { Image(systemName: "play.circle.fill").font(.system(size: 18)).notchHitArea() }.buttonStyle(.plain)
            }
            .padding(12)
            .background(Theme.notchCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func color(_ kind: HearSpeechKind) -> Color {
        switch kind {
        case .approval: Theme.orange
        case .summary: Theme.notchGreen
        case .stopFailure: Theme.red
        }
    }
}

extension View {
    /// A square tap target around a small glyph; a plain button only takes clicks on drawn pixels.
    func notchHitArea(_ size: CGFloat = 28) -> some View {
        frame(width: size, height: size).contentShape(Rectangle())
    }
}

private struct NotchEmpty: View {
    let icon: String
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Theme.notchMuted)
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.notchMuted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .background(Theme.notchCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct NotchButtonStyle: ButtonStyle {
    let color: Color
    var foreground: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.vertical, 8)
            .background(color.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
