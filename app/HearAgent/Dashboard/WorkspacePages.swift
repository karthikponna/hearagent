import SwiftUI

struct ServersPage: View {
    @Bindable var model: AppModel
    private let columns = [GridItem(.adaptive(minimum: 250), spacing: 14)]

    var body: some View {
        let servers = model.servers.servers
        VStack(alignment: .leading, spacing: 14) {
            if servers.isEmpty {
                EmptyState(icon: "server.rack", title: "No dev servers running", message: "Start one (npm run dev, vite, uvicorn…) and it appears here within a few seconds.")
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(servers, id: \.pid) { server in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(server.framework).font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Text(Format.duration(server.uptimeSeconds)).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted)
                                    .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.canvas, in: Capsule())
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(":\(String(server.port))").font(.system(size: 26, weight: .bold, design: .monospaced))
                                Text(server.process).font(.system(size: 11)).foregroundStyle(Theme.muted)
                            }
                            Label(server.cwd.isEmpty ? "—" : (server.cwd as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
                                .font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                            HStack(spacing: 6) {
                                Button { model.servers.open(server) } label: { Label("Open", systemImage: "safari") }.buttonStyle(SoftButtonStyle())
                                Button { model.servers.reveal(server) } label: { Label("Folder", systemImage: "folder") }.buttonStyle(SoftButtonStyle())
                                Spacer()
                                Button { model.servers.stop(server) } label: { Label("Stop", systemImage: "stop.fill") }.buttonStyle(SoftButtonStyle())
                            }
                        }
                        .card()
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

struct ActionsPage: View {
    @Bindable var model: AppModel
    @State private var name = ""
    @State private var command = ""
    @State private var directory = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TextField("Action name", text: $name).textFieldStyle(.roundedBorder)
                TextField("Command (e.g. pnpm dev)", text: $command).textFieldStyle(.roundedBorder).font(.mono)
                TextField("Directory (optional)", text: $directory).textFieldStyle(.roundedBorder)
                Button { pickFolder() } label: { Image(systemName: "folder") }.buttonStyle(SoftButtonStyle())
                Button("Add") {
                    model.actions.add(name: name, command: command, directory: directory)
                    name = ""; command = ""; directory = ""
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .card()

            if model.actions.actions.isEmpty {
                EmptyState(icon: "bolt", title: "No actions yet", message: "Save the commands you run all day, like “Run tests” or “Deploy preview”, and start them from here or the notch.")
            } else {
                VStack(spacing: 0) {
                    ForEach(model.actions.actions) { action in
                        HStack(spacing: 12) {
                            Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundStyle(Theme.warning)
                                .frame(width: 26, height: 26).background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.name).font(.system(size: 13, weight: .semibold))
                                Text("> \(action.command)").font(.mono).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer()
                            if !action.directory.isEmpty {
                                Text((action.directory as NSString).abbreviatingWithTildeInPath).font(.system(size: 11)).foregroundStyle(Theme.faint).lineLimit(1)
                            }
                            Button { model.actions.run(action) } label: { Label("Run", systemImage: "play.fill") }.buttonStyle(PrimaryButtonStyle())
                            Button { model.actions.remove(action) } label: { Image(systemName: "trash") }.buttonStyle(SoftButtonStyle())
                        }
                        .padding(.vertical, 10)
                        Divider()
                    }
                }
                .card()
            }
            if let error = model.actions.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(Theme.warning)
            }
            Text("Actions open in Terminal. macOS asks once for permission to control Terminal.")
                .font(.system(size: 11)).foregroundStyle(Theme.faint)
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { directory = url.path }
    }
}

struct RoutesPage: View {
    @State private var agents = AgentRoutes.all()

    var body: some View {
        VStack(spacing: 14) {
            ForEach(agents) { agent in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 5).fill(agent.color).frame(width: 20, height: 20)
                            .overlay(Image(systemName: agent.symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
                        Text(agent.name).font(.system(size: 14, weight: .bold))
                        Spacer()
                        Text("\(agent.mcpServers) MCP servers").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Theme.canvas, in: Capsule())
                    }
                    HStack(spacing: 10) {
                        ForEach(agent.routes) { route in
                            let exists = route.exists
                            Button { agent.open(route) } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: route.symbol).font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(exists ? agent.color : Theme.faint)
                                        .frame(width: 36, height: 36)
                                        .background((exists ? agent.color : Theme.faint).opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                                    Text(route.name).font(.system(size: 11, weight: .medium)).foregroundStyle(exists ? Theme.ink : Theme.faint)
                                    Text(exists ? route.path : "Not created").font(.system(size: 9)).foregroundStyle(Theme.faint).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!exists)
                        }
                    }
                }
                .card()
            }
        }
        .onAppear { agents = AgentRoutes.all() }
    }
}
