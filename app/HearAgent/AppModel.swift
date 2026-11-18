import AppKit
import Foundation
import Observation
@preconcurrency import UserNotifications
import os

@MainActor
@Observable
final class AppModel {
    nonisolated static let log = Logger(subsystem: "com.karthikponna.hearagent", category: "engine")

    let preferences: Preferences
    private(set) var sessions: [HearSession] = []
    private(set) var lastSpoken = ""
    private(set) var engineError: String?
    private(set) var hookStatus: [AgentKind: Bool] = [:]
    private(set) var hookError: String?
    private(set) var launchAtLoginEnabled = LoginItem.isEnabled

    private(set) var accountState: HearAccountState = .signedOut
    private(set) var account: HearAccount?
    private(set) var isSigningIn = false
    private(set) var accountError: String?

    let usage: UsageStore
    let servers = ServerStore()
    let actions: ActionStore
    private(set) var history: [SpokenUpdate] = []
    var page: DashboardPage = .overview
    /// Bumped when a session starts needing the user, so the notch can open itself.
    private(set) var attentionTick = 0

    @ObservationIgnored private var engine: Engine
    @ObservationIgnored private let player = AudioPlayer()
    @ObservationIgnored private var pendingSignIn: HearSignIn?
    @ObservationIgnored private var replaying = false

    /// `listen: false` builds a model that never touches the shared socket, agent configs, or the keychain.
    init(preferences: Preferences = Preferences(), listen: Bool = true) {
        self.preferences = preferences
        usage = UsageStore(preferences: preferences)
        actions = ActionStore(preferences: preferences)
        let events = EngineEvents()
        engine = Engine(listener: events, apiBaseUrl: preferences.apiBaseURL)
        events.model = self
        engine.setMuted(muted: preferences.muted)
        applySpokenKinds()
        player.volume = Float(preferences.volume)
        player.onFinished = { [weak self] in
            guard let self else { return }
            if self.replaying {
                self.replaying = false
            } else {
                self.engine.speechFinished()
            }
        }
        guard listen else { return }
        usage.start()
        let token = Keychain.loadToken()
        engine.setToken(token: token)
        do {
            let path = try engine.start(socketPath: nil)
            Self.log.info("listening on \(path, privacy: .public)")
        } catch {
            engineError = error.localizedDescription
        }
        repointMovedHooks()
        refreshHookStatus()
        if token != nil { refreshAccount() }
    }

    // MARK: Playback

    var muted: Bool {
        get { preferences.muted }
        set {
            preferences.muted = newValue
            engine.setMuted(muted: newValue)
            if newValue { player.stop() }
        }
    }

    var volume: Double {
        get { preferences.volume }
        set {
            preferences.volume = newValue
            player.volume = Float(newValue)
        }
    }

    func skipCurrent() {
        player.stop()
    }

    var speakApprovals: Bool {
        get { preferences.speakApprovals }
        set { preferences.speakApprovals = newValue; applySpokenKinds() }
    }

    var speakSummaries: Bool {
        get { preferences.speakSummaries }
        set { preferences.speakSummaries = newValue; applySpokenKinds() }
    }

    var speakStops: Bool {
        get { preferences.speakStops }
        set { preferences.speakStops = newValue; applySpokenKinds() }
    }

    private func applySpokenKinds() {
        engine.setKindEnabled(kind: .approval, enabled: preferences.speakApprovals)
        engine.setKindEnabled(kind: .summary, enabled: preferences.speakSummaries)
        engine.setKindEnabled(kind: .stopFailure, enabled: preferences.speakStops)
    }

    /// Plays a past line again from memory. Free: no credits are used.
    func replay(_ update: SpokenUpdate) {
        guard !player.isPlaying else { return }
        replaying = true
        player.play(update.audio)
    }

    var isPlaying: Bool { player.isPlaying }

    /// The usage record behind a live session, matched by session id.
    func usage(for session: HearSession) -> HearSessionUsage? {
        guard let id = session.key.split(separator: ":", maxSplits: 1).last else { return nil }
        return usage.session(id: String(id))
    }

    func liveSession(for usage: HearSessionUsage) -> HearSession? {
        let prefix = usage.agent == .claudeCode ? "claude-code:" : "codex:"
        return sessions.first { $0.key == prefix + usage.id }
    }

    func sessionName(forKey key: String) -> String {
        sessions.first { $0.key == key }?.name ?? "Session"
    }

    var needsAttention: [HearSession] {
        sessions.filter { $0.status == .needsYou || $0.status == .failed }
    }

    func togglePin(_ session: HearSession) {
        engine.setPinned(sessionKey: session.pinned ? nil : session.key)
    }

    @discardableResult
    func injectSample(agent: String, payload: String) -> Bool {
        engine.injectPayload(agent: agent, payloadJson: payload)
    }

    fileprivate func received(_ utterance: HearUtterance) {
        lastSpoken = utterance.text
        Self.log.info("playing [\(String(describing: utterance.kind), privacy: .public)] \(utterance.text, privacy: .public)")
        recordSpoken(utterance)
        replaying = false
        player.play(utterance.audio)
    }

    private func recordSpoken(_ utterance: HearUtterance) {
        history.insert(
            SpokenUpdate(id: utterance.id, kind: utterance.kind, text: utterance.text, sessionKey: utterance.sessionKey, at: Date(), audio: utterance.audio),
            at: 0
        )
        if history.count > 40 { history.removeLast(history.count - 40) }
    }

    fileprivate func sessionsChanged(_ sessions: [HearSession]) {
        let before = Set(self.sessions.filter { $0.status == .needsYou }.map(\.key))
        let finishedBefore = Set(self.sessions.filter { $0.status == .done }.map(\.key))
        self.sessions = sessions
        if sessions.contains(where: { $0.status == .needsYou && !before.contains($0.key) }) {
            attentionTick += 1
        }
        // New finished turns mean new usage on disk.
        if sessions.contains(where: { $0.status == .done && !finishedBefore.contains($0.key) }) {
            usage.refresh()
        }
    }

    fileprivate func accountStateChanged(_ state: HearAccountState) {
        let previous = accountState
        accountState = state
        Self.log.info("account state: \(String(describing: state), privacy: .public)")
        if state == .signedOut, previous != .signedOut {
            Keychain.deleteToken()
            account = nil
        }
        notifyIfNewlyBlocked(previous: previous, current: state)
    }

    // MARK: Account

    var isSignedIn: Bool { account != nil || accountState != .signedOut }

    func signIn() {
        let request = engine.startSignIn()
        pendingSignIn = request
        isSigningIn = true
        accountError = nil
        if let url = URL(string: request.url) { NSWorkspace.shared.open(url) }
    }

    /// Handles `hearagent://auth?code=…&state=…` and `hearagent://billing?…`.
    func handle(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let query = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        switch parts.host {
        case "auth":
            guard let pending = pendingSignIn, query["state"] == pending.state, let code = query["code"] else {
                accountError = "That sign-in link is out of date. Please try again."
                isSigningIn = false
                return
            }
            pendingSignIn = nil
            let engine = self.engine
            Task.detached {
                let result = Result { try engine.finishSignIn(code: code, verifier: pending.verifier) }
                await MainActor.run {
                    self.isSigningIn = false
                    switch result {
                    case .success(let token):
                        Keychain.saveToken(token)
                        self.refreshAccount()
                    case .failure(let error):
                        self.accountError = "Sign-in failed: \(error.localizedDescription)"
                    }
                }
            }
        case "billing":
            refreshAccount()
        default:
            break
        }
    }

    func refreshAccount() {
        let engine = self.engine
        Task.detached {
            let result = Result { try engine.fetchAccount() }
            await MainActor.run {
                switch result {
                case .success(let account):
                    self.account = account
                    self.accountError = nil
                case .failure(HearError.SignedOut):
                    self.account = nil
                case .failure(let error):
                    self.accountError = error.localizedDescription
                }
            }
        }
    }

    func signOut() {
        let engine = self.engine
        Keychain.deleteToken()
        account = nil
        Task.detached { engine.signOut() }
    }

    func openCheckout() { openBillingURL { try $0.checkoutUrl() } }

    func openPortal() { openBillingURL { try $0.portalUrl() } }

    private func openBillingURL(_ fetch: @escaping @Sendable (Engine) throws -> String) {
        let engine = self.engine
        Task.detached {
            let result = Result { try fetch(engine) }
            await MainActor.run {
                switch result {
                case .success(let link):
                    if let url = URL(string: link) { NSWorkspace.shared.open(url) }
                case .failure(let error):
                    self.accountError = error.localizedDescription
                }
            }
        }
    }

    private func notifyIfNewlyBlocked(previous: HearAccountState, current: HearAccountState) {
        let message: String
        switch current {
        case .creditsExhausted(let periodEnd):
            if case .creditsExhausted = previous { return }
            message = "Your monthly credits are used up\(Self.renewalSuffix(periodEnd)). Spoken updates are paused."
        case .noSubscription:
            if previous == .noSubscription { return }
            message = "Your Hear Agent subscription isn't active, so spoken updates are paused."
        default:
            return
        }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Hear Agent"
            content.body = message
            center.add(UNNotificationRequest(identifier: "hearagent-account", content: content, trigger: nil))
        }
    }

    static func renewalSuffix(_ iso: String?) -> String {
        guard let date = iso.flatMap({ ISO8601DateFormatter().date(from: $0) }) else { return "" }
        return ", renewing \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    // MARK: Agent hooks

    static let agents: [AgentKind] = [.claudeCode, .codex]

    var anyHooksInstalled: Bool { hookStatus.values.contains(true) }

    /// The hook binary shipped inside this app bundle.
    var hookBinaryPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/hearagent-hook").path
    }

    func refreshHookStatus() {
        for agent in Self.agents {
            hookStatus[agent] = hooksInstalled(agent: agent)
        }
    }

    func setHooks(_ agent: AgentKind, enabled: Bool) {
        do {
            if enabled {
                _ = try installHooks(agent: agent, hookBinary: hookBinaryPath)
            } else {
                _ = try uninstallHooks(agent: agent)
            }
            hookError = nil
        } catch {
            hookError = "\(agent.displayName): \(error.localizedDescription)"
        }
        refreshHookStatus()
    }

    /// If the app moved (for example into /Applications) or the event list changed, rewrite the hooks.
    private func repointMovedHooks() {
        for agent in Self.agents where installedHookCommand(agent: agent) != nil {
            _ = try? installHooks(agent: agent, hookBinary: hookBinaryPath)
        }
    }

    var launchAtLogin: Bool {
        get { launchAtLoginEnabled }
        set {
            do {
                try LoginItem.set(enabled: newValue)
                hookError = nil
            } catch {
                hookError = "Launch at login: \(error.localizedDescription)"
            }
            launchAtLoginEnabled = LoginItem.isEnabled
        }
    }

    #if DEBUG
    func setPreview(lastSpoken: String, account: HearAccount?, state: HearAccountState) {
        self.lastSpoken = lastSpoken
        self.account = account
        self.accountState = state
    }

    func setPreview(sessions: [HearSession], history: [SpokenUpdate], hooks: [AgentKind: Bool]) {
        self.sessions = sessions
        self.history = history
        self.hookStatus = hooks
    }
    #endif
}

extension AgentKind {
    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }
}

/// Receives engine callbacks on Rust threads and hops to the main actor.
private final class EngineEvents: EngineListener, @unchecked Sendable {
    weak var model: AppModel?

    func speak(utterance: HearUtterance) {
        Task { @MainActor [weak self] in self?.model?.received(utterance) }
    }

    func sessionsChanged(sessions: [HearSession]) {
        Task { @MainActor [weak self] in self?.model?.sessionsChanged(sessions) }
    }

    func accountStateChanged(state: HearAccountState) {
        Task { @MainActor [weak self] in self?.model?.accountStateChanged(state) }
    }
}
