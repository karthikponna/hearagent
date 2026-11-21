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
        if SnapshotRenderer.previewRequested() {
            let model = AppModel(preferences: Preferences(defaults: UserDefaults(suiteName: "hearagent-preview")!), listen: false)
            model.preferences.showMenuBarIcon = false
            SnapshotRenderer.loadPreview(model: model)
            _model = State(initialValue: model)
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
        .defaultSize(width: 1380, height: 880)

        MenuBarExtra(isInserted: Binding(get: { model.preferences.showMenuBarIcon }, set: { model.preferences.showMenuBarIcon = $0 })) {
            MenuBarMenu(model: model)
        } label: {
            Image(systemName: menuBarSymbol)
        }
        .menuBarExtraStyle(.menu)
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
            Updates.showWhatsNewIfUpdated()
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
        @Bindable var prefs = model.preferences
        Button("Open Dashboard") { AppDelegate.showDashboard?() }
            .keyboardShortcut("d")

        Divider()
        if let account = model.account {
            Text("Signed in · \(account.email)")
            if let sub = account.subscription {
                Text("Plan: \(sub.planName)\(sub.active ? "" : " (\(sub.status))")")
                if !sub.active { Button("Renew plan…") { model.openCheckout() } }
            } else {
                Text("Plan: none")
                Button("Choose a plan…") { model.openCheckout() }
            }
        } else {
            Text("Not signed in")
            Button("Sign in…") { open(.account) }
        }

        Divider()
        Text("Hear Agent v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
        Button("Check for Updates…") { Updates.check(apiBaseURL: model.preferences.apiBaseURL) }

        Divider()
        Toggle("Mute Updates", isOn: $model.muted)
        Toggle("Hide Notch", isOn: Binding(get: { !prefs.notchEnabled }, set: { prefs.notchEnabled = !$0 }))

        Divider()
        Button("Settings…") { open(.general) }
            .keyboardShortcut(",")

        Divider()
        Button("Quit Hear Agent") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func open(_ pane: SettingsPane) {
        model.settingsPane = pane
        model.page = .settings
        AppDelegate.showDashboard?()
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
