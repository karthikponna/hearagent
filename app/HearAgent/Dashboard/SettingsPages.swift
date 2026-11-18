import SwiftUI

struct SettingsPage: View {
    @Bindable var model: AppModel

    var body: some View {
        @Bindable var prefs = model.preferences
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 16) {
                section("Notch") {
                    toggle("Show Hear Agent in the notch", "A few quiet dots at the top of the screen, with a badge when an agent needs you.", $prefs.notchEnabled)
                    toggle("Expand on hover", "Open the notch panel when the pointer reaches it.", $prefs.notchExpandOnHover)
                    toggle("Open when an agent needs you", "Show the approval for a few seconds, even if you're not hovering.", $prefs.notchOpenOnApproval)
                }
                section("App") {
                    toggle("Show menu bar icon", "Quick mute, open dashboard and quit.", $prefs.showMenuBarIcon)
                    toggle("Open Hear Agent when you log in", "Start listening as soon as your Mac is ready.", Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 16) {
                section("Targets & limits") {
                    field("Monthly budget ($)", value: $prefs.monthlyBudget)
                    intField("Claude 5h token limit (0 = auto)", value: $prefs.claudeFiveHourLimit)
                    intField("Claude weekly token limit (0 = auto)", value: $prefs.claudeWeeklyLimit)
                    field("Limit warning (%)", value: $prefs.limitWarningPercent)
                    Text("Claude limits are estimated from your local transcripts. With 0, your busiest past window counts as 100%. Codex limits come straight from Codex.")
                        .font(.system(size: 11)).foregroundStyle(Theme.faint)
                    Button("Recalculate usage") { model.usage.refresh() }.buttonStyle(SoftButtonStyle())
                }
                section("Privacy") {
                    Text("Usage, sessions and servers are read from files on this Mac and never leave it. Only the short summary sent for speaking goes to Hear Agent's server, and it isn't stored.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Text("Hear Agent \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.system(size: 11)).foregroundStyle(Theme.faint)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 15, weight: .bold))
            content()
        }
        .card(padding: 18)
    }

    private func toggle(_ title: String, _ detail: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
        .toggleStyle(.switch)
    }

    private func field(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            TextField("", value: value, format: .number).textFieldStyle(.roundedBorder).frame(width: 130).multilineTextAlignment(.trailing)
        }
    }

    private func intField(_ title: String, value: Binding<Int>) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            TextField("", value: value, format: .number).textFieldStyle(.roundedBorder).frame(width: 130).multilineTextAlignment(.trailing)
        }
    }
}

struct AccountPage: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                if let account = model.account {
                    HStack(spacing: 12) {
                        Circle().fill(Theme.ink.opacity(0.08)).frame(width: 46, height: 46)
                            .overlay(Image(systemName: "person.fill").foregroundStyle(Theme.muted))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.email).font(.system(size: 15, weight: .semibold))
                            Text("Signed in with Google").font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                    }
                    planCard(account)
                    Button(role: .destructive) { model.signOut() } label: { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }
                        .buttonStyle(SoftButtonStyle())
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sign in to Hear Agent").font(.system(size: 18, weight: .bold))
                        Text("Your Google account keeps your plan and voice credits. Your code and transcripts stay on this Mac.")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        Button(model.isSigningIn ? "Waiting for Google…" : "Sign in with Google") { model.signIn() }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(model.isSigningIn)
                    }
                    .card(padding: 20)
                }
                if let error = model.accountError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(Theme.warning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                Text("What's included").font(.system(size: 15, weight: .bold))
                ForEach([
                    ("waveform", "Spoken summaries when agents need approval, finish or stop"),
                    ("sparkles", "Summaries written by AI from what the agent actually did"),
                    ("person.wave.2", "George, a natural ElevenLabs voice"),
                    ("chart.bar", "Usage, limits, sessions and servers for every agent"),
                    ("rectangle.topthird.inset.filled", "The notch, always one hover away"),
                ], id: \.1) { item in
                    Label(item.1, systemImage: item.0).font(.system(size: 12)).foregroundStyle(Theme.ink)
                }
                Text("$19/month · 150,000 voice credits (about 750 summaries)").font(.system(size: 11)).foregroundStyle(Theme.faint).padding(.top, 4)
            }
            .card(padding: 20)
            .frame(width: 360)
        }
    }

    private func planCard(_ account: HearAccount) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YOUR PLAN").font(.system(size: 10, weight: .semibold)).kerning(0.8).foregroundStyle(Theme.ink.opacity(0.6))
                Spacer()
                if let sub = account.subscription {
                    Tag(text: sub.active ? "● Active" : sub.status.capitalized, color: sub.active ? Theme.success : Theme.danger)
                }
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.subscription.map { "Hear Agent · \($0.planName)" } ?? "No plan yet").font(.system(size: 22, weight: .bold))
                    if let sub = account.subscription, sub.active {
                        Text("\(Format.number(sub.creditsRemaining)) of \(Format.number(sub.creditsTotal)) credits left\(AppModel.renewalSuffix(sub.periodEnd))")
                            .font(.system(size: 12)).foregroundStyle(Theme.ink.opacity(0.65))
                    } else {
                        Text("$19/month · 150,000 credits").font(.system(size: 12)).foregroundStyle(Theme.ink.opacity(0.65))
                    }
                }
                Spacer()
                if account.subscription?.active == true {
                    Button("Manage plan") { model.openPortal() }.buttonStyle(PrimaryButtonStyle())
                } else {
                    Button("Subscribe") { model.openCheckout() }.buttonStyle(PrimaryButtonStyle(color: Theme.accent))
                }
            }
            if let sub = account.subscription, sub.active {
                LimitBar(fraction: Double(sub.creditsUsed) / Double(max(sub.creditsTotal, 1)), height: 8, track: .white.opacity(0.6))
            }
        }
        .padding(20)
        .background(
            LinearGradient(colors: [Color(red: 0.86, green: 0.82, blue: 1.0), Color(red: 0.96, green: 0.85, blue: 0.92)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .shadow(color: Theme.accent.opacity(0.15), radius: 12, y: 6)
    }
}
