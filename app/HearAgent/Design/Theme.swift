import SwiftUI

/// Hear Agent's visual language: a calm light dashboard, a black notch, one violet accent.
enum Theme {
    static let accent = Color(red: 0.42, green: 0.31, blue: 1.0)
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let codex = Color(red: 0.36, green: 0.49, blue: 0.98)
    static let success = Color(red: 0.13, green: 0.62, blue: 0.42)
    static let warning = Color(red: 0.95, green: 0.55, blue: 0.13)
    static let danger = Color(red: 0.86, green: 0.27, blue: 0.24)

    static let canvas = Color(red: 0.965, green: 0.965, blue: 0.957)
    static let sidebar = Color(red: 0.945, green: 0.945, blue: 0.937)
    static let card = Color.white
    static let line = Color.black.opacity(0.07)
    static let ink = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let muted = Color(red: 0.42, green: 0.42, blue: 0.45)
    static let faint = Color(red: 0.62, green: 0.62, blue: 0.65)

    // Notch
    static let notchBackground = Color.black
    static let notchCard = Color(white: 0.11)
    static let notchCardRaised = Color(white: 0.15)
    static let notchText = Color(white: 0.93)
    static let notchMuted = Color(white: 0.55)

    static let radius: CGFloat = 14
}

extension Font {
    static let pageTitle = Font.system(size: 26, weight: .bold)
    static let cardTitle = Font.system(size: 13, weight: .semibold)
    static let bigNumber = Font.system(size: 26, weight: .bold).monospacedDigit()
    static let label = Font.system(size: 11, weight: .medium)
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.line))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}

/// Small uppercase label used above sidebar groups and inside cards.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(Theme.faint)
    }
}

/// Rounded tag, e.g. "Budget", "Healthy", "ACTIVE".
struct Tag: View {
    let text: String
    var color: Color = Theme.muted
    var filled = false
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(filled ? .white : color)
            .background(filled ? color : color.opacity(0.12), in: Capsule())
    }
}

struct StatusPill: View {
    let status: HearSessionStatus?
    var body: some View {
        let (text, color) = Self.style(status)
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.12), in: Capsule())
    }

    static func style(_ status: HearSessionStatus?) -> (String, Color) {
        switch status {
        case .working: ("Working", Theme.success)
        case .needsYou: ("Needs you", Theme.warning)
        case .failed: ("Stopped", Theme.danger)
        case .done: ("Done", Theme.muted)
        case nil: ("Done", Theme.faint)
        }
    }
}

/// Agent logo square: Claude orange, Codex blue.
struct AgentBadge: View {
    let agent: AgentKind
    var size: CGFloat = 18
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(agent.color)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: agent.symbol)
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(.white)
            }
    }
}

extension AgentKind {
    var color: Color { self == .claudeCode ? Theme.claude : Theme.codex }
    var symbol: String { self == .claudeCode ? "asterisk" : "chevron.left.forwardslash.chevron.right" }
    var shortName: String { self == .claudeCode ? "Claude" : "Codex" }

    init?(agentName: String) {
        switch agentName {
        case "Claude": self = .claudeCode
        case "Codex": self = .codex
        default: return nil
        }
    }
}

/// Thin progress bar made of ticks, like a budget meter.
struct TickMeter: View {
    let fraction: Double
    var ticks = 28
    var color: Color = Theme.ink
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<ticks, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Double(i) / Double(ticks) < fraction ? color : Theme.line)
                    .frame(height: 14)
            }
        }
    }
}

struct LimitBar: View {
    let fraction: Double
    var height: CGFloat = 6
    var track: Color = Theme.line
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(Self.color(fraction)).frame(width: max(height, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
    }

    static func color(_ fraction: Double) -> Color {
        fraction >= 0.9 ? Theme.danger : fraction >= 0.75 ? Theme.warning : Theme.success
    }
}

enum Format {
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

    static func percent(_ v: Double) -> String {
        String(format: "%.0f%%", v)
    }

    static func relative(_ ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        if abs(date.timeIntervalSinceNow) < 60 { return "now" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    static func dateTime(_ ms: Int64) -> String {
        Date(timeIntervalSince1970: Double(ms) / 1000).formatted(date: .abbreviated, time: .shortened)
    }

    static func time(_ ms: Int64?) -> String {
        guard let ms else { return "—" }
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        let sameDay = Calendar.current.isDateInToday(date)
        return sameDay ? date.formatted(date: .omitted, time: .shortened) : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
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
            // gpt-5.5-codex -> GPT-5.5 Codex
            let parts = model.split(separator: "-")
            let head = parts.prefix(2).joined(separator: "-").uppercased()
            return ([head] + parts.dropFirst(2).map { $0.prefix(1).uppercased() + $0.dropFirst() }).joined(separator: " ")
        }
        return model.replacingOccurrences(of: "claude-", with: "")
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
            .replacingOccurrences(of: #"(\d) (\d)"#, with: "$1.$2", options: .regularExpression)
    }

    static var todayChip: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}
