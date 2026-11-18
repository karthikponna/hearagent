import SwiftUI

struct OverviewPage: View {
    @Bindable var model: AppModel

    var body: some View {
        let report = model.usage.report
        let month = report?.month
        VStack(alignment: .leading, spacing: 16) {
            SetupBanner(model: model)

            HStack(spacing: 14) {
                let spend = month?.costUsd ?? 0
                let budget = max(model.preferences.monthlyBudget, 1)
                StatCard(icon: "dollarsign", title: "Spend", tag: "Budget", value: Format.usd(spend), detail: "of \(Format.usd(budget))", dark: true) {
                    TickMeter(fraction: spend / budget, color: .white)
                    HStack {
                        Text("\(Format.usd(max(budget - spend, 0))) left this month").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text(Format.percent(spend / budget * 100)).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    }
                }
                StatCard(icon: "number", title: "Tokens", tag: "Month", value: Format.tokens(month?.tokens ?? 0)) {
                    TickMeter(fraction: Double(month?.activeDays ?? 0) / Double(max(month?.daysInMonth ?? 30, 1)), color: Theme.success)
                    Text("\(month?.activeDays ?? 0) of \(month?.daysInMonth ?? 30) days active").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                StatCard(icon: "bubble.left.and.bubble.right", title: "Sessions", tag: "Month", value: "\(month?.sessions ?? 0)") {
                    TickMeter(fraction: min(Double(model.sessions.count) / 6, 1), color: Theme.warning)
                    Text("\(model.sessions.count) live right now").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                let five = report?.claudeFiveHour
                StatCard(icon: "timer", title: "Claude 5h", tag: five?.estimated == false ? "Exact" : "Estimate", value: Format.percent(five?.usedPercent ?? 0)) {
                    LimitBar(fraction: (five?.usedPercent ?? 0) / 100, height: 8)
                    Text(five?.resetsAtMs.map { "Resets \(Format.time($0))" } ?? "No active window")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }

            HStack(spacing: 0) {
                let fourWeeks = report?.days.suffix(28) ?? []
                let tokens4w = fourWeeks.reduce(UInt64(0)) { $0 + $1.claudeTokens + $1.codexTokens }
                MetricCell(icon: "sum", title: "Total tokens", value: Format.tokens(tokens4w), note: "Last 4 weeks")
                divider
                MetricCell(icon: "arrow.triangle.2.circlepath", title: "Cache hit rate", value: Format.percent((month?.cacheHitRate ?? 0) * 100), note: "Reads beat fresh input", noteColor: Theme.success)
                divider
                let sessions = Double(max(month?.sessions ?? 0, 1))
                MetricCell(icon: "chart.line.uptrend.xyaxis", title: "Avg cost", value: Format.usd((month?.costUsd ?? 0) / sessions), note: "per session")
                divider
                MetricCell(icon: "calendar", title: "Forecast", value: Format.usd(month?.forecastUsd ?? 0), note: "this month at this pace")
                divider
                MetricCell(icon: "waveform", title: "Voice credits", value: creditsText, note: creditsNote, noteColor: Theme.accent)
            }
            .card()

            HStack(alignment: .top, spacing: 14) {
                WorkRhythm(heatmap: report?.heatmap ?? [])
                    .frame(maxWidth: .infinity)
                LiveNowCard(model: model)
                    .frame(width: 320)
            }
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Recent spoken updates", systemImage: "waveform").font(.cardTitle)
                    Spacer()
                    Button("See all") { model.page = .voice }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
                }
                if model.history.isEmpty {
                    Text("Nothing yet. When an agent needs approval, finishes or stops, you'll hear it and see it here.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                } else {
                    ForEach(model.history.prefix(3)) { SpokenRow(model: model, update: $0) }
                }
            }
            .card()
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(width: 1).padding(.horizontal, 14)
    }

    private var creditsText: String {
        if case .active(let remaining, _, _) = model.accountState { return Format.tokens(UInt64(max(remaining, 0))) }
        if case .creditsExhausted = model.accountState { return "0" }
        return "—"
    }

    private var creditsNote: String {
        switch model.accountState {
        case .active(let remaining, _, _): "about \(remaining / 180) updates left"
        case .creditsExhausted: "renews next billing date"
        case .noSubscription: "subscribe to hear updates"
        case .signedOut: "sign in to start"
        case .offline: "offline"
        }
    }
}
