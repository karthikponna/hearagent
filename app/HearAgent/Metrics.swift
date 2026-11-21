import Foundation

enum UsageRange: String, CaseIterable, Identifiable {
    case threeMonths = "3M", sixMonths = "6M", year = "1Y"
    var id: String { rawValue }
    var months: Int {
        switch self {
        case .threeMonths: 3
        case .sixMonths: 6
        case .year: 12
        }
    }
    var days: Int { months * 30 }
}

/// A custom range of whole days, both ends included.
struct DayRange: Equatable {
    let start: Date
    let end: Date

    init(_ a: Date, _ b: Date) {
        let cal = Calendar.current
        let (x, y) = (cal.startOfDay(for: a), cal.startOfDay(for: b))
        start = min(x, y)
        end = max(x, y)
    }

    var startKey: String { DateFormatter.yearMonthDay.string(from: start) }
    var endKey: String { DateFormatter.yearMonthDay.string(from: end) }
    var dayCount: Int { (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) + 1 }

    /// Calendar months the range touches, so month charts cover it.
    var monthCount: Int {
        let c = Calendar.current.dateComponents([.month], from: Calendar.current.startOfMonth(start), to: Calendar.current.startOfMonth(end))
        return (c.month ?? 0) + 1
    }

    /// "Nov 3 – 20", "Oct 28 – Nov 20", or with years when they differ.
    var label: String {
        let cal = Calendar.current
        let thisYear = cal.component(.year, from: Date())
        let sameYear = cal.component(.year, from: start) == cal.component(.year, from: end)
        let showYear = !sameYear || cal.component(.year, from: end) != thisYear
        if start == end { return end.formatted(showYear ? .dateTime.month(.abbreviated).day().year() : .dateTime.month(.abbreviated).day()) }
        let from = start.formatted(sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year())
        let sameMonth = sameYear && cal.component(.month, from: start) == cal.component(.month, from: end)
        let to = end.formatted(sameMonth ? (showYear ? .dateTime.day().year() : .dateTime.day()) : (showYear ? .dateTime.month(.abbreviated).day().year() : .dateTime.month(.abbreviated).day()))
        return "\(from) – \(to)"
    }
}

extension Calendar {
    func startOfMonth(_ date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}

/// Totals for a window of days and the same-length window before it.
struct PeriodStats {
    var tokens: UInt64 = 0
    var cost: Double = 0
    var sessions: Int = 0
    var activeDays: Int = 0

    var costPerSession: Double { sessions == 0 ? 0 : cost / Double(sessions) }

    init(_ days: some Collection<HearDayUsage>) {
        for d in days {
            tokens += d.claudeTokens + d.codexTokens
            cost += d.costUsd
            sessions += Int(d.sessions)
            if d.claudeTokens + d.codexTokens > 0 { activeDays += 1 }
        }
    }
}

enum Metrics {
    /// The last `n` days and the `n` days before them.
    static func windows(_ days: [HearDayUsage], last n: Int) -> (current: ArraySlice<HearDayUsage>, previous: ArraySlice<HearDayUsage>) {
        let current = days.suffix(n)
        let previous = days.dropLast(current.count).suffix(n)
        return (current, previous)
    }

    /// The days inside `range` and the same number of days just before it.
    static func windows(_ days: [HearDayUsage], in range: DayRange) -> (current: ArraySlice<HearDayUsage>, previous: ArraySlice<HearDayUsage>) {
        let (from, to) = (range.startKey, range.endKey)
        guard let lo = days.firstIndex(where: { $0.day >= from }), let hi = days.lastIndex(where: { $0.day <= to }), lo <= hi else {
            return (days[0..<0], days[0..<0])
        }
        let current = days[lo...hi]
        return (current, days[..<lo].suffix(current.count))
    }

    /// Percent change, or 0 when there is nothing to compare against.
    static func change(_ now: Double, _ before: Double) -> Double {
        before <= 0 ? 0 : (now - before) / before * 100
    }

    struct MonthSpend: Identifiable {
        let key: String
        let label: String
        let cost: Double
        let isCurrent: Bool
        let date: Date
        var id: String { key }
    }

    static func months(_ days: [HearDayUsage], count: Int) -> [MonthSpend] {
        var order: [String] = []
        var sums: [String: Double] = [:]
        for d in days {
            let key = String(d.day.prefix(7))
            if sums[key] == nil { order.append(key) }
            sums[key, default: 0] += d.costUsd
        }
        let recent = order.suffix(count)
        return recent.map { key in
            let date = DateFormatter.yearMonth.date(from: key) ?? Date()
            return MonthSpend(key: key, label: date.formatted(.dateTime.month(.abbreviated)), cost: sums[key] ?? 0, isCurrent: key == recent.last, date: date)
        }
    }

    static func dayLabel(_ day: String) -> String {
        guard let date = DateFormatter.yearMonthDay.date(from: day) else { return day }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

extension DateFormatter {
    static let yearMonth: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM"; return f }()
    static let yearMonthDay: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()
}
