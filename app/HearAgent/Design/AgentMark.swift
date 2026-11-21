import SwiftUI

/// The coding agents Hear Agent knows by name, with their real marks.
enum AgentBrand: String, CaseIterable {
    case claude, codex, gemini, cursor, opencode, other

    init(_ kind: AgentKind) {
        self = kind == .claudeCode ? .claude : .codex
    }

    /// From an engine agent name ("Claude", "Codex") or a route name.
    init(name: String) {
        switch name.lowercased() {
        case let n where n.hasPrefix("claude"): self = .claude
        case let n where n.hasPrefix("codex"): self = .codex
        case let n where n.hasPrefix("gemini"): self = .gemini
        case let n where n.hasPrefix("cursor"): self = .cursor
        case let n where n.hasPrefix("opencode"): self = .opencode
        default: self = .other
        }
    }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .cursor: "Cursor"
        case .opencode: "OpenCode"
        case .other: "Agent"
        }
    }

    /// The color that stands for the agent in dots, chart bars and soft tiles.
    var color: Color {
        switch self {
        case .claude: Theme.claude
        case .codex: Theme.codex
        case .gemini: Theme.gemini
        case .cursor, .opencode, .other: Theme.ink2
        }
    }
}

/// An agent's app-icon-style tile: Claude's starburst on its orange, Codex's mark
/// on white, Gemini's sparkle on navy, Cursor and OpenCode on black.
struct AgentMark: View {
    let brand: AgentBrand
    var size: CGFloat = 22

    init(_ brand: AgentBrand, size: CGFloat = 22) {
        self.brand = brand
        self.size = size
    }

    init(kind: AgentKind, size: CGFloat = 22) {
        self.init(AgentBrand(kind), size: size)
    }

    init(name: String, size: CGFloat = 22) {
        self.init(AgentBrand(name: name), size: size)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        ZStack {
            switch brand {
            case .claude:
                shape.fill(Theme.claude)
                mark("ClaudeMark", scale: 0.66).foregroundStyle(.white)
            case .codex:
                shape.fill(.white)
                shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                mark("CodexMark", scale: 0.68)
                    .foregroundStyle(LinearGradient(colors: [Color(hex: 0x8AA1FF), Color(hex: 0x3B55F0)], startPoint: .top, endPoint: .bottom))
            case .gemini:
                Image("GeminiCLIMark").resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            case .cursor:
                shape.fill(Theme.ink)
                mark("CursorMark", scale: 0.62).foregroundStyle(.white)
            case .opencode:
                shape.fill(Color(hex: 0x131010))
                mark("OpenCodeMark", scale: 0.6).foregroundStyle(.white)
            case .other:
                shape.fill(Theme.well)
                Image(systemName: "terminal").font(.system(size: size * 0.48, weight: .semibold)).foregroundStyle(Theme.muted)
            }
        }
        .frame(width: size, height: size)
    }

    private func mark(_ name: String, scale: CGFloat) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size * scale, height: size * scale)
    }
}

extension AgentKind {
    var color: Color { AgentBrand(self).color }
    var shortName: String { AgentBrand(self).title }

    init?(agentName: String) {
        switch AgentBrand(name: agentName) {
        case .claude: self = .claudeCode
        case .codex: self = .codex
        default: return nil
        }
    }
}

/// Back-compat wrapper for views that show an engine agent.
struct AgentBadge: View {
    let agent: AgentKind
    var size: CGFloat = 18
    var dark = false
    var body: some View { AgentMark(kind: agent, size: size) }
}
