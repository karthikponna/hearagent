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

    /// `"Hear Agent" --preview [--sample]` opens the dashboard beside an installed copy without
    /// touching its socket, hooks or keychain: this Mac's real usage, or sample data with --sample.
    static func previewRequested() -> Bool { CommandLine.arguments.contains("--preview") }

    static func loadPreview(model: AppModel) {
        load(model: model, real: !CommandLine.arguments.contains("--sample"))
    }

    static func renderAll(model: AppModel, request: Request) {
        try? FileManager.default.createDirectory(at: request.dir, withIntermediateDirectories: true)
        load(model: model, real: request.real)
        let prefix = request.real ? "real-" : ""
        let tall = CommandLine.arguments.contains("--tall")
        let narrow = CommandLine.arguments.contains("--narrow")
        for page in DashboardPage.allCases {
            model.page = page
            render(DashboardView(model: model).frame(width: narrow ? 1180 : 1380, height: tall ? 1500 : 880), name: "\(prefix)dashboard-\(page.rawValue)", dir: request.dir)
        }
        for theme in Appearance.allCases where theme != .classic {
            model.preferences.appearance = theme
            for page in [DashboardPage.overview, .usage, .voice, .board, .settings] {
                model.page = page
                render(DashboardView(model: model).frame(width: narrow ? 1180 : 1380, height: tall ? 1500 : 880), name: "\(prefix)\(theme.rawValue)-\(page.rawValue)", dir: request.dir)
            }
        }
        model.preferences.appearance = .classic
        model.page = .settings
        for pane in SettingsPane.allCases where pane != .general {
            model.settingsPane = pane
            render(DashboardView(model: model).frame(width: narrow ? 1180 : 1380, height: tall ? 1500 : 880), name: "\(prefix)settings-\(pane.rawValue)", dir: request.dir)
        }
        model.settingsPane = .general
        let next = Release(version: "0.4.0", build: 99, url: "", highlights: Release.bundled.highlights)
        for (name, prompt) in [("uptodate", Updates.Prompt.upToDate), ("available", .available(next)), ("whatsnew", .whatsNew(from: "0.2.0", .bundled))] {
            render(UpdateCard(prompt: prompt) { _ in }.padding(40)
                    .background(LinearGradient(colors: [Color(hex: 0x1D4E6E), Color(hex: 0x0E2A3D), Color(hex: 0x6B5A3A)], startPoint: .topLeading, endPoint: .bottomTrailing)),
                   name: "\(prefix)update-\(name)", dir: request.dir)
        }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let picked = DayRange(cal.date(byAdding: .day, value: -16, to: today)!, cal.date(byAdding: .day, value: -3, to: today)!)
        render(RangeCalendar(initial: picked, onApply: { _ in }, onCancel: {}).background(Theme.card), name: "\(prefix)range-calendar", dir: request.dir)
        render(RangeCalendar(initial: nil, onApply: { _ in }, onCancel: {}).background(Theme.card), name: "\(prefix)range-calendar-empty", dir: request.dir)
        model.usageCustom = picked
        model.page = .usage
        render(DashboardView(model: model).frame(width: narrow ? 1180 : 1380, height: 880), name: "\(prefix)dashboard-usage-custom", dir: request.dir)
        model.usageCustom = nil
        let monthDays = model.usage.report?.days ?? []
        let quiet = monthDays.enumerated().map { i, d in
            i % 9 == 0 ? d : HearDayUsage(day: d.day, claudeTokens: 0, codexTokens: 0, costUsd: 0, sessions: 0, cacheReadTokens: 0, promptTokens: 0)
        }
        for (name, days) in [("busy", monthDays), ("quiet", quiet)] {
            render(MonthMeter(days: days, daysInMonth: 30, animated: false).padding(14).frame(width: 572)
                    .background(Theme.notchCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(20).background(Theme.notchBackground).environment(\.colorScheme, .dark),
                   name: "\(prefix)notch-meter-\(name)", dir: request.dir)
        }
        let gazes = [-1, 0, 1].flatMap { y in [-1, 0, 1].map { x in var g = Gaze(); g.x = x; g.y = y; return g } }
        render(Grid(horizontalSpacing: 18, verticalSpacing: 18) {
                   ForEach(0..<3, id: \.self) { row in
                       GridRow { ForEach(0..<3, id: \.self) { col in PixelCat(mood: .idle, gaze: gazes[row * 3 + col], paused: true, pixel: 4) } }
                   }
               }
               .padding(24).background(Color.black),
               name: "\(prefix)notch-cat-gaze", dir: request.dir)
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
            render(DashboardView(model: model).frame(width: 1380, height: 880), name: "dashboard-overview-signed-out", dir: request.dir)
        }
        print("snapshots written to \(request.dir.path)")
        exit(0)
    }

    private static func load(model: AppModel, real: Bool) {
        if real {
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
            model.preferences.allowRules = SampleData.allowRules
        }
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
