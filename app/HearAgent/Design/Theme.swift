import SwiftUI

/// The dashboard's color themes, picked in Settings › Appearance. Status colors (green ready,
/// orange needs you, red deny) and the notch are the same in every theme.
enum Appearance: String, CaseIterable, Identifiable {
    case classic, blue, plum
    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .blue: "Blue"
        case .plum: "Plum"
        }
    }

    var blurb: String {
        switch self {
        case .classic: "Black and white, with a warm charcoal accent."
        case .blue: "Midnight and navy over cool neutrals."
        case .plum: "Deep plum and lilac over soft neutrals."
        }
    }

    var palette: ThemePalette {
        switch self {
        case .classic: .classic
        case .blue: .blue
        case .plum: .plum
        }
    }
}

/// Every color the dashboard uses that changes with the theme.
struct ThemePalette {
    // Surfaces. The window (behind the sidebar) sits a clear step darker than the panel.
    var window: Color
    var panel: Color
    var panelBorder: Color
    var well: Color
    var track: Color
    var column: Color
    var line: Color
    var hairline: Color
    // Ink and selection
    var ink: Color
    var ink2: Color
    var muted: Color
    var faint: Color
    var accent: Color
    var accentWash: Color
    var toggle: Color
    var green: Color
    var blue: Color
    var blueSoft: Color
    // The one decorative highlight: the current month's bar, the spend line.
    var highlightLeft: [Color]
    var highlightRight: [Color]
    var highlightLid: Color
    var barLeft: [Color]
    var barRight: [Color]
    var barLid: Color
    var spendLine: Color
    // The setup banner
    var bannerGround: Color
    var bannerGlyph: Color
    var bannerBorder: Color
    var bannerProgress: Color
    var bannerTrack: Color
    var bannerInk: Color
    // The Spoken updates hero
    var heroTop: Color
    var heroBottom: Color
    var heroText: Color
    var heroMuted: Color
    var heroMeter: Color
    var heroMeterEmpty: Color
    var discTop: Color
    var discBottom: Color
    var discGlyph: Color
    var waveActive: Color
    var waveIdle: Color
    var heroAction: Color
    /// The desktop behind the notch illustration.
    var wallpaper: Color

    /// The original black-and-white look; its decorative accent is a warm charcoal, not orange.
    static let classic = ThemePalette(
        window: Color(hex: 0xE3E3E5), panel: Color(hex: 0xF8F8F8), panelBorder: Color.black.opacity(0.06),
        well: Color(hex: 0xF2F2F2), track: Color(hex: 0xE7E7E7), column: Color(hex: 0xEFEFEF),
        line: Color.black.opacity(0.07), hairline: Color.black.opacity(0.05),
        ink: Color(hex: 0x111111), ink2: Color(hex: 0x3A3A3C), muted: Color(hex: 0x6E6E73), faint: Color(hex: 0x9C9CA1),
        accent: Color(hex: 0x111111), accentWash: Color(hex: 0xF2F2F2), toggle: Color(hex: 0x22A06B),
        green: Color(hex: 0x22A06B), blue: Color(hex: 0x5B6CFF), blueSoft: Color(hex: 0xE5E8FF),
        highlightLeft: [Color(hex: 0x5A544E), Color(hex: 0x2E2A26)], highlightRight: [Color(hex: 0x2A2723), Color(hex: 0x14120F)],
        highlightLid: Color(hex: 0x78716A),
        barLeft: [Color(hex: 0xF6F2EC), Color(hex: 0xEEE7DD)], barRight: [Color(hex: 0xECE5DA), Color(hex: 0xE3DACC)], barLid: Color(hex: 0xF4EFE8),
        spendLine: Color(hex: 0x3B3631),
        bannerGround: Color(hex: 0xF5F3F0), bannerGlyph: Color(hex: 0x8A827A), bannerBorder: Color(hex: 0x1C1917).opacity(0.08),
        bannerProgress: Color(hex: 0x1C1917), bannerTrack: Color(hex: 0x1C1917).opacity(0.12), bannerInk: Color(hex: 0x1C1917),
        heroTop: Color(hex: 0x33302C), heroBottom: Color(hex: 0x161412), heroText: .white, heroMuted: Color(hex: 0xD6D1CB).opacity(0.7),
        heroMeter: Color(hex: 0xF5F1EB), heroMeterEmpty: Color.white.opacity(0.16),
        discTop: Color(hex: 0xF5F1EB), discBottom: Color(hex: 0xD9D2C9), discGlyph: Color(hex: 0x1C1917),
        waveActive: Color(hex: 0xF5F1EB), waveIdle: Color.white.opacity(0.22), heroAction: Color(hex: 0x57524C),
        wallpaper: Color(hex: 0xE9E6E1)
    )

    /// #021024 · #052659 · #5483B3 · #7DA0CA · #C1E8FF. The two darks carry text and actions;
    /// steel and soft are decoration only (under 4.5:1 on white); ice is a ground.
    static let blue = ThemePalette(
        window: Color(hex: 0xDFE5ED), panel: Color(hex: 0xF7F9FB), panelBorder: Color(hex: 0x021024).opacity(0.06),
        well: Color(hex: 0xF1F4F8), track: Color(hex: 0xE4E9F0), column: Color(hex: 0xEAEEF3),
        line: Color(hex: 0x021024).opacity(0.08), hairline: Color(hex: 0x021024).opacity(0.05),
        ink: Color(hex: 0x021024), ink2: Color(hex: 0x27344D), muted: Color(hex: 0x5D6980), faint: Color(hex: 0x98A2B4),
        accent: Color(hex: 0x052659), accentWash: Color(hex: 0xEAF6FF), toggle: Color(hex: 0x052659),
        green: Color(hex: 0x1E9A6A), blue: Color(hex: 0x3A6797), blueSoft: Color(hex: 0xEAF6FF),
        highlightLeft: [Color(hex: 0xFFAE7A), Color(hex: 0xF4762C)], highlightRight: [Color(hex: 0xF27A33), Color(hex: 0xD9530C)],
        highlightLid: Color(hex: 0xFFC49D),
        barLeft: [Color(hex: 0xF6F2EC), Color(hex: 0xEEE7DD)], barRight: [Color(hex: 0xECE5DA), Color(hex: 0xE3DACC)], barLid: Color(hex: 0xF4EFE8),
        spendLine: Color(hex: 0xF26A1B),
        bannerGround: Color(hex: 0xEAF6FF), bannerGlyph: Color(hex: 0x5483B3), bannerBorder: Color(hex: 0x7DA0CA).opacity(0.35),
        bannerProgress: Color(hex: 0x052659), bannerTrack: Color(hex: 0x7DA0CA).opacity(0.35), bannerInk: Color(hex: 0x021024),
        heroTop: Color(hex: 0x052659), heroBottom: Color(hex: 0x021024), heroText: .white, heroMuted: Color(hex: 0xC1E8FF).opacity(0.75),
        heroMeter: Color(hex: 0xC1E8FF), heroMeterEmpty: Color(hex: 0x7DA0CA).opacity(0.25),
        discTop: Color(hex: 0xC1E8FF), discBottom: Color(hex: 0x7DA0CA), discGlyph: Color(hex: 0x052659),
        waveActive: Color(hex: 0xC1E8FF), waveIdle: Color(hex: 0x7DA0CA).opacity(0.35), heroAction: Color(hex: 0x5483B3),
        wallpaper: Color(hex: 0xE2E9F2)
    )

    /// #49225B · #6E3482 · #A56ABD · #E7DBEF · #F5EBFA. Plum carries text and actions, violet marks
    /// what's selected, orchid is decoration only (about 3.4:1 on white), the two lilacs are grounds.
    static let plum = ThemePalette(
        window: Color(hex: 0xE8DFEE), panel: Color(hex: 0xFAF7FC), panelBorder: Color(hex: 0x49225B).opacity(0.07),
        well: Color(hex: 0xF4EEF7), track: Color(hex: 0xEAE1EF), column: Color(hex: 0xF1EAF5),
        line: Color(hex: 0x49225B).opacity(0.09), hairline: Color(hex: 0x49225B).opacity(0.05),
        ink: Color(hex: 0x2E1538), ink2: Color(hex: 0x49225B), muted: Color(hex: 0x6F5A79), faint: Color(hex: 0xA593AD),
        accent: Color(hex: 0x6E3482), accentWash: Color(hex: 0xF5EBFA), toggle: Color(hex: 0x6E3482),
        green: Color(hex: 0x22A06B), blue: Color(hex: 0x6E3482), blueSoft: Color(hex: 0xF5EBFA),
        highlightLeft: [Color(hex: 0x8A4BA0), Color(hex: 0x6E3482)], highlightRight: [Color(hex: 0x5C2A6E), Color(hex: 0x3E1C4E)],
        highlightLid: Color(hex: 0xA56ABD),
        barLeft: [Color(hex: 0xF8F1FB), Color(hex: 0xEFE4F4)], barRight: [Color(hex: 0xE9DCEF), Color(hex: 0xDFCFE7)], barLid: Color(hex: 0xFBF6FD),
        spendLine: Color(hex: 0x6E3482),
        bannerGround: Color(hex: 0xF5EBFA), bannerGlyph: Color(hex: 0xA56ABD), bannerBorder: Color(hex: 0xA56ABD).opacity(0.3),
        bannerProgress: Color(hex: 0x6E3482), bannerTrack: Color(hex: 0xA56ABD).opacity(0.3), bannerInk: Color(hex: 0x49225B),
        heroTop: Color(hex: 0x6E3482), heroBottom: Color(hex: 0x49225B), heroText: .white, heroMuted: Color(hex: 0xF5EBFA).opacity(0.75),
        heroMeter: Color(hex: 0xF5EBFA), heroMeterEmpty: Color(hex: 0xA56ABD).opacity(0.35),
        discTop: Color(hex: 0xF5EBFA), discBottom: Color(hex: 0xE7DBEF), discGlyph: Color(hex: 0x6E3482),
        waveActive: Color(hex: 0xF5EBFA), waveIdle: Color(hex: 0xA56ABD).opacity(0.45), heroAction: Color(hex: 0xA56ABD),
        wallpaper: Color(hex: 0xEFE6F4)
    )
}

/// Hear Agent's visual language: a window a step darker than its inset panel, white cards with
/// whisper shadows, the theme's ink, one accent for what's selected, and green / amber / red for status.
enum Theme {
    /// Set from Preferences; the dashboard rebuilds when it changes.
    nonisolated(unsafe) static var current: ThemePalette = .classic
    static var palette: ThemePalette { current }

    // Surfaces
    static var window: Color { current.window }
    static var panel: Color { current.panel }
    static let card = Color.white
    static var well: Color { current.well }
    static var track: Color { current.track }
    static var line: Color { current.line }
    static var hairline: Color { current.hairline }

    // Ink
    static var ink: Color { current.ink }
    static var ink2: Color { current.ink2 }
    static var muted: Color { current.muted }
    static var faint: Color { current.faint }

    // What's selected or current
    static var accent: Color { current.accent }
    static var accentWash: Color { current.accentWash }

    // Signals
    static var green: Color { current.green }
    static let greenSoft = Color(hex: 0xDDF3E7)
    static let amber = Color(hex: 0xF0B429)
    static let amberSoft = Color(hex: 0xFCF1D6)
    static let orange = Color(hex: 0xF26A1B)
    static let orangeSoft = Color(hex: 0xFDE7D9)
    static let red = Color(hex: 0xE5484D)
    static let redSoft = Color(hex: 0xFBE0E0)
    static var blue: Color { current.blue }
    static var blueSoft: Color { current.blueSoft }

    // Agents
    static let claude = Color(hex: 0xD97757)
    static let codex = Color(hex: 0x4F6BFF)
    static let gemini = Color(hex: 0x4C8DFF)

    // Notch: the same in every theme.
    static let notchBackground = Color.black
    static let notchCard = Color(hex: 0x1C1C1E)
    static let notchCardRaised = Color(hex: 0x2C2C2E)
    static let notchText = Color(white: 0.94)
    static let notchMuted = Color(white: 0.56)
    static let notchGreen = Color(hex: 0x22A06B)

    static let radius: CGFloat = 18
    static let controlRadius: CGFloat = 10
    static let ease = Animation.smooth(duration: 0.24)
    /// Range switches: long enough for figures to visibly roll to their new values.
    static let roll = Animation.smooth(duration: 0.55)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension Font {
    static let pageTitle = Font.system(size: 28, weight: .bold)
    static let cardTitle = Font.system(size: 14, weight: .semibold)
    static let heroNumber = Font.system(size: 32, weight: .bold).monospacedDigit()
    static let bigNumber = Font.system(size: 26, weight: .bold).monospacedDigit()
    static let statNumber = Font.system(size: 24, weight: .bold).monospacedDigit()
    static let label = Font.system(size: 12, weight: .medium)
    static let caption = Font.system(size: 12)
    static let mono = Font.system(size: 12.5, weight: .regular, design: .monospaced)
}

// MARK: Surfaces

struct CardModifier: ViewModifier {
    var padding: CGFloat = 18
    var fill: Color = Theme.card
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(fill)
                    .shadow(color: .black.opacity(0.035), radius: 10, y: 3)
                    .shadow(color: .black.opacity(0.03), radius: 1, y: 0.5)
            }
    }
}

extension View {
    func card(padding: CGFloat = 18, fill: Color = Theme.card) -> some View { modifier(CardModifier(padding: padding, fill: fill)) }
}

/// Uppercase section label: sidebar groups, "PENDING PERMISSIONS", "PINNED".
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.faint
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11.5, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(color)
    }
}

/// A card's title row with optional trailing content.
struct CardHeader<Trailing: View>: View {
    let title: String
    var icon: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            if let icon { IconSquare(symbol: icon, style: .soft) }
            Text(title).font(.cardTitle).foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, icon: String? = nil) { self.init(title: title, icon: icon) { EmptyView() } }
}

/// A glyph in a rounded square: black for stat cards, soft gray for card headers.
struct IconSquare: View {
    enum Style { case solid, soft, onDark, circle }
    let symbol: String
    var style: Style = .solid
    var size: CGFloat = 26

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style == .circle ? size / 2 : size * 0.27, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(style == .solid ? Color.white : style == .onDark ? Theme.ink : Theme.ink)
            .frame(width: size, height: size)
            .background(fill, in: shape)
    }

    private var fill: Color {
        switch style {
        case .solid: Theme.ink
        case .soft, .circle: Theme.well
        case .onDark: Color.white.opacity(0.9)
        }
    }
}

/// Small gray tag at a card's top right: "Budget", "Month", "1 alert".
struct Tag: View {
    let text: String
    var dark = false
    var color: Color?
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .foregroundStyle(color ?? (dark ? Color.white.opacity(0.78) : Theme.muted))
            .background(dark ? Color.white.opacity(0.14) : Theme.well, in: Capsule())
            .fixedSize()
    }
}

/// Bold value pill at a card's bottom right: "52%", "Healthy".
struct ValuePill: View {
    let text: String
    var dark = false
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold).monospacedDigit())
            .padding(.horizontal, 10)
            .frame(height: 22)
            .foregroundStyle(dark ? Theme.ink : Theme.ink)
            .background(dark ? Color.white : Theme.well, in: Capsule())
            .fixedSize()
    }
}

/// Status chip in tables and the chat header: tinted fill, colored word.
struct StatusPill: View {
    let status: HearSessionStatus?
    var body: some View {
        let style = Self.style(status)
        Text(style.text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(style.color)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(style.soft, in: Capsule())
            .fixedSize()
    }

    struct Style { let text: String; let color: Color; let soft: Color }

    static func style(_ status: HearSessionStatus?) -> Style {
        switch status {
        case .working: Style(text: "Working", color: Theme.green, soft: Theme.greenSoft)
        case .needsYou: Style(text: "Needs you", color: Theme.orange, soft: Theme.orangeSoft)
        case .failed: Style(text: "Stopped", color: Theme.red, soft: Theme.redSoft)
        case .done, nil: Style(text: "Done", color: Theme.faint, soft: Theme.well)
        }
    }

    /// The color that stands for a status in dots and lines.
    static func color(_ status: HearSessionStatus?) -> Color { style(status).color }
}

/// "↑ 11%" in green or red.
struct Delta: View {
    let value: Double
    var suffix = "%"
    /// When true, a rise is bad (spend, cost).
    var invert = false
    var decimals = 1

    var body: some View {
        let up = value >= 0
        let good = invert ? !up : up
        let color = abs(value) < 0.05 ? Theme.green : (good ? Theme.green : Theme.red)
        HStack(spacing: 3) {
            Image(systemName: up ? "arrow.up" : "arrow.down").font(.system(size: 10.5, weight: .bold))
            Text(String(format: "%.\(decimals)f", abs(value)) + suffix)
                .contentTransition(.numericText(value: value))
        }
        .font(.system(size: 13, weight: .semibold).monospacedDigit())
        .foregroundStyle(color)
    }
}

/// Keyboard shortcut chip: "⌘K".
struct Kbd: View {
    let text: String
    var dark = false
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(dark ? Color.white.opacity(0.7) : Theme.faint)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(dark ? Color.white.opacity(0.14) : Theme.track.opacity(0.8), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// A rounded initials tile tinted by agent, used in tables.
struct InitialsAvatar: View {
    let text: String
    var tint: Color = Theme.muted
    var size: CGFloat = 30

    var body: some View {
        Text(Self.initials(text))
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }

    static func initials(_ text: String) -> String {
        let words = text.split(whereSeparator: { $0 == "-" || $0 == " " || $0 == "_" || $0 == "." }).prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }.joined()
        return letters.isEmpty ? "·" : letters
    }
}

// MARK: Meters

/// A row of rounded capsules, filled up to a fraction. The dashboard's signature meter.
struct TickMeter: View {
    let fraction: Double
    var color: Color = Theme.ink
    var empty: Color = Theme.track
    var height: CGFloat = 22
    var tickWidth: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let spacing = tickWidth * 0.62
            let count = max(Int((geo.size.width + spacing) / (tickWidth + spacing)), 1)
            let filled = Int((min(max(fraction, 0), 1) * Double(count)).rounded())
            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule().fill(i < filled ? color : empty).frame(width: tickWidth, height: height)
                }
            }
        }
        .frame(height: height)
        .animation(Theme.ease, value: fraction)
    }
}

/// Tick meter for a limit: green up to the value, a marker at the value,
/// then the warning zones ahead in pale green, yellow, peach and pink.
struct ZoneMeter: View {
    let fraction: Double
    var height: CGFloat = 22
    var tickWidth: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let spacing = tickWidth * 0.62
            let count = max(Int((geo.size.width + spacing) / (tickWidth + spacing)), 2)
            let value = min(max(fraction, 0), 1)
            let marker = min(Int((value * Double(count)).rounded()), count - 1)
            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { i in
                    let p = Double(i) / Double(count - 1)
                    if i == marker {
                        Capsule().fill(Theme.ink).frame(width: tickWidth * 0.8, height: height + 8)
                    } else {
                        Capsule().fill(i < marker ? Self.solid(value) : Self.zone(p)).frame(width: tickWidth, height: height)
                    }
                }
            }
            .frame(height: height + 8)
        }
        .frame(height: height + 8)
        .animation(Theme.ease, value: fraction)
    }

    static func solid(_ value: Double) -> Color {
        value >= 0.9 ? Theme.red : value >= 0.75 ? Theme.orange : Theme.green
    }

    static func zone(_ p: Double) -> Color {
        switch p {
        case ..<0.55: Color(hex: 0xD3ECD9)
        case ..<0.7: Color(hex: 0xE6EDC4)
        case ..<0.8: Color(hex: 0xF6E5B5)
        case ..<0.9: Color(hex: 0xF8D3BC)
        default: Color(hex: 0xF6C3C2)
        }
    }
}

/// A slim usage bar: green while healthy, amber and red near the limit.
struct LimitBar: View {
    let fraction: Double
    var height: CGFloat = 6
    var track: Color = Theme.track
    var normal: Color = Theme.green

    var body: some View {
        GeometryReader { geo in
            let f = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(Self.color(f, normal: normal))
                    .frame(width: f == 0 ? 0 : max(height, geo.size.width * f))
            }
        }
        .frame(height: height)
        .animation(Theme.ease, value: fraction)
    }

    static func color(_ fraction: Double, normal: Color = Theme.green) -> Color {
        fraction >= 0.9 ? Theme.red : fraction >= 0.75 ? Theme.amber : normal
    }
}

/// One track and one arc.
struct ProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 3.5
    var color: Color = Theme.ink
    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(Theme.ease, value: fraction)
    }
}

// MARK: Formatting

enum Format {
    /// A project folder and the folder it sits in: "~/code/storefront", "~/fourth_video/youtube-spot".
    /// Any /Users/<name> home reads "~"; callers show the full path in a tooltip.
    static func path(_ path: String) -> String {
        var p = path
        let home = NSHomeDirectory()
        if p == home || p.hasPrefix(home + "/") {
            p = "~" + p.dropFirst(home.count)
        } else if p.hasPrefix("/Users/"), let slash = p.dropFirst("/Users/".count).firstIndex(of: "/") {
            p = "~" + p[slash...]
        }
        let inHome = p.hasPrefix("~")
        let parts = p.split(separator: "/").map(String.init).filter { $0 != "~" }
        guard parts.count > 2 else { return p }
        return (inHome ? "~/" : "…/") + parts.suffix(2).joined(separator: "/")
    }

    static func tokens(_ n: UInt64) -> String {
        let d = Double(n)
        switch d {
        case 1_000_000_000...: return String(format: "%.1fB", d / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", d / 1_000_000)
        case 1_000...: return String(format: "%.0fk", d / 1_000)
        default: return "\(n)"
        }
    }

    static func usd(_ v: Double) -> String {
        v.formatted(.currency(code: "USD").precision(.fractionLength(2)).locale(Locale(identifier: "en_US")))
    }

    static func usdWhole(_ v: Double) -> String {
        v.formatted(.currency(code: "USD").precision(.fractionLength(0)).locale(Locale(identifier: "en_US")))
    }

    static func percent(_ v: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f%%", v)
    }

    static func relative(_ ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 5 { return "now" }
        if seconds < 60 { return "\(seconds) seconds ago" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }

    /// "now", "4m", "2h", "3d".
    static func ago(_ ms: Int64) -> String {
        let seconds = max(Int(Date().timeIntervalSince1970 - Double(ms) / 1000), 0)
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86_400)d"
        }
    }

    static func date(_ ms: Int64) -> String {
        Date(timeIntervalSince1970: Double(ms) / 1000).formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func clock(_ ms: Int64) -> String {
        Date(timeIntervalSince1970: Double(ms) / 1000).formatted(date: .omitted, time: .shortened)
    }

    static func time(_ ms: Int64?) -> String {
        guard let ms else { return "—" }
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        return Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    static func duration(_ seconds: UInt64) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60
        if h >= 24 { return "\(h / 24)d \(h % 24)h" }
        return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m)m"
    }

    static func number(_ n: Int64) -> String {
        n.formatted(.number.locale(Locale(identifier: "en_US")))
    }

    static func shortModel(_ model: String) -> String {
        if model.lowercased().hasPrefix("gpt") {
            // gpt-5.5-codex -> GPT-5.5-codex
            let parts = model.split(separator: "-")
            let head = parts.prefix(2).joined(separator: "-").uppercased()
            return ([head] + parts.dropFirst(2).map(String.init)).joined(separator: "-")
        }
        if model.isEmpty { return "—" }
        return model.replacingOccurrences(of: "claude-", with: "")
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
            .replacingOccurrences(of: #"(\d) (\d)"#, with: "$1.$2", options: .regularExpression)
    }
}
