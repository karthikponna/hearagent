#if DEBUG
import AppKit
import SwiftUI

/// `"Hear Agent" --render-snapshots <dir> [--real]` draws every dashboard page and the
/// notch to PNGs, with sample data (or this Mac's real usage with --real), then exits.
@MainActor
enum SnapshotRenderer {
    struct Request {
        let dir: URL
        let real: Bool
    }

    static func request() -> Request? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-snapshots"), i + 1 < args.count else { return nil }
        return Request(dir: URL(fileURLWithPath: args[i + 1], isDirectory: true), real: args.contains("--real"))
    }

    static func renderAll(model: AppModel, request: Request) {
        try? FileManager.default.createDirectory(at: request.dir, withIntermediateDirectories: true)
        if request.real {
            let offset = Int32(TimeZone.current.secondsFromGMT())
            model.usage.setPreview(usageReport(utcOffsetSeconds: offset, claudeFiveHourLimit: 0, claudeWeeklyLimit: 0))
            model.servers.setPreview(devServers())
            model.setPreview(sessions: [], history: [], hooks: [.claudeCode: hooksInstalled(agent: .claudeCode), .codex: hooksInstalled(agent: .codex)])
        } else {
            model.usage.setPreview(SampleData.usage())
            model.servers.setPreview(SampleData.servers())
            model.actions.setPreview(SampleData.actions())
            model.setPreview(sessions: SampleData.liveSessions(), history: SampleData.history(), hooks: [.claudeCode: true, .codex: true])
            model.setPreview(lastSpoken: SampleData.history()[0].text, account: SampleData.account,
                             state: .active(creditsRemaining: 142_300, creditsTotal: 150_000, periodEnd: SampleData.account.subscription?.periodEnd))
        }
        let prefix = request.real ? "real-" : ""
        for page in DashboardPage.allCases {
            model.page = page
            render(DashboardView(model: model).frame(width: 1240, height: 800), name: "\(prefix)dashboard-\(page.rawValue)", dir: request.dir)
        }
        let state = NotchState()
        state.notchSize = CGSize(width: 190, height: 32)
        render(NotchView(model: model, state: state, controller: nil).frame(width: state.collapsedSize.width + 40, height: 60).background(Color(white: 0.85)),
               name: "\(prefix)notch-collapsed", dir: request.dir)
        state.expanded = true
        for tab in NotchTab.allCases {
            state.tab = tab
            render(NotchView(model: model, state: state, controller: nil).frame(width: state.expandedSize.width + 40, height: state.expandedSize.height + 20).background(Color(white: 0.85)),
                   name: "\(prefix)notch-\(tab.rawValue)", dir: request.dir)
        }
        if !request.real {
            model.setPreview(lastSpoken: "", account: nil, state: .signedOut)
            model.page = .overview
            render(DashboardView(model: model).frame(width: 1240, height: 800), name: "dashboard-overview-signed-out", dir: request.dir)
        }
        print("snapshots written to \(request.dir.path)")
        exit(0)
    }

    private static func render<V: View>(_ view: V, name: String, dir: URL) {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
#endif
