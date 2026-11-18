import Foundation
import Observation

/// User settings, persisted in UserDefaults.
@MainActor
@Observable
final class Preferences {
    private let defaults: UserDefaults

    var volume: Double { didSet { defaults.set(volume, forKey: "volume") } }
    var muted: Bool { didSet { defaults.set(muted, forKey: "muted") } }

    var speakApprovals: Bool { didSet { defaults.set(speakApprovals, forKey: "speakApprovals") } }
    var speakSummaries: Bool { didSet { defaults.set(speakSummaries, forKey: "speakSummaries") } }
    var speakStops: Bool { didSet { defaults.set(speakStops, forKey: "speakStops") } }

    var notchEnabled: Bool { didSet { defaults.set(notchEnabled, forKey: "notchEnabled") } }
    var notchExpandOnHover: Bool { didSet { defaults.set(notchExpandOnHover, forKey: "notchExpandOnHover") } }
    var notchOpenOnApproval: Bool { didSet { defaults.set(notchOpenOnApproval, forKey: "notchOpenOnApproval") } }
    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }

    var monthlyBudget: Double { didSet { defaults.set(monthlyBudget, forKey: "monthlyBudget") } }
    /// 0 = auto (busiest past window counts as 100%).
    var claudeFiveHourLimit: Int { didSet { defaults.set(claudeFiveHourLimit, forKey: "claudeFiveHourLimit") } }
    var claudeWeeklyLimit: Int { didSet { defaults.set(claudeWeeklyLimit, forKey: "claudeWeeklyLimit") } }
    var limitWarningPercent: Double { didSet { defaults.set(limitWarningPercent, forKey: "limitWarningPercent") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        volume = defaults.object(forKey: "volume") as? Double ?? 1.0
        muted = bool("muted", false)
        speakApprovals = bool("speakApprovals", true)
        speakSummaries = bool("speakSummaries", true)
        speakStops = bool("speakStops", true)
        notchEnabled = bool("notchEnabled", true)
        notchExpandOnHover = bool("notchExpandOnHover", true)
        notchOpenOnApproval = bool("notchOpenOnApproval", true)
        showMenuBarIcon = bool("showMenuBarIcon", true)
        monthlyBudget = defaults.object(forKey: "monthlyBudget") as? Double ?? 250
        claudeFiveHourLimit = defaults.integer(forKey: "claudeFiveHourLimit")
        claudeWeeklyLimit = defaults.integer(forKey: "claudeWeeklyLimit")
        limitWarningPercent = defaults.object(forKey: "limitWarningPercent") as? Double ?? 80
    }

    /// Backend origin. `defaults write com.karthikponna.hearagent apiBaseURL <url>` overrides the built-in one.
    var apiBaseURL: String {
        if let override = defaults.string(forKey: "apiBaseURL"), !override.isEmpty { return override }
        return Bundle.main.object(forInfoDictionaryKey: "HearAgentAPIBaseURL") as? String ?? "http://localhost:8787"
    }

    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    func save<T: Encodable>(_ value: T, key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
