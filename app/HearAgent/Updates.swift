import AppKit
import SwiftUI

/// A published build, as served by the backend's `/releases/latest`.
struct Release: Decodable, Equatable {
    struct Highlight: Decodable, Equatable, Hashable {
        let title: String
        let detail: String
    }

    let version: String
    let build: Int
    let url: String
    let highlights: [Highlight]

    /// What this build ships with, shown once after updating to it.
    static let bundled = Release(version: AppVersion.version, build: AppVersion.build, url: "https://hearagent.app/download", highlights: [
        Highlight(title: "Three themes", detail: "Settings → Appearance switches the dashboard between Classic, Blue and Plum."),
        Highlight(title: "Usage you can scrub", detail: "Spend and daily tokens are line charts now; hover any day to read it."),
        Highlight(title: "Pick your narrator", detail: "Choose George, Alice or Brian and set the speaking speed on the Narrator page."),
        Highlight(title: "A quicker notch", detail: "It opens straight out of the camera and shows both 5-hour windows next to refresh."),
    ])
}

enum AppVersion {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    static var build: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0 }
}

/// Asks the backend for the newest build and shows the answer; after an update, says what's new.
@MainActor
enum Updates {
    enum Prompt: Equatable {
        case upToDate
        case available(Release)
        case whatsNew(from: String, Release)
        case failed
    }

    private static var window: NSWindow?

    static func check(apiBaseURL: String) {
        guard let url = URL(string: "\(apiBaseURL)/releases/latest") else { return show(.failed) }
        Task {
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let latest = try? await JSONDecoder.snakeCase.decode(Release.self, from: URLSession.shared.data(for: request).0)
            guard let latest else { return show(.failed) }
            show(latest.build > AppVersion.build ? .available(latest) : .upToDate)
        }
    }

    /// Once per new build: the highlights of the version the user just updated to.
    static func showWhatsNewIfUpdated(defaults: UserDefaults = .standard) {
        let key = "lastLaunchedBuild"
        let previousBuild = defaults.integer(forKey: key)
        let previousVersion = defaults.string(forKey: "lastLaunchedVersion") ?? ""
        defaults.set(AppVersion.build, forKey: key)
        defaults.set(AppVersion.version, forKey: "lastLaunchedVersion")
        guard previousBuild > 0, AppVersion.build > previousBuild else { return }
        show(.whatsNew(from: previousVersion, .bundled))
    }

    static func show(_ prompt: Prompt) {
        window?.close()
        let host = NSHostingController(rootView: UpdateCard(prompt: prompt) { download in
            if let download, let url = URL(string: download) { NSWorkspace.shared.open(url) }
            window?.close()
            window = nil
        })
        host.sizingOptions = [.preferredContentSize]
        let panel = UpdateWindow(contentViewController: host)
        panel.styleMask = [.borderless]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.layoutIfNeeded()
        panel.center()
        window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}

private final class UpdateWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

extension JSONDecoder {
    static let snakeCase: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}

/// Dark glass card: the app icon, what happened, and one clear way out.
struct UpdateCard: View {
    let prompt: Updates.Prompt
    /// Called with a download link for "Download update", nil for OK / Later.
    let dismiss: (String?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            AppGlyph(size: 76)
            switch prompt {
            case .upToDate:
                message("You're up to date", "Hear Agent \(AppVersion.version) is the latest version.")
                primary("OK") { dismiss(nil) }
            case .failed:
                message("Couldn't check for updates", "Hear Agent's server didn't answer. Check your connection and try again.")
                primary("OK") { dismiss(nil) }
            case .available(let release):
                versionPill(from: AppVersion.version, to: release.version, celebrate: false)
                Text("A new version is ready").font(.system(size: 15, weight: .semibold)).padding(.top, 14)
                HighlightsCard(highlights: release.highlights).padding(.top, 16)
                HStack(spacing: 10) {
                    secondary("Later") { dismiss(nil) }
                    primary("Download update") { dismiss(release.url) }
                }
                .padding(.top, 18)
            case .whatsNew(let from, let release):
                versionPill(from: from, to: release.version, celebrate: true)
                HighlightsCard(highlights: release.highlights).padding(.top, 18)
                secondary("OK") { dismiss(nil) }.padding(.top, 18)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 22)
        .frame(width: Self.width(prompt))
        .background(GlassBackground())
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.14)))
        .environment(\.colorScheme, .dark)
    }

    private static func width(_ prompt: Updates.Prompt) -> CGFloat {
        switch prompt {
        case .upToDate, .failed: 360
        case .available, .whatsNew: 440
        }
    }

    private func message(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(detail).font(.system(size: 13)).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 22)
        .padding(.bottom, 20)
    }

    private func versionPill(from: String, to: String, celebrate: Bool) -> some View {
        HStack(spacing: 8) {
            Text(from.isEmpty ? "Before" : from).foregroundStyle(.white.opacity(0.55))
            Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
            Text(to).fontWeight(.semibold)
            if celebrate { Text("🎉") }
        }
        .font(.system(size: 13.5).monospacedDigit())
        .padding(.horizontal, 16)
        .frame(height: 32)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
        .padding(.top, 18)
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.black)
                .frame(maxWidth: .infinity).frame(height: 36)
                .background(Color.white, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13.5, weight: .semibold))
                .frame(maxWidth: .infinity).frame(height: 36)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
    }
}

/// Hear Agent's mark: a light tile holding a black notch screen with the listener inside.
struct AppGlyph: View {
    var size: CGFloat = 76

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0xFAFAFA), Color(hex: 0xD6D6D9)], startPoint: .top, endPoint: .bottom))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.15, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x1C1C1E), .black], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.74, height: size * 0.4)
                    .overlay(PixelCat(mood: .idle, paused: true, pixel: size / 50))
                    .offset(y: -size * 0.07)
            }
            .overlay(RoundedRectangle(cornerRadius: size * 0.235, style: .continuous).strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5))
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}

/// "★ Highlights" and one line per change: the change in bold, then what it means.
private struct HighlightsCard: View {
    let highlights: [Release.Highlight]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "star.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(LinearGradient(colors: [Color(hex: 0xFFB340), Color(hex: 0xF5821F)], startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("Highlights").font(.system(size: 14, weight: .semibold))
            }
            .padding(14)
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(highlights, id: \.self) { h in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").foregroundStyle(.white.opacity(0.6))
                            (Text(h.title).fontWeight(.semibold).foregroundColor(.white) + Text(": \(h.detail)").foregroundColor(.white.opacity(0.7)))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.system(size: 13))
                        .lineSpacing(2)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.09)))
    }
}

/// Frosted dark glass that blurs whatever is behind the window.
private struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
