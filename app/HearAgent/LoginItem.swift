import ServiceManagement

/// Launch at login via the system's login items.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// `Hear Agent --login-item on|off|status` for scripted setup; prints the result and exits.
    static func handleCommandLine() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--login-item") else { return }
        let action = i + 1 < args.count ? args[i + 1] : "status"
        do {
            switch action {
            case "on": try set(enabled: true)
            case "off": try set(enabled: false)
            default: break
            }
            print("login item: \(describe(SMAppService.mainApp.status))")
            exit(0)
        } catch {
            print("login item error: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: "enabled"
        case .notRegistered: "not registered"
        case .requiresApproval: "requires approval in System Settings > General > Login Items"
        case .notFound: "not found"
        @unknown default: "unknown"
        }
    }

    static func set(enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
