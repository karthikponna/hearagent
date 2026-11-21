import SwiftUI

/// The home page: is everything set up, and how Hear Agent reaches you.
struct OverviewPage: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StatusBanner(model: model)
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "On this Mac")
                    SetupChecklist(model: model)
                    tip
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "Where you'll hear from it")
                    NotchFeatureCard(model: model)
                }
                .frame(width: 400)
            }
        }
    }

    private var tip: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                .frame(width: 26).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Session not showing up?").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.ink)
                Text("Agents read their hooks when they start. Restart any Claude Code or Codex session that was already open when you connected.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.ink2).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// "Good evening, Karthik": the time of day on this Mac's clock and time zone, then the account name or the Mac's.
enum Greeting {
    static func title(for account: HearAccount?, at date: Date = Date()) -> String {
        // autoupdatingCurrent follows time zone changes (travel, Settings) without a relaunch.
        let hour = Calendar.autoupdatingCurrent.component(.hour, from: date)
        let part = switch hour {
        case 5..<12: "Good morning"
        case 12..<16: "Good afternoon"
        default: "Good evening"
        }
        let name = (account?.name.isEmpty == false ? account!.name : NSFullUserName()).split(separator: " ").first.map(String.init) ?? ""
        return name.isEmpty ? part : "\(part), \(name)"
    }
}

// MARK: Setup state

/// One thing Hear Agent needs, and whether it's done.
struct SetupStep: Identifiable {
    enum Action { case signIn, reloadAccount, retry, connect(AgentKind), subscribe, unmute }
    let id: String
    let title: String
    let ready: Bool
    let status: String
    let action: (label: String, kind: Action)?
    /// Blocking steps keep the banner from saying everything is in place.
    let required: Bool
    var agent: AgentKind?
    /// The banner's line when this is the next thing to do.
    var next = ""
}

extension AppModel {
    var setupSteps: [SetupStep] {
        let signedIn = account != nil
        // Signed in with Supabase, but the account didn't load from Hear Agent's server.
        let stuck = !signedIn && hasSession
        var steps = [
            SetupStep(id: "signin", title: "Signed in", ready: signedIn,
                      status: signedIn ? "Ready" : stuck ? (accountError == nil ? "Loading account…" : "Can't reach Hear Agent") : "Not signed in",
                      action: signedIn ? nil : stuck ? ("Retry", .reloadAccount) : ("Sign in", .signIn), required: true,
                      next: stuck ? "Your account didn't load. Check your connection."
                                  : "Sign in so Hear Agent can speak your updates."),
            SetupStep(id: "listening", title: "Hear Agent is running on this Mac", ready: isListening, status: isListening ? "Ready" : (engineError ?? "Stopped"),
                      action: isListening ? nil : ("Retry", .retry), required: true, next: "Hear Agent can't listen for your agents yet."),
        ]
        for agent in Self.agents {
            let on = hookStatus[agent] ?? false
            steps.append(SetupStep(id: agent == .claudeCode ? "claude" : "codex", title: agent.displayName, ready: on, status: on ? "Ready" : "Not connected",
                                   action: on ? nil : ("Connect", .connect(agent)), required: false, agent: agent,
                                   next: "Connect Claude Code or Codex so Hear Agent can follow your sessions."))
        }
        let voice: (Bool, String, (String, SetupStep.Action)?, String)
        switch accountState {
        case .active(let remaining, _, _) where muted:
            voice = (false, "Muted · \(Format.number(remaining)) credits", ("Unmute", .unmute), "Spoken updates are muted.")
        case .active(let remaining, _, _):
            voice = (true, "\(Format.number(remaining)) credits", nil, "")
        case .creditsExhausted(let end):
            voice = (false, "Credits used up", nil, "This month's voice credits are used up\(AppModel.renewalSuffix(end)).")
        case .noSubscription:
            voice = (false, "No plan yet", ("Choose a plan", .subscribe), "Choose a plan to turn on the voice.")
        case .offline:
            voice = (false, "Offline", nil, "Hear Agent can't reach its server. Check your connection.")
        case .signedOut:
            voice = (false, "Sign in first", nil, "Sign in so Hear Agent can speak your updates.")
        }
        steps.append(SetupStep(id: "voice", title: "Hear Agent can talk", ready: voice.0, status: voice.1, action: voice.2, required: true, next: voice.3))
        return steps
    }

    /// Ready means signed in, listening, one agent connected and a voice to speak with.
    var isFullySetUp: Bool {
        setupSteps.filter(\.required).allSatisfy(\.ready) && anyHooksInstalled
    }

    func perform(_ action: SetupStep.Action) {
        switch action {
        case .signIn: signIn(with: .google)
        case .reloadAccount: refreshAccount()
        case .retry: refreshHookStatus()
        case .connect(let agent): setHooks(agent, enabled: true)
        case .subscribe: openCheckout()
        case .unmute: muted = false
        }
    }
}

// MARK: Banner

/// "Finish setting up Hear Agent" with progress and the next step, or "Everything is in place."
/// with a test button. Pale blue, with an ASCII field drawn behind the empty middle.
struct StatusBanner: View {
    @Bindable var model: AppModel
    @State private var sent = false

    // The theme's banner colors: progress and action, ink, and the ground the ASCII field sits on.
    static var blue: Color { Theme.palette.bannerProgress }
    static var navy: Color { Theme.palette.bannerInk }
    static var ground: Color { Theme.palette.bannerGround }

    var body: some View {
        let steps = model.setupSteps
        let ready = model.isFullySetUp
        // Progress counts what's required: sign-in, the listener, the voice, and one connected agent.
        let units = steps.filter(\.required).map(\.ready) + [model.anyHooksInstalled]
        let done = units.filter { $0 }.count
        let next = steps.first { !$0.ready && $0.required } ?? (model.anyHooksInstalled ? nil : steps.first { $0.agent == .claudeCode })

        HStack(spacing: 16) {
            badge(ready: ready, fraction: Double(done) / Double(units.count))
            VStack(alignment: .leading, spacing: 4) {
                Text(ready ? "Everything is in place." : "Finish setting up Hear Agent")
                    .font(.system(size: 18, weight: .semibold)).kerning(-0.2)
                    .foregroundStyle(Self.navy)
                Text(ready ? "Hear Agent will speak up when an agent finishes or needs you." : (next?.next ?? "A couple of things are left."))
                    .font(.system(size: 13.5)).foregroundStyle(Self.navy.opacity(0.68))
                    .lineLimit(1)
                if !ready {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            ForEach(0..<units.count, id: \.self) { i in
                                Capsule().fill(i < done ? Self.blue : Theme.palette.bannerTrack).frame(width: 22, height: 4)
                            }
                        }
                        Text("\(done) of \(units.count) done")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(Self.navy.opacity(0.55))
                    }
                    .padding(.top, 4)
                }
            }
            // A scrim behind the words, so a long line never sits on the ASCII field.
            .padding(.trailing, 40)
            .background {
                HStack(spacing: 0) {
                    Self.ground
                    LinearGradient(colors: [Self.ground, Self.ground.opacity(0)], startPoint: .leading, endPoint: .trailing).frame(width: 40)
                }
                .padding(.vertical, -18)
            }
            .layoutPriority(1)
            Spacer(minLength: 16)
            if ready {
                Button {
                    model.sendTestUpdate()
                    withAnimation(Theme.ease) { sent = true }
                    Task { try? await Task.sleep(for: .seconds(5)); withAnimation(Theme.ease) { sent = false } }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: sent ? "waveform" : "play.fill").font(.system(size: 11, weight: .bold))
                            .contentTransition(.symbolEffect(.replace))
                        Text(sent ? "Listen…" : "Send a test update")
                    }
                    .fixedSize()
                }
                .buttonStyle(PrimaryButtonStyle(color: Self.navy, height: 36))
                .disabled(sent)
            } else if let next, let action = next.action {
                Button(action.label) { model.perform(action.kind) }
                    .buttonStyle(PrimaryButtonStyle(color: Self.navy, height: 36))
                    .fixedSize()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background {
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Self.ground)
                .overlay(AsciiField(tint: Theme.palette.bannerGlyph).clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)))
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.palette.bannerBorder))
    }

    private func badge(ready: Bool, fraction: Double) -> some View {
        ZStack {
            if ready {
                Circle().fill(Self.blue)
                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            } else {
                Circle().fill(.white)
                ProgressRing(fraction: fraction, lineWidth: 3.5, color: Self.blue).padding(3)
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Self.blue)
            }
        }
        .frame(width: 42, height: 42)
    }
}

/// A field of monospaced characters in rolling dunes, masked to the banner's middle so it never
/// sits under the words or the button.
struct AsciiField: View {
    var tint: Color

    private static let ramp = Array(" .·:-=+*#%")

    var body: some View {
        Canvas(rendersAsynchronously: true) { ctx, size in
            let cell = CGSize(width: 7, height: 11)
            let font = Font.system(size: 10, weight: .medium, design: .monospaced)
            let glyphs = Self.ramp.enumerated().map { i, c in
                ctx.resolve(Text(String(c)).font(font).foregroundColor(tint.opacity(0.18 + 0.5 * Double(i) / Double(Self.ramp.count - 1))))
            }
            let cols = Int(size.width / cell.width) + 1
            let rows = Int(size.height / cell.height) + 1
            for row in 0..<rows {
                for col in 0..<cols {
                    let u = Double(col) * cell.width / max(size.width, 1)
                    let v = Double(row) * cell.height / max(size.height, 1)
                    // Dunes: rows bend with a slow wave, crests are densest.
                    let crest = sin(u * 26 + sin(v * 2.6 + u * 5) * 2.2) * cos(v * 6.5 - u * 4)
                    let density = pow(0.5 + 0.5 * crest, 1.35)
                    let level = Int((density * Double(Self.ramp.count - 1)).rounded())
                    guard level > 0 else { continue }
                    ctx.draw(glyphs[min(level, glyphs.count - 1)],
                             at: CGPoint(x: (Double(col) + 0.5) * cell.width, y: (Double(row) + 0.5) * cell.height))
                }
            }
        }
        // Only the middle carries the field; it fades in after the text and out before the button.
        .mask(LinearGradient(stops: [
            .init(color: .clear, location: 0.5), .init(color: .white, location: 0.64),
            .init(color: .white, location: 0.74), .init(color: .clear, location: 0.86),
        ], startPoint: .leading, endPoint: .trailing))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: Checklist

struct SetupChecklist: View {
    @Bindable var model: AppModel

    var body: some View {
        let steps = model.setupSteps
        VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                row(step)
                if i < steps.count - 1 { Divider().overlay(Theme.line).padding(.leading, 50) }
            }
        }
        .padding(.vertical, 4)
        .card(padding: 0)
    }

    private func row(_ step: SetupStep) -> some View {
        HStack(spacing: 12) {
            ZStack {
                if step.ready {
                    Circle().fill(Theme.green)
                    Image(systemName: "checkmark").font(.system(size: 9.5, weight: .heavy)).foregroundStyle(.white)
                } else {
                    Circle().strokeBorder(Theme.faint.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                }
            }
            .frame(width: 20, height: 20)
            .frame(width: 26)
            Text(step.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(1)
            if let agent = step.agent {
                AgentMark(kind: agent, size: 18)
            }
            Spacer(minLength: 12)
            if let action = step.action {
                Text(step.status).font(.system(size: 12.5)).foregroundStyle(Theme.muted).lineLimit(1)
                Button(action.label) { model.perform(action.kind) }
                    .buttonStyle(SoftButtonStyle(height: 28))
                    .fixedSize()
            } else {
                Text(step.status)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(step.ready ? Theme.green : Theme.muted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
    }
}

// MARK: Notch card

/// A product shot of the notch answering a permission prompt, with the shortcuts under it.
struct NotchFeatureCard: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NotchIllustration()
                .frame(height: 196, alignment: .top)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: Theme.radius, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: Theme.radius, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                Text("Answer agents from the notch").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                Text("Hover the top of your screen to see every session. When an agent needs permission, the notch opens on its own and reads it out.")
                    .font(.system(size: 13)).foregroundStyle(Theme.ink2).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    shortcut("⌘Y", "Allow")
                    shortcut("⇧⌘Y", "Always")
                    shortcut("⌘N", "Deny")
                }
                .padding(.top, 4)
                Button { model.peekNotch() } label: {
                    HStack(spacing: 6) { Text("Show me"); Image(systemName: "arrow.up.right").font(.system(size: 10.5, weight: .bold)) }
                        .fixedSize()
                }
                .buttonStyle(PrimaryButtonStyle(height: 32))
                .padding(.top, 8)
                .disabled(!model.preferences.notchEnabled)
                .help(model.preferences.notchEnabled ? "Opens the notch for a few seconds" : "Turn the notch on in Settings")
            }
            .padding(18)
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .shadow(color: .black.opacity(0.035), radius: 10, y: 3)
    }

    private func shortcut(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Kbd(text: keys)
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
        }
    }
}

/// The top of a screen: a quiet menu bar, and the notch hanging from it with a permission request open.
/// Real words only on the request; the menu bar is filler.
struct NotchIllustration: View {
    var body: some View {
        ZStack(alignment: .top) {
            Theme.palette.wallpaper
            terminal
                .padding(.top, 128)
                .padding(.horizontal, 36)
            menuBar
            notch
        }
    }

    /// A terminal window behind the notch, running off the bottom edge.
    private var terminal: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach([Color(hex: 0xEC6A5E), Color(hex: 0xF4BF4F), Color(hex: 0x61C554)], id: \.self) { Circle().fill($0).frame(width: 8, height: 8) }
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 22)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text("›").foregroundStyle(Theme.orange)
                    Text("migrate billing to usage-based plans").foregroundStyle(Theme.ink2)
                }
                .font(.system(size: 10.5, design: .monospaced))
                ForEach([150.0, 210], id: \.self) { w in
                    Capsule().fill(Theme.ink.opacity(0.1)).frame(width: w, height: 5)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160, alignment: .top)
        .background(Color.white, in: UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 2)
    }

    private var menuBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "apple.logo").font(.system(size: 10.5)).foregroundStyle(Theme.ink.opacity(0.55))
            ForEach([34.0, 26, 30, 22], id: \.self) { w in
                Capsule().fill(Theme.ink.opacity(0.16)).frame(width: w, height: 5)
            }
            Spacer()
            ForEach([14.0, 14, 40], id: \.self) { w in
                Capsule().fill(Theme.ink.opacity(0.16)).frame(width: w, height: 5)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 24)
        .background(Color.white.opacity(0.45))
    }

    private var notch: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AgentMark(kind: .codex, size: 20)
                Text("Migrate billing").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Text("Needs you").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.orange)
            }
            Text("pnpm prisma migrate deploy")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.92))
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(spacing: 6) {
                pill("Deny", "⌘N", Color(hex: 0xB9483F))
                pill("Allow", "⌘Y", Color(hex: 0x3E8E5A))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 26)
        .padding(.bottom, 14)
        .frame(width: 300)
        .background(Color.black, in: UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 22, bottomTrailingRadius: 22, topTrailingRadius: 0, style: .continuous))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 22, bottomTrailingRadius: 22, topTrailingRadius: 0, style: .continuous)
                .strokeBorder(Color(hex: 0xE45A12).opacity(0.55), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
    }

    private func pill(_ title: String, _ keys: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Text(title).font(.system(size: 12, weight: .bold))
            Text(keys).font(.system(size: 10.5, weight: .semibold)).opacity(0.7)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 28)
        .background(color, in: Capsule())
    }
}

/// The longest phrasing that fits on one line; the last one truncates if nothing fits.
struct FitText: View {
    let options: [String]
    init(_ options: String...) { self.options = options }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, text in
                if i == options.count - 1 {
                    Text(text).lineLimit(1)
                } else {
                    Text(text).lineLimit(1).fixedSize()
                }
            }
        }
        .layoutPriority(1)
    }
}
