import SwiftUI

struct StatCard<Footer: View>: View {
    let icon: String
    let title: String
    var tag: String?
    let value: String
    var detail: String?
    var dark = false
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(dark ? Theme.ink : .white)
                    .background(dark ? Color.white : Theme.ink, in: RoundedRectangle(cornerRadius: 5))
                Text(title).font(.cardTitle).foregroundStyle(dark ? .white : Theme.ink)
                Spacer()
                if let tag {
                    Text(tag)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(dark ? .white.opacity(0.7) : Theme.muted)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(dark ? Color.white.opacity(0.12) : Theme.canvas, in: RoundedRectangle(cornerRadius: 5))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.bigNumber).foregroundStyle(dark ? .white : Theme.ink)
                if let detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(dark ? .white.opacity(0.6) : Theme.muted)
                }
            }
            footer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(dark ? Theme.ink : Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(dark ? .clear : Theme.line))
    }
}

struct MetricCell: View {
    let icon: String
    let title: String
    let value: String
    var note: String?
    var noteColor: Color = Theme.muted

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.muted)
            }
            Text(value).font(.system(size: 20, weight: .bold).monospacedDigit()).foregroundStyle(Theme.ink)
            if let note {
                Text(note).font(.system(size: 11)).foregroundStyle(noteColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Activity by weekday and hour (last four weeks), in Claude orange.
struct WorkRhythm: View {
    let heatmap: [UInt32]
    private let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        let peak = max(heatmap.max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Work rhythm", systemImage: "square.grid.3x3.fill").font(.cardTitle)
                Spacer()
                Text("Last 4 weeks").font(.label).foregroundStyle(Theme.faint)
            }
            VStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { day in
                    HStack(spacing: 3) {
                        Text(days[day]).font(.system(size: 10)).foregroundStyle(Theme.faint).frame(width: 28, alignment: .leading)
                        ForEach(0..<24, id: \.self) { hour in
                            let v = heatmap.count == 168 ? heatmap[day * 24 + hour] : 0
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(v == 0 ? Theme.line : Theme.claude.opacity(0.25 + 0.75 * Double(v) / Double(peak)))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
                HStack(spacing: 3) {
                    Spacer().frame(width: 28)
                    ForEach(0..<24, id: \.self) { hour in
                        Text(hour % 6 == 0 ? (hour == 0 ? "12a" : hour == 12 ? "12p" : hour < 12 ? "\(hour)a" : "\(hour - 12)p") : "")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.faint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            HStack(spacing: 4) {
                Spacer()
                Text("Less").font(.system(size: 10)).foregroundStyle(Theme.faint)
                ForEach([0.0, 0.3, 0.55, 0.8, 1.0], id: \.self) { f in
                    RoundedRectangle(cornerRadius: 2).fill(f == 0 ? Theme.line : Theme.claude.opacity(0.25 + 0.75 * f)).frame(width: 10, height: 10)
                }
                Text("More").font(.system(size: 10)).foregroundStyle(Theme.faint)
            }
        }
        .card()
    }
}

/// Dark list of sessions running right now.
struct LiveNowCard: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live now").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                Spacer()
                let working = model.sessions.filter { $0.status == .working || $0.status == .needsYou }.count
                Text("\(working)/\(model.sessions.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Theme.warning, in: Capsule())
            }
            if model.sessions.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "moon.zzz").font(.title2).foregroundStyle(.white.opacity(0.35))
                    Text("No agents running").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                    Text("Start Claude Code or Codex and it shows up here.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                ForEach(model.sessions.prefix(5), id: \.key) { session in
                    HStack(spacing: 10) {
                        AgentBadge(agent: AgentKind(agentName: session.agent) ?? .claudeCode, size: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.usage(for: session)?.title ?? session.name)
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                            Text("\(session.name) · \(Format.relative(Int64(session.lastEventMs)))")
                                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                        }
                        Spacer()
                        Circle().fill(StatusPill.style(session.status).1).frame(width: 8, height: 8)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

/// Heard-style setup card: everything in place, or the next thing to do.
struct SetupBanner: View {
    @Bindable var model: AppModel

    private var steps: [(String, Bool, String, () -> Void)] {
        [
            ("Sign in with Google", model.isSignedIn, "Sign in", { model.signIn() }),
            ("Start your subscription", { if case .active = model.accountState { return true }; return false }(), "Subscribe", { model.openCheckout() }),
            ("Connect Claude Code or Codex", model.anyHooksInstalled, "Connect", { model.page = .agents }),
            ("Let Hear Agent listen on this Mac", model.engineError == nil, "Retry", {}),
        ]
    }

    var body: some View {
        let next = steps.first { !$0.1 }
        HStack(spacing: 14) {
            Circle()
                .fill(.white.opacity(0.75))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: next == nil ? "checkmark" : "sparkles").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink))
            VStack(alignment: .leading, spacing: 3) {
                Text(next == nil ? "Everything is in place." : "Finish setting up Hear Agent")
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.ink)
                if let next {
                    Text("Next: \(next.0). \(steps.filter(\.1).count) of \(steps.count) done.")
                        .font(.system(size: 12)).foregroundStyle(Theme.ink.opacity(0.7))
                } else {
                    Text("You'll hear when an agent needs approval, finishes, or stops.")
                        .font(.system(size: 12)).foregroundStyle(Theme.ink.opacity(0.7))
                }
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { i in
                    Circle().fill(steps[i].1 ? Theme.success : Theme.ink.opacity(0.15)).frame(width: 7, height: 7).help(steps[i].0)
                }
            }
            if let next {
                Button(next.2, action: next.3).buttonStyle(PrimaryButtonStyle())
            } else if let last = model.history.first {
                Button("Replay last update") { model.replay(last) }.buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [Color(red: 0.93, green: 0.9, blue: 1.0), Color(red: 0.88, green: 0.95, blue: 0.97), Color(red: 0.95, green: 0.93, blue: 0.86)],
                           startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(Theme.faint)
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
            Text(message).font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .card()
    }
}

/// One row in the recent spoken updates list.
struct SpokenRow: View {
    @Bindable var model: AppModel
    let update: SpokenUpdate

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(update.text).font(.system(size: 12)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                Text("\(model.sessionName(forKey: update.sessionKey)) · \(update.at.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10)).foregroundStyle(Theme.faint)
            }
            Spacer()
            Button { model.replay(update) } label: { Image(systemName: "play.fill") }
                .buttonStyle(SoftButtonStyle())
                .help("Replay (free)")
        }
    }

    private var icon: String {
        switch update.kind {
        case .approval: "hand.raised.fill"
        case .summary: "checkmark"
        case .stopFailure: "exclamationmark"
        }
    }

    private var color: Color {
        switch update.kind {
        case .approval: Theme.warning
        case .summary: Theme.success
        case .stopFailure: Theme.danger
        }
    }
}
