import SwiftUI

struct VoicePage: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 16) {
                voiceCard
                momentsCard
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 16) {
                creditsCard
                historyCard
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Voice").font(.system(size: 17, weight: .bold))
            HStack(spacing: 14) {
                VoiceOrb(speaking: model.isPlaying).frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 3) {
                    Text("George · ElevenLabs").font(.system(size: 13, weight: .semibold))
                    Text("Warm, clear British voice. More voices are coming.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button {
                    if let last = model.history.first { model.replay(last) }
                } label: {
                    Label("Replay last", systemImage: "play.fill")
                }
                .buttonStyle(SoftButtonStyle())
                .disabled(model.history.isEmpty)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Volume").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(Format.percent(model.volume * 100)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.muted)
                }
                Slider(value: $model.volume, in: 0.1...1.0)
            }
            Divider()
            Toggle(isOn: $model.muted) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mute spoken updates").font(.system(size: 13, weight: .medium))
                    Text("Nothing is spoken and no credits are used while muted.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            .toggleStyle(.switch)
        }
        .card(padding: 18)
    }

    private var momentsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What you'll hear").font(.system(size: 17, weight: .bold))
            Text("Hear Agent stays quiet while agents work and speaks at three moments.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            moment(icon: "hand.raised.fill", color: Theme.warning, title: "Approval needed",
                   example: "“auth service needs approval to remove node_modules directory.”", isOn: $model.speakApprovals)
            Divider()
            moment(icon: "checkmark", color: Theme.success, title: "Task finished",
                   example: "“Hey, tool timeout mcp just wrapped up: the client now times out after 30 seconds and tests pass.”", isOn: $model.speakSummaries)
            Divider()
            moment(icon: "exclamationmark", color: Theme.danger, title: "Run stopped",
                   example: "“Heads up, ios app stopped: Codex hit a rate limit.”", isOn: $model.speakStops)
        }
        .card(padding: 18)
    }

    private func moment(icon: String, color: Color, title: String, example: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                    .frame(width: 26, height: 26).background(color.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(example).font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
    }

    private var creditsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Voice credits").font(.system(size: 17, weight: .bold))
                Spacer()
                Button("Account") { model.page = .account }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
            }
            switch model.accountState {
            case .active(let remaining, let total, let periodEnd):
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.number(remaining)).font(.bigNumber)
                    Text("of \(Format.number(total)) left").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                LimitBar(fraction: 1 - Double(remaining) / Double(max(total, 1)), height: 8)
                Text("About \(remaining / 180) more updates\(AppModel.renewalSuffix(periodEnd)). 1 credit = 1 spoken character.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            case .creditsExhausted(let periodEnd):
                Text("Credits used up").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.danger)
                Text("Spoken updates are paused\(AppModel.renewalSuffix(periodEnd)).").font(.system(size: 12)).foregroundStyle(Theme.muted)
            case .noSubscription:
                Text("No active plan").font(.system(size: 15, weight: .semibold))
                Button("Subscribe for $19/month") { model.openCheckout() }.buttonStyle(PrimaryButtonStyle(color: Theme.accent))
            case .signedOut:
                Text("Sign in to start hearing your agents.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                Button("Sign in with Google") { model.signIn() }.buttonStyle(PrimaryButtonStyle())
            case .offline:
                Text("Can't reach Hear Agent right now. Updates resume when you're back online.").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
        .card(padding: 18)
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent updates").font(.system(size: 17, weight: .bold))
                Spacer()
                Text("This run only · replays are free").font(.label).foregroundStyle(Theme.faint)
            }
            if model.history.isEmpty {
                Text("Nothing spoken yet.").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.vertical, 20)
            } else {
                ForEach(model.history) { update in
                    SpokenRow(model: model, update: update)
                    if update.id != model.history.last?.id { Divider() }
                }
            }
        }
        .card(padding: 18)
    }
}

/// Soft animated gradient circle, like a voice "presence".
struct VoiceOrb: View {
    var speaking = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(red: 0.75, green: 0.68, blue: 1.0), Theme.accent, Color(red: 0.32, green: 0.2, blue: 0.85)], center: .topLeading, startRadius: 2, endRadius: 50))
            Circle().strokeBorder(.white.opacity(0.6), lineWidth: 3).padding(2)
        }
        .scaleEffect(speaking && pulse ? 1.06 : 1)
        .shadow(color: Theme.accent.opacity(0.35), radius: speaking ? 10 : 6)
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true } }
    }
}

struct AgentsPage: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("On this Mac").font(.system(size: 17, weight: .bold))
                Text("Coding agents Hear Agent listens to.").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.bottom, 8)
                ForEach(AppModel.agents, id: \.self) { agent in
                    agentRow(agent)
                    Divider()
                }
                ForEach(["Cursor", "Gemini CLI", "OpenCode", "GitHub Copilot"], id: \.self) { name in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                            Text("Spoken updates coming soon").font(.system(size: 11)).foregroundStyle(Theme.faint)
                        }
                        Spacer()
                        Tag(text: "SOON", color: Theme.faint)
                    }
                    .padding(.vertical, 8)
                    if name != "GitHub Copilot" { Divider() }
                }
                if let error = model.hookError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(Theme.warning).padding(.top, 8)
                }
            }
            .card(padding: 18)
            .frame(maxWidth: .infinity)

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("How it connects").font(.system(size: 17, weight: .bold))
                    bullet("Hear Agent adds its hooks to the agent's settings file and saves a backup next to it (*.hearagent-backup).")
                    bullet("Hooks only talk to Hear Agent on this Mac. Turning an agent off removes only Hear Agent's entries.")
                    bullet("Restart sessions that were already running after you connect.")
                }
                .card(padding: 18)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Live sessions").font(.system(size: 17, weight: .bold))
                    if model.sessions.isEmpty {
                        Text("No sessions are reporting right now.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    ForEach(model.sessions, id: \.key) { s in
                        HStack(spacing: 8) {
                            AgentBadge(agent: AgentKind(agentName: s.agent) ?? .claudeCode)
                            Text(s.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Spacer()
                            StatusPill(status: s.status)
                        }
                    }
                }
                .card(padding: 18)
            }
            .frame(width: 360)
        }
    }

    private func agentRow(_ agent: AgentKind) -> some View {
        let on = model.hookStatus[agent] ?? false
        return HStack(spacing: 12) {
            AgentBadge(agent: agent, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.displayName).font(.system(size: 13, weight: .semibold))
                Text(on ? "Connected · restart running sessions after changes" : agentConfigPath(agent: agent))
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            if on {
                Tag(text: "● ACTIVE", color: Theme.success)
                Button("Reinstall") { model.setHooks(agent, enabled: true) }.buttonStyle(SoftButtonStyle())
                Button("Disconnect") { model.setHooks(agent, enabled: false) }.buttonStyle(SoftButtonStyle())
            } else {
                Button("Connect") { model.setHooks(agent, enabled: true) }.buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.vertical, 8)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Theme.accent).frame(width: 5, height: 5).padding(.top, 6)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}
