import AppKit
import Observation
import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case sessions, usage, servers, routes, voice
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessions: "Sessions"
        case .usage: "Usage"
        case .servers: "Servers"
        case .routes: "Routes"
        case .voice: "Updates"
        }
    }

    var symbol: String {
        switch self {
        case .sessions: "bubble.left.and.bubble.right"
        case .usage: "chart.bar"
        case .servers: "server.rack"
        case .routes: "signpost.right"
        case .voice: "waveform"
        }
    }

    /// Tabs after the divider in the tab bar.
    var secondary: Bool { self == .voice }
}

/// A borderless panel that can take key focus without activating Hear Agent.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Shared state between the notch window and its SwiftUI content.
@MainActor
@Observable
final class NotchState {
    /// What the content shows; animated.
    var expanded = false
    /// Whether the window is at full size. Grows before `expanded`, shrinks after it.
    var panelExpanded = false
    var pinned = false
    var tab: NotchTab = .sessions
    /// Where the cat in the closed notch is looking: always toward the cursor.
    var gaze = Gaze.center
    var notchSize = CGSize(width: 200, height: 32)
    let expandedSize = CGSize(width: 640, height: 456)
    var collapsedSize: CGSize { CGSize(width: notchSize.width + 92, height: notchSize.height) }
}

/// Owns the borderless panel that sits over the MacBook notch (or the top centre
/// of the screen on Macs without one) and grows into a panel on hover.
@MainActor
final class NotchController {
    private let model: AppModel
    let state = NotchState()
    private var panel: NotchPanel?
    private var collapseWork: DispatchWorkItem?
    private var autoCloseWork: DispatchWorkItem?
    private var lastAttentionTick = 0
    private var lastPeekTick = 0
    private var hovering = false
    private let hotKeys = ApprovalHotKeys()
    /// The cat's centre on screen, where its gaze is measured from.
    private var catPoint: CGPoint = .zero
    private var mouseMonitors: [Any] = []

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        hotKeys.onPress = { [weak self] key in
            MainActor.assumeIsolated { self?.answer(key) }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.layout(animated: false) }
        }
        observe()
        sync()
        trackCursor()
    }

    /// Mouse moves anywhere on screen turn the cat's eyes. Watching mouse moves needs no
    /// permission; the local monitor covers moves over Hear Agent's own windows.
    private func trackCursor() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateGaze() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.updateGaze() }
            return event
        }
        mouseMonitors = [global, local].compactMap { $0 }
        updateGaze()
    }

    private func updateGaze() {
        guard !state.expanded else { return }
        let gaze = Gaze(from: catPoint, to: NSEvent.mouseLocation)
        if gaze != state.gaze { state.gaze = gaze }
    }

    /// Re-reads settings and model changes that affect the notch.
    private func observe() {
        withObservationTracking {
            _ = model.preferences.notchEnabled
            _ = model.attentionTick
            _ = model.notchPeekTick
            _ = model.pendingApprovals.map(\.key)
            _ = model.preferences.approveFromNotch
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sync()
                self?.observe()
            }
        }
    }

    private func sync() {
        if model.preferences.notchEnabled {
            if panel == nil { makePanel() }
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
        if model.notchPeekTick != lastPeekTick {
            lastPeekTick = model.notchPeekTick
            if model.preferences.notchEnabled {
                expand()
                scheduleAutoClose()
            }
        }
        defer { updateHotKeys() }
        if model.attentionTick != lastAttentionTick {
            lastAttentionTick = model.attentionTick
            if model.preferences.notchOpenOnApproval && model.preferences.notchEnabled {
                state.tab = .sessions
                expand()
                scheduleAutoClose()
            }
        }
    }

    private func makePanel() {
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        let host = NotchHostingView(rootView: NotchView(model: model, state: state, controller: self))
        // The controller sizes this window. A hosting view that is the window's content view also
        // resizes the window to fit its content; the two fight until AppKit aborts the app. Inside a
        // plain container it only fills the window.
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.onHover = { [weak self] inside in self?.hoverChanged(inside) }
        let container = NSView()
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        panel.contentView = container
        self.panel = panel
        layout(animated: false)
    }

    // MARK: Expand / collapse

    func toggle() {
        state.expanded ? collapse() : expand()
    }

    func expand() {
        collapseWork?.cancel()
        guard !state.expanded else { return }
        state.panelExpanded = true
        layout(animated: false)
        // The window just grew around the notch, which moves every view inside it. Settle that
        // layout now, without animation, and morph on the next frame; otherwise the content
        // animates from its old place in the narrow window and slides in from the side.
        panel?.contentView?.layoutSubtreeIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state.panelExpanded, !self.state.expanded else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) { self.state.expanded = true }
            self.updateHotKeys()
        }
        model.servers.refresh()
    }

    func collapse() {
        guard state.expanded, !state.pinned else { return }
        withAnimation(.spring(response: 0.27, dampingFraction: 1)) { state.expanded = false }
        updateHotKeys()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.state.expanded else { return }
            self.state.panelExpanded = false
            self.layout(animated: false)
            self.updateGaze()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func hoverChanged(_ inside: Bool) {
        hovering = inside
        if inside {
            autoCloseWork?.cancel()
            if model.preferences.notchExpandOnHover { expand() }
        } else {
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.hovering else { return }
                self.collapse()
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    private func scheduleAutoClose() {
        autoCloseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.hovering else { return }
            self.collapse()
        }
        autoCloseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    // MARK: Approval shortcuts

    /// The request the shortcuts answer: the first waiting one, which the notch lists first.
    var shortcutTarget: HearSession? {
        state.expanded && model.preferences.approveFromNotch ? model.pendingApprovals.first : nil
    }

    private func updateHotKeys() {
        if shortcutTarget != nil { hotKeys.register() } else { hotKeys.unregister() }
    }

    private func answer(_ key: ApprovalHotKeys.Key) {
        guard let session = shortcutTarget else { return }
        switch key {
        case .allow: model.decide(session, .allow)
        case .alwaysAllow: model.decide(session, .alwaysAllow)
        case .deny: model.decide(session, .deny)
        }
    }

    func openDashboard(_ page: DashboardPage? = nil) {
        if let page { model.page = page }
        state.pinned = false
        collapse()
        AppDelegate.showDashboard?()
    }

    // MARK: Geometry

    private func layout(animated: Bool) {
        guard let panel, let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let frame = screen.frame
        let notchHeight = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : max(frame.maxY - screen.visibleFrame.maxY, 24)
        var notchWidth: CGFloat = 190
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = frame.width - left.width - right.width
        }
        state.notchSize = CGSize(width: notchWidth, height: notchHeight)
        // Matches the closed notch's layout: ear, 12pt inset, then the 21pt cat.
        catPoint = CGPoint(x: frame.midX - state.collapsedSize.width / 2 + NotchShape.collapsedEar + 12 + 10.5,
                           y: frame.maxY - notchHeight / 2)
        let size = state.panelExpanded ? state.expandedSize : state.collapsedSize
        let origin = CGPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height)
        panel.setFrame(CGRect(origin: origin, size: size), display: true, animate: animated)
    }
}

/// Hosting view that reports hover even when Hear Agent isn't the active app.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(next)
        area = next
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
