import Foundation
import Observation

/// User settings, persisted in UserDefaults.
@MainActor
@Observable
final class Preferences {
    private let defaults: UserDefaults

    var volume: Double { didSet { defaults.set(volume, forKey: "volume") } }
    /// The dashboard's color theme; Classic unless changed in Settings › Appearance.
    var appearance: Appearance {
        didSet {
            Theme.current = appearance.palette
            defaults.set(appearance.rawValue, forKey: "appearance")
        }
    }
    var muted: Bool { didSet { defaults.set(muted, forKey: "muted") } }
    var voice: NarratorVoice { didSet { defaults.set(voice.rawValue, forKey: "voice") } }
    /// ElevenLabs' speed setting: 0.7 to 1.2, 1 is natural.
    var voiceSpeed: Double { didSet { defaults.set(voiceSpeed, forKey: "voiceSpeed") } }

    var speakApprovals: Bool { didSet { defaults.set(speakApprovals, forKey: "speakApprovals") } }
    var speakSummaries: Bool { didSet { defaults.set(speakSummaries, forKey: "speakSummaries") } }
    var speakStops: Bool { didSet { defaults.set(speakStops, forKey: "speakStops") } }

    var notchEnabled: Bool { didSet { defaults.set(notchEnabled, forKey: "notchEnabled") } }
    var notchExpandOnHover: Bool { didSet { defaults.set(notchExpandOnHover, forKey: "notchExpandOnHover") } }
    var notchOpenOnApproval: Bool { didSet { defaults.set(notchOpenOnApproval, forKey: "notchOpenOnApproval") } }
    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }

    /// 0 = auto (busiest past window counts as 100%).
    var claudeFiveHourLimit: Int { didSet { defaults.set(claudeFiveHourLimit, forKey: "claudeFiveHourLimit") } }
    var claudeWeeklyLimit: Int { didSet { defaults.set(claudeWeeklyLimit, forKey: "claudeWeeklyLimit") } }
    var limitWarningPercent: Double { didSet { defaults.set(limitWarningPercent, forKey: "limitWarningPercent") } }

    var notifyOnPermission: Bool { didSet { defaults.set(notifyOnPermission, forKey: "notifyOnPermission") } }
    var notifyOnFinish: Bool { didSet { defaults.set(notifyOnFinish, forKey: "notifyOnFinish") } }
    var approveFromNotch: Bool { didSet { defaults.set(approveFromNotch, forKey: "approveFromNotch") } }

    /// Permission requests Hear Agent answers "allow" to on its own.
    var allowRules: [AllowRuleItem] { didSet { save(allowRules, key: "allowRules") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        volume = defaults.object(forKey: "volume") as? Double ?? 1.0
        let appearance = defaults.string(forKey: "appearance").flatMap(Appearance.init(rawValue:)) ?? .classic
        self.appearance = appearance
        Theme.current = appearance.palette
        muted = bool("muted", false)
        voice = defaults.string(forKey: "voice").flatMap(NarratorVoice.init(rawValue:)) ?? .george
        voiceSpeed = defaults.object(forKey: "voiceSpeed") as? Double ?? 1.0
        speakApprovals = bool("speakApprovals", true)
        speakSummaries = bool("speakSummaries", true)
        speakStops = bool("speakStops", true)
        notchEnabled = bool("notchEnabled", true)
        notchExpandOnHover = bool("notchExpandOnHover", true)
        notchOpenOnApproval = bool("notchOpenOnApproval", true)
        showMenuBarIcon = bool("showMenuBarIcon", true)
        claudeFiveHourLimit = defaults.integer(forKey: "claudeFiveHourLimit")
        claudeWeeklyLimit = defaults.integer(forKey: "claudeWeeklyLimit")
        limitWarningPercent = defaults.object(forKey: "limitWarningPercent") as? Double ?? 80
        notifyOnPermission = bool("notifyOnPermission", true)
        notifyOnFinish = bool("notifyOnFinish", false)
        approveFromNotch = bool("approveFromNotch", true)
        allowRules = defaults.data(forKey: "allowRules").flatMap { try? JSONDecoder().decode([AllowRuleItem].self, from: $0) } ?? []
    }

    /// Backend origin. `defaults write com.karthikponna.hearagent apiBaseURL <url>` overrides the built-in one.
    var apiBaseURL: String {
        if let override = defaults.string(forKey: "apiBaseURL"), !override.isEmpty { return override }
        return Bundle.main.object(forInfoDictionaryKey: "HearAgentAPIBaseURL") as? String ?? "http://localhost:8787"
    }

    /// Supabase project URL. Override with `defaults write com.karthikponna.hearagent supabaseURL <url>`.
    var supabaseURL: String {
        if let override = defaults.string(forKey: "supabaseURL"), !override.isEmpty { return override }
        return Bundle.main.object(forInfoDictionaryKey: "HearAgentSupabaseURL") as? String ?? ""
    }

    /// Supabase publishable key (safe to ship). Override with `defaults write … supabaseKey <key>`.
    var supabaseKey: String {
        if let override = defaults.string(forKey: "supabaseKey"), !override.isEmpty { return override }
        return Bundle.main.object(forInfoDictionaryKey: "HearAgentSupabaseKey") as? String ?? ""
    }

    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    func save<T: Encodable>(_ value: T, key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}

/// The voices the narrator can speak in, each an ElevenLabs premade voice.
enum NarratorVoice: String, CaseIterable, Identifiable {
    case george, alice, brian

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    var trait: String {
        switch self {
        case .george: "Warm"
        case .alice: "Clear"
        case .brian: "Deep"
        }
    }

    var blurb: String {
        switch self {
        case .george: "A warm British voice, easy to hear over music."
        case .alice: "A crisp British voice that cuts through a busy room."
        case .brian: "A low, steady American voice."
        }
    }

    var elevenLabsID: String {
        switch self {
        case .george: "JBFqnCBsd6RMkjVDRZzb"
        case .alice: "Xb7hH8MSUJpSbSDYk0k2"
        case .brian: "nPczCjzI2devNBz1zQrb"
        }
    }

    /// The kind of system voice used for previews until previews come from ElevenLabs.
    var previewLanguage: String { self == .brian ? "en-US" : "en-GB" }
    var previewIsFemale: Bool { self == .alice }
}

/// An always-allow rule: a tool and a command or path pattern ("Bash pnpm test", "Edit src/**").
struct AllowRuleItem: Codable, Hashable, Identifiable {
    var tool: String
    var pattern: String
    var id: String { "\(tool) \(pattern)" }
}
