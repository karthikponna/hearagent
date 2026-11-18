import SwiftUI

enum DashboardPage: String, CaseIterable, Identifiable {
    case overview, usage, sessions, board, voice, agents, servers, actions, routes, settings, account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .usage: "Usage"
        case .sessions: "Sessions"
        case .board: "Board"
        case .voice: "Spoken updates"
        case .agents: "Agents"
        case .servers: "Servers"
        case .actions: "Actions"
        case .routes: "Routes"
        case .settings: "Settings"
        case .account: "Account"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "Here's how your agents are doing."
        case .usage: "Track spend and catch limits before you hit them."
        case .sessions: "Every agent session on this Mac, newest first."
        case .board: "Sessions grouped by status."
        case .voice: "What you hear, and when you hear it."
        case .agents: "The coding agents Hear Agent listens to."
        case .servers: "Local dev servers listening on this Mac."
        case .actions: "Saved shell commands, one click away."
        case .routes: "Jump to each agent's skills, rules and config."
        case .settings: "Notch, limits and how Hear Agent behaves."
        case .account: "Your plan, credits and sign-in."
        }
    }

    var symbol: String {
        switch self {
        case .overview: "house"
        case .usage: "chart.bar.xaxis"
        case .sessions: "list.bullet.rectangle"
        case .board: "rectangle.split.3x1"
        case .voice: "waveform"
        case .agents: "point.3.connected.trianglepath.dotted"
        case .servers: "server.rack"
        case .actions: "bolt"
        case .routes: "folder"
        case .settings: "gearshape"
        case .account: "person.crop.circle"
        }
    }

    static let groups: [(String, [DashboardPage])] = [
        ("Analytics", [.overview, .usage, .sessions]),
        ("Planning", [.board]),
        ("Voice", [.voice, .agents]),
        ("Workspace", [.servers, .actions, .routes]),
    ]
}

struct DashboardView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model)
                .frame(width: 214)
            Divider().overlay(Theme.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageHeader(model: model)
                    page
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.canvas)
        }
        .frame(minWidth: 1080, minHeight: 700)
        .background(Theme.canvas)
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private var page: some View {
        switch model.page {
        case .overview: OverviewPage(model: model)
        case .usage: UsagePage(model: model)
        case .sessions: SessionsPage(model: model)
        case .board: BoardPage(model: model)
        case .voice: VoicePage(model: model)
        case .agents: AgentsPage(model: model)
        case .servers: ServersPage(model: model)
        case .actions: ActionsPage(model: model)
        case .routes: RoutesPage()
        case .settings: SettingsPage(model: model)
        case .account: AccountPage(model: model)
        }
    }
}

private struct Sidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                BrandMark(size: 26)
                Text("Hear Agent").font(.system(size: 16, weight: .bold))
            }
            .padding(.horizontal, 18)
            .padding(.top, 34)
            .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(DashboardPage.groups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            SectionLabel(text: group.0).padding(.horizontal, 10).padding(.bottom, 4)
                            ForEach(group.1) { page in
                                SidebarItem(page: page, selected: model.page == page, badge: badge(for: page)) {
                                    model.page = page
                                }
                            }
                        }
                    }
                    SidebarItem(page: .settings, selected: model.page == .settings, badge: nil) { model.page = .settings }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 0)
            UserChip(model: model)
                .padding(10)
        }
        .background(Theme.sidebar)
    }

    private func badge(for page: DashboardPage) -> String? {
        switch page {
        case .sessions, .board:
            let n = model.needsAttention.count
            return n > 0 ? "\(n)" : nil
        case .servers:
            return model.servers.servers.isEmpty ? nil : "\(model.servers.servers.count)"
        default:
            return nil
        }
    }
}

private struct SidebarItem: View {
    let page: DashboardPage
    let selected: Bool
    let badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: page.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(selected ? .white : Theme.muted)
                    .background(selected ? Theme.ink : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(page.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.ink : Theme.muted)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.ink, in: Capsule())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(selected ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .shadow(color: selected ? .black.opacity(0.06) : .clear, radius: 2, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct UserChip: View {
    @Bindable var model: AppModel

    var body: some View {
        Button { model.page = .account } label: {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    Circle().fill(Theme.ink.opacity(0.08)).frame(width: 32, height: 32)
                        .overlay(Text(initials).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink))
                    Circle().fill(statusColor).frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.account?.name.isEmpty == false ? model.account!.name : (model.account?.email ?? "Not signed in"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(Host.current().localizedName ?? "This Mac")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "ellipsis").foregroundStyle(Theme.faint)
            }
            .padding(10)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
        }
        .buttonStyle(.plain)
    }

    private var initials: String {
        let source = model.account?.name.isEmpty == false ? model.account!.name : (model.account?.email ?? "?")
        let parts = source.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }

    private var statusColor: Color {
        switch model.accountState {
        case .active: Theme.success
        case .creditsExhausted, .noSubscription: Theme.warning
        case .offline: Theme.danger
        case .signedOut: Theme.faint
        }
    }
}

private struct PageHeader: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(model.page.title).font(.pageTitle).foregroundStyle(Theme.ink)
                    Text(Format.todayChip)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.line))
                }
                Text(model.page.subtitle).font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            Spacer()
            HStack(spacing: 8) {
                if model.usage.isLoading {
                    ProgressView().controlSize(.small)
                }
                Button {
                    model.usage.refresh()
                    model.servers.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SoftButtonStyle())
                Button {
                    model.muted.toggle()
                } label: {
                    Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(SoftButtonStyle())
                .help(model.muted ? "Unmute spoken updates" : "Mute spoken updates")
            }
        }
    }
}

/// The Hear Agent mark: a sound wave inside a rounded square.
struct BrandMark: View {
    var size: CGFloat = 24
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(LinearGradient(colors: [Theme.accent, Color(red: 0.62, green: 0.38, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(Image(systemName: "waveform").font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(.white))
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.ink
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
