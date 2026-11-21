import SwiftUI

// MARK: Servers

struct ServersPage: View {
    @Bindable var model: AppModel
    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 16)]

    var body: some View {
        let servers = model.servers.servers
        VStack(alignment: .leading, spacing: 14) {
            if servers.isEmpty {
                EmptyState(icon: "server.rack", title: "No dev servers running", message: "Start one (npm run dev, vite, uvicorn…) and it appears here within a few seconds.")
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(servers, id: \.pid) { server in
                        ServerCard(model: model, server: server)
                    }
                }
            }
        }
        .onAppear { model.servers.refresh() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                model.servers.refresh()
            }
        }
    }
}

private struct ServerCard: View {
    @Bindable var model: AppModel
    let server: HearDevServer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 8)
                Tag(text: Format.duration(server.uptimeSeconds))
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(":\(String(server.port))").font(.system(size: 34, weight: .medium, design: .monospaced)).kerning(-1).foregroundStyle(Theme.ink)
                Text(server.process).font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            .padding(.top, 14)
            HStack(spacing: 7) {
                Image(systemName: "folder").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                Text(server.cwd.isEmpty ? "—" : Format.path(server.cwd))
                    .font(.system(size: 13)).foregroundStyle(Theme.ink2).lineLimit(1).truncationMode(.head)
            }
            .help(server.cwd)
            .padding(.top, 6)
            HStack(spacing: 8) {
                action("Open", "safari") { model.servers.open(server) }
                action("Folder", "folder") { model.servers.reveal(server) }
                Spacer(minLength: 8)
                action("Stop", "stop.fill") { model.servers.stop(server) }
            }
            .padding(.top, 16)
        }
        .card()
    }

    /// Generic runtimes say little on their own, so those cards are named after the project folder.
    private var title: String {
        let generic = ["node", "bun", "deno", "python", "python3", "ruby", "java", "php", "go"]
        guard generic.contains(server.framework.lowercased()), !server.cwd.isEmpty else { return server.framework }
        return (server.cwd as NSString).lastPathComponent
    }

    private func action(_ title: String, _ symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title).lineLimit(1)
            }
            .fixedSize()
        }
        .buttonStyle(SoftButtonStyle(height: 30))
    }
}

// MARK: Routes

struct RoutesPage: View {
    @State private var agents = AgentRoutes.all()

    var body: some View {
        VStack(spacing: 16) {
            ForEach(agents) { agent in
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        AgentMark(agent.brand, size: 24)
                        Text(agent.name).font(.system(size: 15, weight: .semibold))
                        Spacer()
                    }
                    HStack(spacing: 8) {
                        ForEach(agent.routes) { route in
                            RouteTile(route: route, color: agent.brand == .cursor || agent.brand == .opencode ? Theme.ink2 : agent.brand.color) { agent.open(route) }
                        }
                        if agent.routes.count < 6 {
                            ForEach(0..<(6 - agent.routes.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, minHeight: 1) }
                        }
                    }
                }
                .card()
            }
        }
        .onAppear { agents = AgentRoutes.all() }
    }
}

private struct RouteTile: View {
    let route: AgentRoutes.Route
    let color: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let exists = route.exists
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: route.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(exists ? color : color.opacity(0.35))
                    .frame(width: 44, height: 44)
                    .background(color.opacity(exists ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Text(route.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(exists ? Theme.ink : Theme.faint.opacity(0.7))
                Text(exists ? route.path : "Not created").font(.system(size: 11)).foregroundStyle(Theme.faint.opacity(exists ? 1 : 0.6)).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(hovering && exists ? Theme.well : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!exists)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
