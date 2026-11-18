import SwiftUI

struct NotchView: View {
    @Bindable var model: AppModel
    @Bindable var state: NotchState
    let controller: NotchController?

    var body: some View {
        let size = state.expanded ? state.expandedSize : state.collapsedSize
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: state.expanded ? 24 : 12, bottomTrailingRadius: state.expanded ? 24 : 12, style: .continuous)
                .fill(Theme.notchBackground)
                .shadow(color: .black.opacity(state.expanded ? 0.35 : 0), radius: 18, y: 8)
            if state.expanded {
                expandedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else {
                collapsedContent
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .onTapGesture { if !state.expanded { controller?.expand() } }
    }

    // MARK: Collapsed: a few dots and a badge

    private var collapsedContent: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "waveform")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 5))
                ForEach(model.sessions.prefix(4), id: \.key) { s in
                    Circle().fill(StatusPill.style(s.status).1).frame(width: 5, height: 5)
                }
                if model.sessions.isEmpty {
                    Circle().fill(Theme.notchMuted.opacity(0.5)).frame(width: 4, height: 4)
                }
            }
            .frame(width: 46, alignment: .leading)
            .padding(.leading, 10)
            Spacer(minLength: state.notchSize.width - 20)
            Group {
                if !model.needsAttention.isEmpty {
                    Text("!")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Theme.warning, in: Circle())
                } else if model.isPlaying {
                    Image(systemName: "waveform").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent).symbolEffect(.variableColor.iterative)
                } else if model.muted {
                    Image(systemName: "speaker.slash.fill").font(.system(size: 10)).foregroundStyle(Theme.notchMuted)
                }
            }
            .frame(width: 30, alignment: .trailing)
            .padding(.trailing, 10)
        }
        .frame(height: state.notchSize.height)
    }

    // MARK: Expanded panel

    private var expandedContent: some View {
        VStack(spacing: 10) {
            header
                .padding(.top, state.notchSize.height + 4)
            ScrollView {
                VStack(spacing: 8) {
                    switch state.tab {
                    case .sessions: NotchSessions(model: model)
                    case .usage: NotchUsage(model: model)
                    case .servers: NotchServers(model: model)
                    case .actions: NotchActions(model: model)
                    case .routes: NotchRoutes()
                    case .voice: NotchUpdates(model: model)
                    }
                }
                .padding(.bottom, 54)
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .bottom) { tabBar.padding(.bottom, 12) }
        .foregroundStyle(Theme.notchText)
    }

    private var header: some View {
        let report = model.usage.report
        return HStack(spacing: 8) {
            Text(state.tab.title).font(.system(size: 15, weight: .bold))
            Button { model.usage.refresh(); model.servers.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).foregroundStyle(Theme.notchMuted)
            chip(.claudeCode, "5H \(Format.percent(report?.claudeFiveHour.usedPercent ?? 0))")
            chip(.codex, "7D \(Format.percent(report?.codex?.weekly.usedPercent ?? report?.claudeWeekly.usedPercent ?? 0))")
            chip(nil, "MO \(Format.usd(report?.month.costUsd ?? 0))")
            Spacer()
            iconButton(state.pinned ? "pin.fill" : "pin", active: state.pinned) { state.pinned.toggle() }
                .help(state.pinned ? "Unpin" : "Keep open")
            iconButton("macwindow", active: false) { controller?.openDashboard() }
                .help("Open dashboard")
            iconButton(model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", active: false) { model.muted.toggle() }
                .help(model.muted ? "Unmute" : "Mute")
        }
    }

    private func chip(_ agent: AgentKind?, _ text: String) -> some View {
        HStack(spacing: 4) {
            if let agent {
                RoundedRectangle(cornerRadius: 2).fill(agent.color).frame(width: 7, height: 7)
            } else {
                Image(systemName: "calendar").font(.system(size: 8))
            }
            Text(text).font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Theme.notchCardRaised, in: RoundedRectangle(cornerRadius: 6))
    }

    private func iconButton(_ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(active ? Color.white : Theme.notchCardRaised, in: Circle())
                .foregroundStyle(active ? Color.black : Theme.notchText)
        }
        .buttonStyle(.plain)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(NotchTab.allCases) { tab in
                Button { withAnimation(.easeOut(duration: 0.15)) { state.tab = tab } } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 34, height: 28)
                            .background(state.tab == tab ? Color.white.opacity(0.16) : .clear, in: Capsule())
                            .foregroundStyle(state.tab == tab ? .white : Theme.notchMuted)
                        if tab == .sessions && !model.needsAttention.isEmpty {
                            Circle().fill(Theme.warning).frame(width: 6, height: 6).offset(x: -5, y: 3)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
    }
}

// MARK: Tabs

private struct NotchSessions: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.sessions.isEmpty {
            NotchEmpty(icon: "moon.zzz", text: "No agents running. Start Claude Code or Codex.")
        }
        ForEach(model.sessions, id: \.key) { s in
            let u = model.usage(for: s)
            let attention = s.status == .needsYou || s.status == .failed
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    AgentBadge(agent: AgentKind(agentName: s.agent) ?? .claudeCode, size: 18)
                    Text(u?.title ?? s.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer()
                    if attention {
                        Text(s.status == .failed ? "Stopped" : "Needs you").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(s.status == .failed ? Theme.danger : Theme.warning)
                    } else if let u {
                        Text(Format.usd(u.costUsd)).font(.system(size: 11, weight: .semibold).monospacedDigit())
                    }
                    Text(Format.relative(Int64(s.lastEventMs))).font(.system(size: 10)).foregroundStyle(Theme.notchMuted)
                }
                if attention {
                    Label(s.status == .failed ? "RUN STOPPED" : "PERMISSION PENDING", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(s.status == .failed ? Theme.danger : Theme.warning)
                    Text(s.lastUpdate)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
                    HStack(spacing: 8) {
                        Button { TerminalLauncher.focus(cwd: s.cwd) } label: {
                            Label("Open Terminal", systemImage: "terminal").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NotchButtonStyle(color: Theme.success))
                        Button { model.togglePin(s) } label: {
                            Label(s.pinned ? "Unpin" : "Pin", systemImage: "pin").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NotchButtonStyle(color: Theme.notchCardRaised))
                    }
                } else {
                    HStack(spacing: 10) {
                        if let branch = u?.branch { Label(branch, systemImage: "arrow.triangle.branch").lineLimit(1) }
                        if let model = u?.model, !model.isEmpty { Text(Format.shortModel(model)).lineLimit(1) }
                        Text(u?.project ?? s.name).lineLimit(1)
                    }
                    .font(.system(size: 10)).foregroundStyle(Theme.notchMuted)
                    HStack {
                        Text(s.lastUpdate).font(.system(size: 11)).foregroundStyle(Theme.notchText.opacity(0.8)).lineLimit(2)
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(StatusPill.style(s.status).1).frame(width: 6, height: 6)
                            Text(StatusPill.style(s.status).0).font(.system(size: 10, weight: .medium)).foregroundStyle(StatusPill.style(s.status).1)
                        }
                    }
                }
            }
            .padding(12)
            .background(Theme.notchCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(attention ? Theme.warning.opacity(0.5) : .white.opacity(0.05)))
        }
    }
}

private struct NotchUsage: View {
    @Bindable var model: AppModel

    var body: some View {
        let r = model.usage.report
        limitCard(.claudeCode, five: r?.claudeFiveHour, week: r?.claudeWeekly, estimated: true)
        if let c = r?.codex {
            limitCard(.codex, five: c.fiveHour, week: c.weekly, estimated: false)
        }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Activity").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(Date().formatted(.dateTime.month(.wide).year())).font(.system(size: 10)).foregroundStyle(Theme.notchMuted)
            }
            HStack {
                stat(Format.tokens(r?.month.tokens ?? 0), "Tokens")
                stat(Format.usd(r?.month.costUsd ?? 0), "Cost")
                stat(Format.usd(r?.month.forecastUsd ?? 0), "Forecast")
                stat("\(r?.month.activeDays ?? 0)/\(r?.month.daysInMonth ?? 30)", "Active days")
            }
            let days = Array((r?.days ?? []).suffix(14))
            let peak = max(days.map { $0.claudeTokens + $0.codexTokens }.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(days, id: \.day) { d in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(d.day == days.last?.day ? Theme.success : Theme.success.opacity(0.55))
                        .frame(height: max(3, 46 * Double(d.claudeTokens + d.codexTokens) / Double(peak)))
                }
            }
            .frame(height: 46, alignment: .bottom)
        }
        .padding(12)
        .background(Theme.notchCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func limitCard(_ agent: AgentKind, five: HearLimitWindow?, week: HearLimitWindow?, estimated: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 6) {
                AgentBadge(agent: agent, size: 18)
                Text(agent.shortName).font(.system(size: 12, weight: .semibold))
            }
            .frame(width: 80, alignment: .leading)
            VStack(spacing: 8) {
                row("5H", five, estimated)
                row("7D", week, estimated)
            }
        }
        .padding(12)
        .background(Theme.notchCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func row(_ label: String, _ w: HearLimitWindow?, _ estimated: Bool) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text("\(label) \(Format.percent(100 - (w?.usedPercent ?? 0))) remaining\(estimated ? " · est." : "")")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                Spacer()
                Text(Format.time(w?.resetsAtMs)).font(.system(size: 10)).foregroundStyle(Theme.notchMuted)
            }
            LimitBar(fraction: 1 - (w?.usedPercent ?? 0) / 100, height: 5, track: .white.opacity(0.1))
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 16, weight: .bold).monospacedDigit())
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.notchMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NotchServers: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.servers.servers.isEmpty {
            NotchEmpty(icon: "server.rack", text: "No dev servers listening.")
        }
        VStack(spacing: 0) {
            ForEach(model.servers.servers, id: \.pid) { s in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(":\(String(s.port))").font(.system(size: 14, weight: .bold, design: .monospaced))
                            Text(s.framework).font(.system(size: 12)).foregroundStyle(Theme.notchMuted)
                        }
                        Label((s.cwd as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
                            .font(.system(size: 10)).foregroundStyle(Theme.notchMuted).lineLimit(1)
                    }
                    Spacer()
                    Text(Format.duration(s.uptimeSeconds)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.notchMuted)
                    Button { model.servers.open(s) } label: { Image(systemName: "safari") }.buttonStyle(.plain)
                    Button { model.servers.reveal(s) } label: { Image(systemName: "folder") }.buttonStyle(.plain)
                    Button { model.servers.stop(s) } label: { Image(systemName: "stop.circle.fill").foregroundStyle(Theme.danger) }.buttonStyle(.plain)
                }
                .padding(.vertical, 10)
                Divider().overlay(.white.opacity(0.06))
            }
        }
        .padding(.horizontal, 12)
        .background(Theme.notchCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct NotchActions: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.actions.actions.isEmpty {
            NotchEmpty(icon: "bolt", text: "Save commands in the dashboard's Actions page to run them from here.")
        }
        VStack(spacing: 0) {
            ForEach(model.actions.actions) { a in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.name).font(.system(size: 13, weight: .semibold))
                        Text(">_ \(a.command)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.notchMuted).lineLimit(1)
                    }
                    Spacer()
                    Button { model.actions.run(a) } label: { Image(systemName: "play.fill") }.buttonStyle(.plain)
                }
                .padding(.vertical, 10)
                Divider().overlay(.white.opacity(0.06))
            }
        }
        .padding(.horizontal, 12)
        .background(Theme.notchCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct NotchRoutes: View {
    private let agents = AgentRoutes.all()

    var body: some View {
        ForEach(agents) { agent in
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(agent.color).frame(width: 18, height: 18)
                    .overlay(Image(systemName: agent.symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(.white))
                Text(agent.name).font(.system(size: 12, weight: .semibold))
                Text("· \(agent.mcpServers) MCP").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.notchMuted)
                Spacer()
                ForEach(agent.routes.filter(\.exists).prefix(4)) { route in
                    Button { agent.open(route) } label: {
                        Image(systemName: route.symbol).font(.system(size: 11)).frame(width: 26, height: 22)
                            .background(Theme.notchCardRaised, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(route.name)
                }
            }
            .padding(10)
            .background(Theme.notchCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct NotchUpdates: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.history.isEmpty {
            NotchEmpty(icon: "waveform", text: "Spoken updates from this run appear here. Replays are free.")
        }
        ForEach(model.history.prefix(8)) { update in
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(color(update.kind)).frame(width: 7, height: 7).padding(.top, 5)
                VStack(alignment: .leading, spacing: 3) {
                    Text(update.text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Text(update.at.formatted(date: .omitted, time: .shortened)).font(.system(size: 10)).foregroundStyle(Theme.notchMuted)
                }
                Spacer()
                Button { model.replay(update) } label: { Image(systemName: "play.circle.fill").font(.system(size: 16)) }.buttonStyle(.plain)
            }
            .padding(10)
            .background(Theme.notchCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func color(_ kind: HearSpeechKind) -> Color {
        switch kind {
        case .approval: Theme.warning
        case .summary: Theme.success
        case .stopFailure: Theme.danger
        }
    }
}

private struct NotchEmpty: View {
    let icon: String
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Theme.notchMuted)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.notchMuted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(Theme.notchCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct NotchButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .background(color.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
