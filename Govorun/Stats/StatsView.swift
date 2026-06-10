import AppKit
import SwiftUI

struct StatsView: View {
    private enum Metric: String, CaseIterable, Identifiable {
        case words, minutes, sessions

        var id: String { rawValue }

        var label: String {
            switch self {
            case .words:    return "Слова"
            case .minutes:  return "Минуты"
            case .sessions: return "Сессии"
            }
        }

        var totalUnit: String {
            switch self {
            case .words:    return "слов"
            case .minutes:  return "мин"
            case .sessions: return "сессий"
            }
        }

        var icon: String {
            switch self {
            case .words:    return "text.quote"
            case .minutes:  return "timer"
            case .sessions: return "waveform"
            }
        }

        var color: NSColor {
            switch self {
            case .words:    return NSColor(calibratedRed: 0.18, green: 0.42, blue: 0.92, alpha: 1)
            case .minutes:  return NSColor(calibratedRed: 0.78, green: 0.40, blue: 0.10, alpha: 1)
            case .sessions: return NSColor(calibratedRed: 0.18, green: 0.55, blue: 0.34, alpha: 1)
            }
        }

        func value(_ stat: DayStat) -> Int {
            switch self {
            case .words:    return stat.words
            case .minutes:  return stat.seconds / 60
            case .sessions: return stat.sessions
            }
        }
    }

    private enum Period: String, CaseIterable, Identifiable {
        case week, month

        var id: String { rawValue }
        var label: String { self == .week ? "Неделя" : "Месяц" }

        func load() -> [(date: Date, stat: DayStat)] {
            switch self {
            case .week:  return SessionStats.lastDays(7)
            case .month: return SessionStats.currentMonthDays()
            }
        }
    }

    private struct SummaryItem: Identifiable {
        let id: String
        let title: String
        let value: Int
        let sessions: Int
        let seconds: Int
        let accent: NSColor
    }

    @State private var metric: Metric = .words
    @State private var period: Period = .week
    @State private var days: [(date: Date, stat: DayStat)] = SessionStats.lastDays(7)

    @State private var todayW = 0
    @State private var todayS = 0
    @State private var todaySec = 0
    @State private var ydayW = 0
    @State private var ydayS = 0
    @State private var ydaySec = 0
    @State private var allW = 0
    @State private var allS = 0
    @State private var allSec = 0
    @State private var yellow = WarningSettings.yellowMinutes
    @State private var red = WarningSettings.redMinutes

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            summaryStrip
            chartSection
            storageLine
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: refresh)
        .onChange(of: period) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .statsDidUpdate)) { _ in refresh() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Статистика")
                    .font(.system(size: 17, weight: .semibold))
                Text(periodRangeText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: $period) {
                ForEach(Period.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 148)
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 8) {
            ForEach(summaryItems) { item in
                SummaryTile(
                    title: item.title,
                    value: item.value,
                    detail: "\(sessionsText(item.sessions)) • \(minutesText(item.seconds))",
                    accent: item.accent
                )
            }
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: metric.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(nsColor: metric.color))
                    .frame(width: 24, height: 24)
                    .background(Color(nsColor: metric.color).opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(metric.label)
                        .font(.system(size: 13, weight: .semibold))
                    Text(chartSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("", selection: $metric) {
                    ForEach(Metric.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 194)
            }

            ZStack {
                LightStatsChart(
                    points: chartPoints,
                    maxValue: chartUpperBound,
                    barColor: metric.color,
                    showZones: metric == .minutes && WarningSettings.isEnabled,
                    yellow: yellow,
                    red: red
                )
                .frame(height: 190)

                if totalForPeriod == 0 {
                    Text("0 \(metric.totalUnit)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.background, in: Capsule())
                }
            }

            footerRow
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private var footerRow: some View {
        HStack(spacing: 10) {
            Text("\(totalForPeriod.formatted()) \(metric.totalUnit)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: metric.color))
                .monospacedDigit()

            Text(period == .month ? "с 1 числа" : "последние 7 дней")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if metric == .minutes && WarningSettings.isEnabled {
                ZoneLegend(color: Self.zoneYellow, text: "\(yellow) мин")
                ZoneLegend(color: Self.zoneRed, text: "\(red) мин")
            }
        }
    }

    private var storageLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "internaldrive")
                .font(.system(size: 10, weight: .medium))
            Text("Локально • дневная история \(SessionStats.historyRetentionDays) дней")
                .font(.system(size: 10))
        }
        .foregroundStyle(.tertiary)
    }

    private var summaryItems: [SummaryItem] {
        [
            SummaryItem(id: "today", title: "Сегодня", value: todayW, sessions: todayS, seconds: todaySec, accent: todayZoneColor),
            SummaryItem(id: "yesterday", title: "Вчера", value: ydayW, sessions: ydayS, seconds: ydaySec, accent: NSColor.secondaryLabelColor),
            SummaryItem(id: "all", title: "Всего", value: allW, sessions: allS, seconds: allSec, accent: metric.color)
        ]
    }

    private var chartPoints: [ChartPoint] {
        days.enumerated().map { index, item in
            ChartPoint(
                date: item.date,
                value: metric.value(item.stat),
                label: xAxisLabel(for: item.date, index: index)
            )
        }
    }

    private var totalForPeriod: Int {
        days.reduce(0) { $0 + metric.value($1.stat) }
    }

    private var chartUpperBound: Int {
        let maxData = days.map { metric.value($0.stat) }.max() ?? 0
        let zoneMax = metric == .minutes && WarningSettings.isEnabled ? red : 0
        return max(1, Int(Double(max(maxData, zoneMax)) * 1.18))
    }

    private var periodRangeText: String {
        guard let first = days.first?.date, let last = days.last?.date else { return "Нет данных" }
        return "\(Self.shortDateFormatter.string(from: first)) - \(Self.shortDateFormatter.string(from: last))"
    }

    private var chartSubtitle: String {
        period == .month ? "Календарный месяц, с 1 числа" : "Последние 7 дней, включая сегодня"
    }

    private var todayZoneColor: NSColor {
        guard WarningSettings.isEnabled else { return metric.color }
        let minutes = todaySec / 60
        if minutes >= red { return Self.zoneRed }
        if minutes >= yellow { return Self.zoneYellow }
        return Self.zoneGreen
    }

    private func refresh() {
        days = period.load()
        todayW = SessionStats.wordCountToday
        todayS = SessionStats.sessionCountToday
        todaySec = SessionStats.secondsToday
        ydayW = SessionStats.wordCountYesterday
        ydayS = SessionStats.sessionCountYesterday
        ydaySec = SessionStats.secondsYesterday
        allW = SessionStats.wordCount
        allS = SessionStats.sessionCount
        allSec = SessionStats.secondsTotal
        yellow = WarningSettings.yellowMinutes
        red = WarningSettings.redMinutes
    }

    private func xAxisLabel(for date: Date, index: Int) -> String {
        switch period {
        case .week:
            return Self.weekdayFormatter.string(from: date)
        case .month:
            let day = Calendar.current.component(.day, from: date)
            let isLast = index == days.count - 1
            return day == 1 || day % 5 == 0 || isLast ? "\(day)" : ""
        }
    }

    private func sessionsText(_ value: Int) -> String {
        "\(value) \(plural(value, one: "сессия", few: "сессии", many: "сессий"))"
    }

    private func minutesText(_ seconds: Int) -> String {
        "\(seconds / 60) мин"
    }

    private func plural(_ value: Int, one: String, few: String, many: String) -> String {
        let mod10 = value % 10
        let mod100 = value % 100
        if mod10 == 1 && mod100 != 11 { return one }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
        return many
    }

    fileprivate static let zoneGreen = NSColor(calibratedRed: 0.18, green: 0.56, blue: 0.34, alpha: 1)
    fileprivate static let zoneYellow = NSColor(calibratedRed: 0.82, green: 0.48, blue: 0.10, alpha: 1)
    fileprivate static let zoneRed = NSColor(calibratedRed: 0.82, green: 0.18, blue: 0.20, alpha: 1)

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEEE"
        return formatter
    }()
}

private struct SummaryTile: View {
    let title: String
    let value: Int
    let detail: String
    let accent: NSColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(nsColor: accent))
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(value.formatted())
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct ZoneLegend: View {
    let color: NSColor
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(Color(nsColor: color))
                .frame(width: 12, height: 2)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ChartPoint {
    let date: Date
    let value: Int
    let label: String
}

private struct LightStatsChart: NSViewRepresentable {
    let points: [ChartPoint]
    let maxValue: Int
    let barColor: NSColor
    let showZones: Bool
    let yellow: Int
    let red: Int

    func makeNSView(context: Context) -> LightStatsChartView {
        let view = LightStatsChartView()
        view.wantsLayer = true
        view.layerContentsRedrawPolicy = .onSetNeedsDisplay
        return view
    }

    func updateNSView(_ nsView: LightStatsChartView, context: Context) {
        nsView.points = points
        nsView.maxValue = maxValue
        nsView.barColor = barColor
        nsView.showZones = showZones
        nsView.yellow = yellow
        nsView.red = red
        nsView.needsDisplay = true
    }
}

private final class LightStatsChartView: NSView {
    var points: [ChartPoint] = []
    var maxValue = 1
    var barColor = NSColor.systemBlue
    var showZones = false
    var yellow = 0
    var red = 0

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let gridColor = NSColor.separatorColor.withAlphaComponent(0.45)
        let labelColor = NSColor.secondaryLabelColor
        let plot = bounds.insetBy(dx: 0, dy: 0)
        let chartRect = CGRect(
            x: plot.minX + 34,
            y: plot.minY + 8,
            width: max(1, plot.width - 42),
            height: max(1, plot.height - 30)
        )

        drawGrid(in: chartRect, color: gridColor, labelColor: labelColor)

        if showZones {
            drawRule(value: yellow, in: chartRect, color: StatsView.zoneYellow)
            drawRule(value: red, in: chartRect, color: StatsView.zoneRed)
        }

        drawBars(in: chartRect)
        drawXAxis(in: chartRect, labelColor: labelColor)
    }

    private func drawGrid(in rect: CGRect, color: NSColor, labelColor: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: labelColor
        ]

        for index in 0...3 {
            let ratio = CGFloat(index) / 3
            let y = rect.maxY - rect.height * ratio
            let path = NSBezierPath()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.line(to: CGPoint(x: rect.maxX, y: y))
            color.setStroke()
            path.lineWidth = 1
            path.stroke()

            let value = Int((Double(maxValue) * Double(index) / 3).rounded())
            NSString(string: "\(value)").draw(
                in: CGRect(x: 0, y: y - 7, width: 28, height: 14),
                withAttributes: attrs
            )
        }
    }

    private func drawRule(value: Int, in rect: CGRect, color: NSColor) {
        guard value > 0, value <= maxValue else { return }
        let ratio = CGFloat(value) / CGFloat(maxValue)
        let y = rect.maxY - rect.height * ratio
        let path = NSBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.line(to: CGPoint(x: rect.maxX, y: y))
        color.withAlphaComponent(0.72).setStroke()
        path.lineWidth = 1
        path.setLineDash([4, 4], count: 2, phase: 0)
        path.stroke()
    }

    private func drawBars(in rect: CGRect) {
        guard !points.isEmpty else { return }
        let step = rect.width / CGFloat(points.count)
        let barWidth = max(2, min(points.count > 12 ? 7 : 16, step * 0.62))

        for (index, point) in points.enumerated() {
            let ratio = maxValue == 0 ? 0 : CGFloat(point.value) / CGFloat(maxValue)
            let height = point.value == 0 ? 0 : max(2, rect.height * ratio)
            let x = rect.minX + CGFloat(index) * step + (step - barWidth) / 2
            let y = rect.maxY - height
            let barRect = CGRect(x: x, y: y, width: barWidth, height: height)
            guard barRect.height > 0 else { continue }

            let path = NSBezierPath(roundedRect: barRect, xRadius: min(3, barWidth / 2), yRadius: min(3, barWidth / 2))
            barColor.withAlphaComponent(0.86).setFill()
            path.fill()
        }
    }

    private func drawXAxis(in rect: CGRect, labelColor: NSColor) {
        guard !points.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: labelColor
        ]
        let step = rect.width / CGFloat(points.count)

        for (index, point) in points.enumerated() where !point.label.isEmpty {
            let x = rect.minX + CGFloat(index) * step + step / 2 - 12
            NSString(string: point.label).draw(
                in: CGRect(x: x, y: rect.maxY + 8, width: 24, height: 12),
                withAttributes: attrs
            )
        }
    }
}
