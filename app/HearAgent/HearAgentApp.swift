import AppKit
import SwiftUI

@main
struct HearAgentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        #if DEBUG
        if let request = SnapshotRenderer.request() {
            let model = AppModel(preferences: Preferences(defaults: UserDefaults(suiteName: "hearagent-snapshots")!), listen: false)
            _model = State(initialValue: model)
            DispatchQueue.main.async { SnapshotRenderer.renderAll(model: model, request: request) }
            return
        }
        #endif
        LoginItem.handleCommandLine()
        SingleInstance.exitIfAlreadyRunning()
        let model = AppModel()
        _model = State(initialValue: model)
        AppDelegate.model = model
        AppDelegate.openURL = { url in model.handle(url: url) }
    }

    var body: some Scene {
        Window("Hear Agent", id: "dashboard") {
            DashboardView(model: model)
                .background(WindowOpenerCapture())
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1240, height: 800)

        MenuBarExtra(isInserted: Binding(get: { model.preferences.showMenuBarIcon }, set: { model.preferences.showMenuBarIcon = $0 })) {
            MenuBarMenu(model: model)
        } label: {
            Image(systemName: menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarSymbol: String {
        if model.muted { return "speaker.slash" }
        if !model.needsAttention.isEmpty { return "exclamationmark.bubble.fill" }
        return "waveform"
    }
}

/// Remembers SwiftUI's window opener so the notch, Dock icon and menu can reopen the dashboard.
private struct WindowOpenerCapture: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Color.clear.onAppear {
            let open = openWindow
            AppDelegate.showDashboard = {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "dashboard" && $0.isVisible }) {
                    window.makeKeyAndOrderFront(nil)
                } else {
                    open(id: "dashboard")
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var openURL: ((URL) -> Void)?
    @MainActor static var showDashboard: (() -> Void)?
    @MainActor static var model: AppModel?
    @MainActor private var notch: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            guard let model = Self.model else { return }
            let notch = NotchController(model: model)
            notch.start()
            self.notch = notch
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in urls.forEach { Self.openURL?($0) } }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in Self.showDashboard?() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

private struct MenuBarMenu: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                BrandMark(size: 22)
                Text("Hear Agent").font(.headline)
                Spacer()
                Text("\(model.sessions.count) live").font(.caption).foregroundStyle(.secondary)
            }
            if !model.lastSpoken.isEmpty {
                Text(model.lastSpoken).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            Divider()
            Toggle("Mute spoken updates", isOn: $model.muted)
            Button("Open dashboard") { AppDelegate.showDashboard?() }
                .keyboardShortcut("d")
            Button("Quit Hear Agent") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 280)
    }
}

enum SingleInstance {
    /// A second copy would take over the event socket, so defer to the one already running.
    static func exitIfAlreadyRunning() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let other = others.first {
            AppModel.log.info("another Hear Agent is running; exiting")
            other.activate()
            exit(0)
        }
    }
}
