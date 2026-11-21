import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, notch, notifications, permissions, account, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .notch: "Notch"
        case .notifications: "Notifications"
        case .permissions: "Permissions"
        case .account: "Account"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .notch: "macbook"
        case .notifications: "bell"
        case .permissions: "hand.raised"
        case .account: "person.crop.circle"
        case .about: "info.circle"
        }
    }
}

/// Settings as one sheet: a list of sections on the left, that section's rows on the right.
struct SettingsPage: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsPane.allCases) { pane in
                    navItem(pane)
                }
            }
            .padding(12)
            .frame(width: 200, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .top)

            Rectangle().fill(Theme.line).frame(width: 1)

            VStack(alignment: .leading, spacing: 0) {
                Text(model.settingsPane.title).font(.system(size: 24, weight: .bold)).kerning(-0.5).foregroundStyle(Theme.ink)
                    .padding(.bottom, 20)
                pane
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 26)
            .frame(maxWidth: 680, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minHeight: 540, alignment: .top)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.035), radius: 6, y: 1)
    }

    private func navItem(_ pane: SettingsPane) -> some View {
        let selected = model.settingsPane == pane
        return Button { withAnimation(Theme.ease) { model.settingsPane = pane } } label: {
            HStack(spacing: 10) {
                Image(systemName: pane.symbol).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? Theme.accent : Theme.muted)
                    .frame(width: 18)
                Text(pane.title).font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.ink : Theme.ink2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(selected ? Theme.well : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var pane: some View {
        @Bindable var prefs = model.preferences
        switch model.settingsPane {
        case .general:
            SettingsGroup(caption: "Hear Agent keeps listening for your agents while its window is closed.") {
                SettingsRow("Open Hear Agent when you log in") { Switch(isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 })) }
                SettingsDivider()
                SettingsRow("Show menu bar icon") { Switch(isOn: $prefs.showMenuBarIcon) }
            }
        case .appearance:
            SettingsGroup(caption: "Changes the dashboard's colors. The notch always stays black.") {
                ThemePicker(prefs: model.preferences).padding(12)
            }
        case .notch:
            SettingsGroup(caption: "The notch shows live sessions, usage and servers when you move the pointer to the top of the screen.") {
                SettingsRow("Show Hear Agent in the notch") { Switch(isOn: $prefs.notchEnabled) }
                SettingsDivider()
                SettingsRow("Expand on hover") { Switch(isOn: $prefs.notchExpandOnHover) }
                SettingsDivider()
                SettingsRow("Open when an agent needs permission") { Switch(isOn: $prefs.notchOpenOnApproval) }
            }
        case .notifications:
            SettingsGroup(caption: "Banners from macOS, alongside what the Narrator says out loud.") {
                SettingsRow("When an agent needs permission") { Switch(isOn: $prefs.notifyOnPermission) }
                SettingsDivider()
                SettingsRow("When an agent finishes") { Switch(isOn: $prefs.notifyOnFinish) }
            }
        case .permissions:
            permissions(prefs)
        case .account:
            account
        case .about:
            SettingsGroup(caption: "Usage, sessions and servers are read from files on this Mac and never leave it. Only the short summary sent for speaking goes to Hear Agent's server, and it isn't stored.") {
                SettingsRow("Version") { Value(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") }
                SettingsDivider()
                SettingsRow("This Mac") { Value(Host.current().localizedName ?? "This Mac") }
            }
        }
    }

    // MARK: Permissions

    private func permissions(_ prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(caption: "Off leaves every prompt to the terminal. While the notch is open, ⌘Y allows, ⇧⌘Y always allows and ⌘N denies.") {
                SettingsRow("Answer permission prompts from Hear Agent") { Switch(isOn: $prefs.approveFromNotch) }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Always-allow rules").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.ink)
                SettingsGroup(caption: prefs.allowRules.isEmpty ? nil : "Requests that match a rule are allowed without asking.") {
                    if prefs.allowRules.isEmpty {
                        Text("Choose “Always allow” on a request and its rule shows up here.")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).frame(minHeight: 46)
                    }
                    ForEach(Array(prefs.allowRules.enumerated()), id: \.element.id) { i, rule in
                        if i > 0 { SettingsDivider() }
                        SettingsRow(rule.tool, mono: true) {
                            Text(rule.pattern.isEmpty ? "any" : rule.pattern)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(rule.pattern.isEmpty ? Theme.muted : Theme.ink2).lineLimit(1)
                            Button { model.removeAllowRule(rule) } label: { Image(systemName: "xmark").font(.system(size: 10.5, weight: .semibold)) }
                                .buttonStyle(IconButtonStyle(size: 24))
                                .help("Remove rule")
                        }
                    }
                }
            }
        }
    }

    // MARK: Account

    @ViewBuilder
    private var account: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let account = model.account {
                SettingsGroup(caption: "1 credit = 1 spoken character · $19/month includes 150,000 credits.") {
                    SettingsRow("Email") { Value(account.email) }
                    SettingsDivider()
                    SettingsRow("Plan") {
                        if let sub = account.subscription {
                            Tag(text: sub.active ? "Active" : sub.status.capitalized, color: sub.active ? Theme.green : Theme.red)
                        }
                        Value(account.subscription.map { "Hear Agent \($0.planName)" } ?? "No plan yet")
                    }
                    if let sub = account.subscription, sub.active {
                        SettingsDivider()
                        SettingsRow("Voice credits") { Value("\(Format.number(sub.creditsRemaining)) of \(Format.number(sub.creditsTotal)) left") }
                        if let refill = Self.date(sub.periodEnd) {
                            SettingsDivider()
                            SettingsRow("Credits refill") { Value(refill.formatted(date: .abbreviated, time: .omitted)) }
                        }
                        if let end = Self.date(sub.renewsAt) {
                            SettingsDivider()
                            SettingsRow(sub.cancelAtPeriodEnd ? "Ends" : "Renews") { Value(end.formatted(date: .abbreviated, time: .omitted)) }
                        } else if sub.planId == "lifetime" {
                            SettingsDivider()
                            SettingsRow("Renews") { Value("Never · lifetime") }
                        }
                    }
                }
                HStack(spacing: 8) {
                    if account.subscription?.active == true {
                        Button("Manage plan") { model.openPortal() }.buttonStyle(PrimaryButtonStyle(height: 32))
                    } else {
                        Button("Subscribe") { model.openCheckout() }.buttonStyle(PrimaryButtonStyle(height: 32))
                    }
                    Button("Sign out") { model.signOut() }.buttonStyle(SoftButtonStyle(height: 32))
                }
            } else if model.hasSession {
                SettingsGroup(caption: nil) {
                    Text("You're signed in, but your account didn't load from Hear Agent's server.")
                        .font(.system(size: 13)).foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                HStack(spacing: 8) {
                    Button("Retry") { model.refreshAccount() }.buttonStyle(PrimaryButtonStyle(height: 32))
                    Button("Sign out") { model.signOut() }.buttonStyle(SoftButtonStyle(height: 32))
                }
            } else {
                SettingsGroup(caption: nil) {
                    Text("Your account keeps your plan and voice credits. Your code and transcripts stay on this Mac.")
                        .font(.system(size: 13)).foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                if model.isSigningIn {
                    Text("Finish signing in in your browser…").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                } else {
                    HStack(spacing: 8) {
                        Button { model.signIn(with: .apple) } label: {
                            HStack(spacing: 6) { Image(systemName: "apple.logo"); Text("Sign in with Apple") }
                        }
                        .buttonStyle(PrimaryButtonStyle(height: 32))
                        Button("Sign in with Google") { model.signIn(with: .google) }.buttonStyle(SoftButtonStyle(height: 32))
                    }
                }
            }
            if let error = model.accountError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(Theme.orange)
            }
        }
    }

    private static func date(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }
}

// MARK: Rows

/// Rows on a soft gray plate, with an optional note under it.
private struct SettingsGroup<Content: View>: View {
    let caption: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) { content() }
                .frame(maxWidth: .infinity)
                .background(Theme.well.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if let caption {
                Text(caption).font(.system(size: 12)).foregroundStyle(Theme.faint)
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    var mono = false
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, mono: Bool = false, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.mono = mono
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(mono ? .system(size: 13, weight: .medium, design: .monospaced) : .system(size: 13.5, weight: .medium))
                .foregroundStyle(Theme.ink).lineLimit(1)
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
    }
}

private struct SettingsDivider: View {
    var body: some View { Rectangle().fill(Theme.card).frame(height: 1.5) }
}

private struct Switch: View {
    @Binding var isOn: Bool
    var body: some View {
        Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(Theme.palette.toggle)
    }
}

private struct Value: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 13.5)).foregroundStyle(Theme.ink2).lineLimit(1).truncationMode(.middle)
    }
}

// MARK: Appearance

/// The three dashboard themes, each shown as a small copy of the dashboard in its own colors.
struct ThemePicker: View {
    @Bindable var prefs: Preferences

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Appearance.allCases) { option in
                Button { withAnimation(Theme.ease) { prefs.appearance = option } } label: {
                    tile(option, selected: prefs.appearance == option)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tile(_ option: Appearance, selected: Bool) -> some View {
        let p = option.palette
        return VStack(alignment: .leading, spacing: 10) {
            ThemeThumbnail(palette: p)
                .frame(height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(0.06)))
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text(option.blurb).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                ZStack {
                    Circle().strokeBorder(selected ? p.accent : Theme.line, lineWidth: selected ? 0 : 1.5)
                    if selected {
                        Circle().fill(p.accent)
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                    }
                }
                .frame(width: 20, height: 20)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(selected ? p.accent : Theme.line, lineWidth: selected ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A miniature dashboard in one palette: sidebar with the selected item, the panel, the setup
/// banner, two cards and the primary button. Bars stand in for words.
struct ThemeThumbnail: View {
    let palette: ThemePalette

    var body: some View {
        let p = palette
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Capsule().fill(p.ink).frame(width: 30, height: 5).padding(.bottom, 4)
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3).fill(p.accent).frame(width: 10, height: 10)
                    Capsule().fill(p.accent).frame(width: 24, height: 4)
                }
                .padding(4)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 5))
                ForEach([28.0, 22, 30, 18], id: \.self) { w in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3).fill(p.ink2.opacity(0.25)).frame(width: 10, height: 10)
                        Capsule().fill(p.ink2.opacity(0.25)).frame(width: w, height: 4)
                    }
                    .padding(.horizontal, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
            .padding(.top, 10)
            .frame(width: 66, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(p.ink).frame(width: 62, height: 6)
                HStack(spacing: 5) {
                    Circle().strokeBorder(p.bannerProgress, lineWidth: 1.5).frame(width: 11, height: 11)
                    VStack(alignment: .leading, spacing: 3) {
                        Capsule().fill(p.bannerInk).frame(width: 46, height: 4)
                        Capsule().fill(p.bannerInk.opacity(0.35)).frame(width: 34, height: 3)
                    }
                    Spacer(minLength: 0)
                    Text(":+*#").font(.system(size: 6, weight: .bold, design: .monospaced)).foregroundStyle(p.bannerGlyph)
                    Capsule().fill(p.bannerInk).frame(width: 18, height: 8)
                }
                .padding(.horizontal, 6)
                .frame(height: 22)
                .background(p.bannerGround, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(p.bannerBorder, lineWidth: 0.5))
                HStack(spacing: 5) {
                    miniCard(p, highlight: false)
                    miniCard(p, highlight: true)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(p.panel, in: UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8, bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous))
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .background(p.window)
    }

    private func miniCard(_ p: ThemePalette, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(p.ink2.opacity(0.35)).frame(width: 26, height: 3)
            Canvas { ctx, size in
                let ys: [CGFloat] = highlight ? [0.8, 0.62, 0.68, 0.4, 0.46, 0.15] : [0.7, 0.5, 0.75, 0.35, 0.55, 0.3]
                var line = Path()
                for (i, y) in ys.enumerated() {
                    let pt = CGPoint(x: size.width * CGFloat(i) / CGFloat(ys.count - 1), y: size.height * y)
                    if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
                }
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                let color = highlight ? p.spendLine : p.ink2.opacity(0.35)
                ctx.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.18), color.opacity(0)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            }
            .frame(height: 20)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 5))
    }
}
