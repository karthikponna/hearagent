import AppKit
import Observation
import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case sessions, usage, servers, actions, routes, voice
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessions: "Sessions"
        case .usage: "Usage"
        case .servers: "Servers"
        case .actions: "Actions"
        case .routes: "Routes"
        case .voice: "Updates"
        }
    }

    var symbol: String {
        switch self {
        case .sessions: "rectangle.stack"
        case .usage: "chart.bar.fill"
        case .servers: "server.rack"
        case .actions: "bolt.fill"
        case .routes: "folder.fill"
        case .voice: "waveform"
        }
    }
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
    var notchSize = CGSize(width: 200, height: 32)
    let expandedSize = CGSize(width: 580, height: 430)
    var collapsedSize: CGSize { CGSize(width: notchSize.width + 92, height: notchSize.height) }
}

/// Owns the borderless panel that sits over the MacBook notch (or the top centre
/// of the screen on Macs without one) and grows into a panel on hover.
@MainActor
final class NotchController {
    private let model: AppModel
    let state = NotchState()
    private var panel: NSPanel?
    private var collapseWork: DispatchWorkItem?
    private var autoCloseWork: DispatchWorkItem?
    private var lastAttentionTick = 0
    private var hovering = false

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.layout(animated: false) }
        }
        observe()
        sync()
    }

    /// Re-reads settings and model changes that affect the notch.
    private func observe() {
        withObservationTracking {
            _ = model.preferences.notchEnabled
            _ = model.attentionTick
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
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        let host = NotchHostingView(rootView: NotchView(model: model, state: state, controller: self))
        host.onHover = { [weak self] inside in self?.hoverChanged(inside) }
        panel.contentView = host
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
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { state.expanded = true }
        model.servers.refresh()
    }

    func collapse() {
        guard state.expanded, !state.pinned else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { state.expanded = false }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.state.expanded else { return }
            self.state.panelExpanded = false
            self.layout(animated: false)
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
