import SwiftUI

enum DashboardPage: String, CaseIterable, Identifiable {
    case overview, usage, board, voice, servers, routes, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .usage: "Usage"
        case .board: "Board"
        case .voice: "Narrator"
        case .servers: "Servers"
        case .routes: "Routes"
        case .settings: "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "Agents talk. You decide."
        case .usage: "Track spend and catch limits before they hit."
        case .board: "Sessions grouped by status."
        case .voice: "The voice that tells you what your agents did."
        case .servers: "Local dev servers listening on this Mac."
        case .routes: "Jump to agent skills, commands, rules and config."
        case .settings: "How Hear Agent looks, behaves and bills."
        }
    }

    var symbol: String {
        switch self {
        case .overview: "house"
        case .usage: "chart.xyaxis.line"
        case .board: "rectangle.split.3x1"
        case .voice: "waveform"
        case .servers: "server.rack"
        case .routes: "folder"
        case .settings: "gearshape"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .usage, .voice, .servers: symbol
        default: symbol + ".fill"
        }
    }

    static let groups: [(String, [DashboardPage])] = [
        ("Analytics", [.overview, .usage]),
        ("Planning", [.board]),
        ("Voice", [.voice]),
        ("Workspace", [.servers, .routes, .settings]),
    ]
}

struct DashboardView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model)
                .frame(width: 236)
            content
                .clipShape(Self.panelShape)
                // Clip the content, not the surface, so the panel's shadow shows and lifts it off the window.
                .background {
                    Self.panelShape
                        .fill(Theme.panel)
                        .shadow(color: Theme.ink.opacity(0.07), radius: 14, y: 3)
                        .shadow(color: Theme.ink.opacity(0.04), radius: 1.5, y: 0.5)
                }
                .overlay(Self.panelShape.strokeBorder(Theme.palette.panelBorder, lineWidth: 1))
                .padding(.top, 38)
                .padding(.trailing, 10)
                .padding(.bottom, 10)
        }
        .frame(minWidth: 1180, minHeight: 760)
        .background(Theme.window)
        .id(model.preferences.appearance)
        .ignoresSafeArea()
        .environment(\.colorScheme, .light)
    }

    static let panelShape = UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 24, bottomTrailingRadius: 14, topTrailingRadius: 14, style: .continuous)

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(model: model)
                page
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 30)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .scrollIndicators(.automatic)
        .id(model.page)
        .transition(.opacity)
    }

    @ViewBuilder
    private var page: some View {
        switch model.page {
        case .overview: OverviewPage(model: model)
        case .usage: UsagePage(model: model)
        case .board: BoardPage(model: model)
        case .voice: VoicePage(model: model)
        case .servers: ServersPage(model: model)
        case .routes: RoutesPage()
        case .settings: SettingsPage(model: model)
        }
    }
}

// MARK: Sidebar

private struct Sidebar: View {
    @Bindable var model: AppModel
    @Namespace private var selection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
                .padding(.horizontal, 22)
                .padding(.top, 54)
                .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(DashboardPage.groups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            SectionLabel(text: group.0).padding(.horizontal, 14).padding(.bottom, 6)
                            ForEach(group.1) { page in
                                SidebarItem(page: page, selected: model.page == page, badge: badge(for: page), namespace: selection) {
                                    withAnimation(Theme.ease) { model.page = page }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)

            UserChip(model: model)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    private func badge(for page: DashboardPage) -> SidebarItem.Badge? {
        switch page {
        case .board:
            let active = model.sessions.filter { $0.status == .working || $0.status == .needsYou }.count
            return model.sessions.isEmpty ? nil : .text("\(active)/\(model.sessions.count)")
        case .servers:
            return model.servers.servers.isEmpty ? nil : .text("\(model.servers.servers.count)")
        default:
            return nil
        }
    }
}

/// "Hear Agent." in the sidebar.
struct Wordmark: View {
    var size: CGFloat = 21
    var body: some View {
        (Text("Hear Agent").foregroundStyle(Theme.ink) + Text(".").foregroundStyle(Theme.faint))
            .font(.system(size: size, weight: .bold))
            .kerning(-0.4)
    }
}

private struct SidebarItem: View {
    enum Badge { case count(Int), text(String) }

    let page: DashboardPage
    let selected: Bool
    let badge: Badge?
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    if selected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent)
                            .matchedGeometryEffect(id: "icon", in: namespace)
                    }
                    Image(systemName: selected ? page.selectedSymbol : page.symbol)
                        .font(.system(size: 14, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.white : Theme.ink2)
                }
                .frame(width: 30, height: 30)
                Text(page.title)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.accent : Theme.ink2)
                Spacer(minLength: 4)
                if let badge { badgeView(badge) }
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .frame(height: 42)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Theme.card)
                        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.ink.opacity(0.045))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder
    private func badgeView(_ badge: Badge) -> some View {
        switch badge {
        case .count(let n):
            Text("\(n)")
                .font(.system(size: 11.5, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(minWidth: 21, minHeight: 21)
                .background(Theme.ink, in: Circle())
        case .text(let t):
            Text(t)
                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, selected ? 8 : 0)
                .frame(height: 22)
                .background(selected ? Theme.well : .clear, in: Capsule())
        }
    }
}

private struct UserChip: View {
    @Bindable var model: AppModel

    var body: some View {
        Menu {
            Button("Account and plan") { withAnimation(Theme.ease) { model.settingsPane = .account; model.page = .settings } }
            if model.account != nil {
                Divider()
                Button("Sign out") { model.signOut() }
            } else {
                Button("Sign in with Apple") { model.signIn(with: .apple) }
                Button("Sign in with Google") { model.signIn(with: .google) }
            }
        } label: {
            HStack(spacing: 11) {
                avatar
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.black.opacity(0.06), lineWidth: 0.5))
                    .overlay(alignment: .bottomLeading) {
                        Circle().fill(statusColor).frame(width: 11, height: 11)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .offset(x: 27, y: 1)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(Host.current().localizedName ?? "This Mac").font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink2)
            }
            .padding(10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    /// The provider's profile photo when there is one, otherwise initials on a tile.
    private var avatar: some View {
        AsyncImage(url: model.avatarURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.track)
            }
        }
    }

    private var name: String {
        if let a = model.account { return a.name.isEmpty ? a.email : a.name }
        return model.hasSession ? "Signed in" : "Not signed in"
    }

    private var initials: String {
        guard let a = model.account else { return "?" }
        let source = a.name.isEmpty ? a.email : a.name
        return source.split(separator: " ").prefix(2).map { String($0.prefix(1)).uppercased() }.joined()
    }

    private var statusColor: Color {
        switch model.accountState {
        case .active: Theme.green
        case .creditsExhausted, .noSubscription: Theme.amber
        case .offline: Theme.red
        case .signedOut: Theme.faint
        }
    }
}

// MARK: Header

private struct PageHeader: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                if model.page == .overview {
                    // Re-evaluated every minute, so the greeting turns over on its own.
                    TimelineView(.everyMinute) { context in
                        Text(Greeting.title(for: model.account, at: context.date)).font(.pageTitle).kerning(-0.6).foregroundStyle(Theme.ink)
                    }
                } else {
                    Text(model.page.title).font(.pageTitle).kerning(-0.6).foregroundStyle(Theme.ink)
                }
                Text(model.page == .overview ? overviewSubtitle : model.page.subtitle).font(.system(size: 14)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 16)
            HStack(spacing: 10) {
                if model.usage.isLoading { ProgressView().controlSize(.small).padding(.trailing, 2) }
                trailing
            }
            .padding(.top, 2)
        }
    }

    /// What's happening right now, or the tagline when nothing is running.
    private var overviewSubtitle: String {
        let working = model.sessions.filter { $0.status == .working }.count
        let waiting = model.needsAttention.count
        var parts: [String] = []
        if working > 0 { parts.append(working == 1 ? "1 agent working" : "\(working) agents working") }
        if waiting > 0 { parts.append(waiting == 1 ? "1 needs you" : "\(waiting) need you") }
        return parts.isEmpty ? model.page.subtitle : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var trailing: some View {
        switch model.page {
        case .usage:
            RangePicker(options: UsageRange.allCases, selection: $model.usageRange, custom: $model.usageCustom) { $0.rawValue }
        default:
            EmptyView()
        }
    }
}

/// The Hear Agent mark used in the menu bar menu.
struct BrandMark: View {
    var size: CGFloat = 24
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Theme.ink)
            .frame(width: size, height: size)
            .overlay(Image(systemName: "waveform").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white))
    }
}
