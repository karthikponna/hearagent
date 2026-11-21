import Charts
import SwiftUI

// MARK: Buttons

/// Black capsule: Run, Allow, Add, Apply.
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.ink
    var height: CGFloat = 32
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButton(configuration: configuration, color: color, height: height)
    }

    private struct PrimaryButton: View {
        let configuration: Configuration
        let color: Color
        let height: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, height * 0.5)
                .frame(height: height)
                .background(color.opacity(hovering ? 0.85 : 1), in: Capsule())
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.35)
                .contentShape(Capsule())
                .onHover { hovering = $0 && isEnabled }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

/// White capsule with a hairline: Open, Folder, Deny, Disconnect, Remove.
struct SoftButtonStyle: ButtonStyle {
    var destructive = false
    var height: CGFloat = 32
    func makeBody(configuration: Configuration) -> some View {
        SoftButton(configuration: configuration, destructive: destructive, height: height)
    }

    private struct SoftButton: View {
        let configuration: Configuration
        let destructive: Bool
        let height: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(destructive ? Theme.red : Theme.ink)
                .padding(.horizontal, height * 0.44)
                .frame(height: height)
                .background(hovering ? Theme.well : Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.line))
                .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Capsule())
                .onHover { hovering = $0 && isEnabled }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

/// A round white icon button: trash, folder.
struct CircleButtonStyle: ButtonStyle {
    var size: CGFloat = 32
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        CircleButton(configuration: configuration, size: size, filled: filled)
    }

    private struct CircleButton: View {
        let configuration: Configuration
        let size: CGFloat
        let filled: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: size, height: size)
                .background(hovering ? Theme.well : (filled ? Theme.card : .clear), in: Circle())
                .overlay(Circle().strokeBorder(filled ? Theme.line : .clear))
                .scaleEffect(configuration.isPressed ? 0.93 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Circle())
                .onHover { hovering = $0 && isEnabled }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// A square icon button with no surface until hovered.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    func makeBody(configuration: Configuration) -> some View {
        IconButton(configuration: configuration, size: size)
    }

    private struct IconButton: View {
        let configuration: Configuration
        let size: CGFloat
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(hovering ? Theme.ink : Theme.muted)
                .frame(width: size, height: size)
                .background(hovering ? Theme.well : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// A text link: colored, a touch darker under the pointer.
struct LinkButtonStyle: ButtonStyle {
    var color: Color = Theme.muted
    func makeBody(configuration: Configuration) -> some View {
        LinkButton(configuration: configuration, color: color)
    }

    private struct LinkButton: View {
        let configuration: Configuration
        let color: Color
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .opacity(configuration.isPressed ? 0.6 : (hovering ? 0.8 : 1))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

// MARK: Header controls

/// Gray track with a white sliding selection: 7D / 4W / 1Y.
struct PillPicker<Value: Hashable & Identifiable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    var height: CGFloat = 32
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = option == selection
                Button { withAnimation(Theme.ease) { selection = option } } label: {
                    Text(label(option))
                        .font(.system(size: 12.5, weight: selected ? .bold : .medium))
                        .foregroundStyle(selected ? Theme.ink : Theme.muted)
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .frame(height: height - 6)
                        .background {
                            if selected {
                                Capsule().fill(Theme.card)
                                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.track.opacity(0.7), in: Capsule())
        .fixedSize()
    }
}

/// Presets on the gray track, then a calendar segment for a custom start-to-end range.
/// Choosing a preset clears the custom range; the selection pill slides between them.
struct RangePicker<Value: Hashable & Identifiable>: View {
    let options: [Value]
    @Binding var selection: Value
    @Binding var custom: DayRange?
    let label: (Value) -> String
    var height: CGFloat = 32
    @State private var picking = false
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = custom == nil && option == selection
                Button { withAnimation(Theme.roll) { custom = nil; selection = option } } label: {
                    segment(selected: selected) {
                        Text(label(option)).font(.system(size: 12.5, weight: selected ? .bold : .medium))
                    }
                }
                .buttonStyle(.plain)
            }
            Button { picking = true } label: {
                segment(selected: custom != nil) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar").font(.system(size: 12, weight: .semibold))
                        if let custom {
                            Text(custom.label).font(.system(size: 12.5, weight: .bold)).monospacedDigit()
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Choose dates")
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                RangeCalendar(initial: custom) { picked in
                    withAnimation(Theme.roll) { custom = picked }
                    picking = false
                } onCancel: {
                    picking = false
                }
            }
        }
        .padding(3)
        .background(Theme.track.opacity(0.7), in: Capsule())
        .fixedSize()
    }

    private func segment(selected: Bool, @ViewBuilder content: () -> some View) -> some View {
        content()
            .foregroundStyle(selected ? Theme.accent : Theme.muted)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(height: height - 6)
            .background {
                if selected {
                    Capsule().fill(Theme.card)
                        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                        .matchedGeometryEffect(id: "pill", in: ns)
                }
            }
            .contentShape(Capsule())
    }
}

/// A month calendar for picking a range: click the first day, then the last.
/// The range runs as a band row by row; only the real start and end get a solid disc.
struct RangeCalendar: View {
    let onApply: (DayRange) -> Void
    let onCancel: () -> Void
    @State private var month: Date
    @State private var start: Date?
    @State private var end: Date?
    @State private var hover: Date?

    private let cal = Calendar.current
    private let cell = CGSize(width: 36, height: 32)

    init(initial: DayRange?, onApply: @escaping (DayRange) -> Void, onCancel: @escaping () -> Void) {
        self.onApply = onApply
        self.onCancel = onCancel
        _month = State(initialValue: Calendar.current.startOfMonth(initial?.end ?? Date()))
        _start = State(initialValue: initial?.start)
        _end = State(initialValue: initial?.end)
    }

    private var today: Date { cal.startOfDay(for: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, d in
                        Text(d).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.faint)
                            .frame(width: cell.width)
                    }
                }
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 0) {
                        ForEach(Array(week.enumerated()), id: \.offset) { column, day in
                            dayCell(day, column: column)
                        }
                    }
                }
            }
            Divider().overlay(Theme.line)
            footer
        }
        .padding(16)
        .frame(width: cell.width * 7 + 32)
        .background(Theme.card)
        .environment(\.colorScheme, .light)
    }

    // MARK: Parts

    private var header: some View {
        HStack {
            Text(month.formatted(.dateTime.month(.wide).year())).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
            Spacer()
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(IconButtonStyle())
            Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(IconButtonStyle())
                .disabled(cal.startOfMonth(today) <= month)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                if let start {
                    let r = DayRange(start, end ?? start)
                    Text(r.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink).monospacedDigit()
                    Text(end == nil ? "Now pick the last day" : (r.dayCount == 1 ? "1 day" : "\(r.dayCount) days"))
                        .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                } else {
                    Text("Pick the first day").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 4)
            Button("Cancel", action: onCancel).buttonStyle(SoftButtonStyle(height: 28))
            Button("Apply") { if let start { onApply(DayRange(start, end ?? start)) } }
                .buttonStyle(PrimaryButtonStyle(height: 28))
                .disabled(start == nil)
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date?, column: Int) -> some View {
        if let day {
            let future = day > today
            let lo = start.map { min($0, previewEnd ?? $0) }
            let hi = start.map { max($0, previewEnd ?? $0) }
            let isEdge = day == lo || day == hi
            let inRange = lo.map { day >= $0 } == true && hi.map { day <= $0 } == true
            Button { pick(day) } label: {
                ZStack {
                    if inRange, lo != hi { band(day, column: column, lo: lo!, hi: hi!) }
                    if isEdge {
                        Circle().fill(Theme.ink).frame(width: 30, height: 30)
                    } else if day == today {
                        Circle().strokeBorder(Theme.line, lineWidth: 1).frame(width: 30, height: 30)
                    }
                    Text("\(cal.component(.day, from: day))")
                        .font(.system(size: 12.5, weight: isEdge || day == today ? .semibold : .regular).monospacedDigit())
                        .foregroundStyle(isEdge ? .white : future ? Theme.faint.opacity(0.6) : Theme.ink)
                }
                .frame(width: cell.width, height: cell.height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(future)
            .onHover { inside in
                if inside { hover = day } else if hover == day { hover = nil }
            }
        } else {
            Color.clear.frame(width: cell.width, height: cell.height)
        }
    }

    /// The fill between the ends: half-width at an end, rounded where a row starts or stops.
    private func band(_ day: Date, column: Int, lo: Date, hi: Date) -> some View {
        let lastOfMonth = cal.date(byAdding: .day, value: 1, to: day).map { cal.component(.month, from: $0) != cal.component(.month, from: day) } ?? false
        let leading = day == lo || column == 0 || cal.component(.day, from: day) == 1
        let trailing = day == hi || column == 6 || lastOfMonth
        return UnevenRoundedRectangle(topLeadingRadius: leading ? 15 : 0, bottomLeadingRadius: leading ? 15 : 0,
                                      bottomTrailingRadius: trailing ? 15 : 0, topTrailingRadius: trailing ? 15 : 0, style: .continuous)
            .fill(Theme.well)
            .frame(width: day == lo || day == hi ? cell.width / 2 + 15 : cell.width, height: 30)
            .frame(width: cell.width, alignment: day == lo ? .trailing : day == hi ? .leading : .center)
    }

    // MARK: Logic

    /// While choosing the end, the band follows the pointer.
    private var previewEnd: Date? {
        if let end { return end }
        if let hover, start != nil, hover <= today { return hover }
        return nil
    }

    private func pick(_ day: Date) {
        if start == nil || end != nil {
            start = day
            end = nil
        } else if let s = start, day < s {
            end = s
            start = day
        } else {
            end = day
        }
    }

    private func shift(_ months: Int) {
        if let next = cal.date(byAdding: .month, value: months, to: month) { month = next }
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The month as rows of seven, padded with blanks.
    private var weeks: [[Date?]] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let lead = (cal.component(.weekday, from: month) - cal.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for d in range { cells.append(cal.date(byAdding: .day, value: d - 1, to: month)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }
}

// MARK: Rows and fields

/// A row that takes a soft inset fill under the pointer.
struct HoverRow: ViewModifier {
    var radius: CGFloat = 10
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(hovering ? Theme.well : .clear, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

extension View {
    func hoverRow(radius: CGFloat = 10) -> some View { modifier(HoverRow(radius: radius)) }
}

/// A setting: title and detail on the left, a switch on the right.
struct SettingToggle: View {
    let title: String
    var detail: String?
    var icon: String?
    var iconColor: Color = Theme.muted
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 30, height: 30)
                    .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13.5)).foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(Theme.palette.toggle)
        }
        .padding(.vertical, 7)
    }
}

/// White field with a hairline, used in forms: Action name, Command.
struct FormField: View {
    let prompt: String
    @Binding var text: String
    var mono = false

    var body: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.plain)
            .font(mono ? .mono : .system(size: 13))
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line))
    }
}

/// A right-aligned number field for settings rows.
struct NumberField: View {
    @Binding var value: Double
    var width: CGFloat = 170

    var body: some View {
        TextField("", value: $value, format: .number.grouping(.automatic).locale(Locale(identifier: "en_US")))
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 13).monospacedDigit())
            .padding(.horizontal, 10)
            .frame(width: width, height: 30)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line))
    }
}

/// A vertical hairline between cells in one card.
struct CellDivider: View {
    var body: some View {
        Rectangle().fill(Theme.line).frame(width: 1).padding(.horizontal, 18)
    }
}

// MARK: Charts

/// A line over time with a soft fill. Hovering drops a dashed hairline and a dot on the
/// nearest point and opens a card beside it.
struct TrendChart: View {
    struct Point: Identifiable, Equatable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    let points: [Point]
    var color: Color = Theme.palette.spendLine
    var axes = true
    /// The bottom of the scale; zero unless the values sit in a narrow band (a rate).
    var floor: Double = 0
    var yLabel: (Double) -> String = { Format.usdWhole($0) }
    /// The card beside the hairline; without one the caller reads the hovered point out itself.
    var tip: ((Int) -> ChartTip)? = nil
    var onHover: ((Int?) -> Void)? = nil
    @State private var hovered: Int?
    @State private var tipSize: CGSize = .zero

    var body: some View {
        let top = Self.niceMax(max((points.map(\.value).max() ?? 0) - floor, 0)) + floor
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Day", p.date), yStart: .value("Floor", floor), yEnd: .value("Value", p.value))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(axes ? 0.14 : 0.18), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", p.date), y: .value("Value", p.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: axes ? 2 : 1.6, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let i = hovered, points.indices.contains(i) {
                RuleMark(x: .value("Day", points[i].date))
                    .foregroundStyle(Theme.ink.opacity(0.28))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("Day", points[i].date), y: .value("Value", points[i].value))
                    .symbol {
                        Circle().fill(color).frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
                    }
            }
        }
        .chartXScale(domain: (points.first?.date ?? Date())...(points.last?.date ?? Date()))
        .chartYScale(domain: floor...max(top, floor + 0.0001))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) {
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), collisionResolution: .greedy)
                    .font(.system(size: 11)).foregroundStyle(Theme.faint)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { v in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel { if let n = v.as(Double.self) { Text(yLabel(n)).font(.system(size: 11)).foregroundStyle(Theme.faint) } }
            }
        }
        .chartXAxis(axes ? .visible : .hidden)
        .chartYAxis(axes ? .visible : .hidden)
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plot = proxy.plotFrame.map { geo[$0] } ?? CGRect(origin: .zero, size: geo.size)
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let at):
                            guard let date: Date = proxy.value(atX: at.x - plot.minX) else { return }
                            hovered = nearest(to: date)
                        case .ended:
                            hovered = nil
                        }
                    }
                if let tip, let i = hovered, points.indices.contains(i),
                   let px = proxy.position(forX: points[i].date), let py = proxy.position(forY: points[i].value) {
                    let x = plot.minX + px
                    let y = plot.minY + py
                    let w = tipSize.width
                    let h = tipSize.height
                    let right = x + 14 + w <= plot.maxX
                    let tipY = h >= plot.height ? plot.midY : min(max(y, plot.minY + h / 2), plot.maxY - h / 2)
                    tip(i)
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { tipSize = $0 }
                        .position(x: right ? x + 14 + w / 2 : max(x - 14 - w / 2, plot.minX + w / 2), y: tipY)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .onChange(of: hovered) { _, i in onHover?(i) }
    }

    private func nearest(to date: Date) -> Int? {
        guard !points.isEmpty else { return nil }
        let t = date.timeIntervalSince1970
        var lo = 0
        var hi = points.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if points[mid].date.timeIntervalSince1970 < t { lo = mid } else { hi = mid }
        }
        return abs(points[lo].date.timeIntervalSince1970 - t) <= abs(points[hi].date.timeIntervalSince1970 - t) ? lo : hi
    }

    /// A round axis top a little above the largest value.
    static func niceMax(_ v: Double) -> Double {
        guard v > 0 else { return 1 }
        let raw = v * 1.12 / 5
        let mag = pow(10, Foundation.floor(log10(raw)))
        let step = [1, 2, 2.5, 3, 5, 6, 10].map { $0 * mag }.first { $0 >= raw } ?? raw
        return step * 5
    }
}

/// The card beside a chart's hairline: the day, then one or more values.
struct ChartTip: View {
    struct Row { let label: String; let value: String }
    let title: String
    let rows: [Row]
    var color: Color = Theme.palette.spendLine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink)
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(i == 0 ? color : Color.clear)
                        .frame(width: 9, height: 9)
                    Text(row.label).foregroundStyle(Theme.muted)
                    Spacer(minLength: 18)
                    Text(row.value).monospacedDigit().foregroundStyle(i == 0 ? Theme.ink : Theme.ink2)
                        .fontWeight(i == 0 ? .semibold : .regular)
                }
                .font(.system(size: 12))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.line))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .fixedSize()
    }
}

/// A figure that rolls digit by digit when it changes inside an animation (a range switch,
/// a hover readout); background data refreshes land without a roll.
struct RollingNumber: View {
    let value: Double
    let format: (Double) -> String
    var size: CGFloat = 30

    var body: some View {
        Text(format(value))
            .font(.system(size: size, weight: .bold).monospacedDigit())
            .kerning(-0.6)
            .foregroundStyle(Theme.ink)
            .contentTransition(.numericText(value: value))
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: Shared rows

/// A pending permission: the agent, the command, and the three answers.
struct ApprovalRow: View {
    @Bindable var model: AppModel
    let session: HearSession
    var compact = false

    var body: some View {
        let p = session.pending
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 14)).foregroundStyle(Theme.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(session.name.components(separatedBy: " · ").first ?? session.name) · \(p?.tool ?? "Permission")")
                    .font(.system(size: compact ? 13 : 14, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(p.map { $0.subject.isEmpty ? $0.action : $0.subject } ?? session.lastUpdate)
                    .font(.system(size: compact ? 12 : 13, design: .monospaced)).foregroundStyle(Theme.ink2).lineLimit(compact ? 1 : 2)
            }
            Spacer(minLength: 10)
            if p != nil {
                Button("Deny") { model.decide(session, .deny) }.buttonStyle(SoftButtonStyle(height: compact ? 28 : 34))
                if !compact {
                    Button("Always allow") { model.decide(session, .alwaysAllow) }
                        .buttonStyle(SoftButtonStyle(height: 34))
                        .help(model.suggestedRule(for: session).map { "Allow \($0.tool) \($0.pattern) from now on" } ?? "")
                }
                Button("Allow") { model.decide(session, .allow) }.buttonStyle(PrimaryButtonStyle(height: compact ? 28 : 34))
            } else {
                Button("Open Terminal") { TerminalLauncher.focus(cwd: session.cwd) }.buttonStyle(PrimaryButtonStyle(height: compact ? 28 : 34))
            }
        }
    }
}

/// One row in a spoken updates list.
struct SpokenRow: View {
    @Bindable var model: AppModel
    let update: SpokenUpdate

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(update.text).font(.system(size: 13)).foregroundStyle(Theme.ink).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                Text("\(model.sessionName(forKey: update.sessionKey)) · \(update.at.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.faint)
            }
            Spacer(minLength: 8)
            Button { model.replay(update) } label: { Image(systemName: "play.fill").font(.system(size: 10)) }
                .buttonStyle(CircleButtonStyle(size: 28))
                .help("Replay (free)")
        }
        .padding(.vertical, 6)
    }

    private var icon: String {
        switch update.kind {
        case .approval: "hand.raised.fill"
        case .summary: "checkmark"
        case .stopFailure: "exclamationmark"
        }
    }

    private var color: Color {
        switch update.kind {
        case .approval: Theme.orange
        case .summary: Theme.green
        case .stopFailure: Theme.red
        }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 8) {
            IconSquare(symbol: icon, style: .soft, size: 44).padding(.bottom, 4)
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
            Text(message).font(.system(size: 13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .card()
    }
}

/// Brings the user to their terminal. Sessions can't be addressed directly, so this
/// focuses the running terminal app, or opens Terminal in the session's folder.
@MainActor
enum TerminalLauncher {
    static let terminals = ["com.mitchellh.ghostty", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.apple.Terminal"]

    static func focus(cwd: String) {
        if let running = terminals.lazy.compactMap({ NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }).first {
            running.activate()
        } else if !cwd.isEmpty {
            NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration())
        }
    }

    static func resume(_ session: HearSessionUsage) {
        let command = session.agent == .claudeCode ? "claude --resume \(session.id)" : "codex resume \(session.id)"
        let dir = ActionStore.shellQuote(session.cwd).replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application \"Terminal\"\nactivate\ndo script \"cd \(dir) && \(command)\"\nend tell"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}
