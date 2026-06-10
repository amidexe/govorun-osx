import SwiftUI
import Charts

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
        var color: Color {
            switch self {
            case .words:    return .blue
            case .minutes:  return .orange
            case .sessions: return .green
            }
        }
        func value(_ s: DayStat) -> Int {
            switch self {
            case .words:    return s.words
            case .minutes:  return s.seconds / 60
            case .sessions: return s.sessions
            }
        }
    }

    private enum Period: String, CaseIterable, Identifiable {
        case week, month
        var id: String { rawValue }
        var label: String { self == .week ? "Неделя" : "Месяц" }
        var days: Int { self == .week ? 7 : 30 }
    }

    @State private var metric: Metric = .words
    @State private var period: Period = .week
    @State private var days: [(date: Date, stat: DayStat)] = SessionStats.lastDays(7)

    // Счётчики
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
    @State private var red    = WarningSettings.redMinutes

    var body: some View {
        VStack(spacing: 16) {
            statsBanner

            VStack(spacing: 10) {
                Picker("", selection: $period) {
                    ForEach(Period.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .frame(maxWidth: .infinity)
                .onChange(of: period) { _ in days = SessionStats.lastDays(period.days) }

                Picker("", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .frame(maxWidth: .infinity)

                periodChart
                    .frame(height: 165)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: .statsDidUpdate)) { _ in refresh() }
    }

    // Вся статистика в одном компактном баннере: три колонки.
    // «Сегодня» выделено цветом зоны и крупнее остальных.
    private var statsBanner: some View {
        HStack(spacing: 0) {
            col(title: "Сегодня",   number: todayW, sessions: todayS, seconds: todaySec, color: todayColor, emphasized: true)
            Divider().frame(height: 34)
            col(title: "Вчера",     number: ydayW,  sessions: ydayS,  seconds: ydaySec,  color: .primary, emphasized: false)
            Divider().frame(height: 34)
            col(title: "Всё время", number: allW,   sessions: allS,   seconds: allSec,   color: .primary, emphasized: false)
        }
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.thinMaterial))
    }

    private func col(title: String, number: Int, sessions: Int, seconds: Int, color: Color, emphasized: Bool) -> some View {
        VStack(spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(number.formatted())
                .font(.system(size: emphasized ? 24 : 19, weight: emphasized ? .black : .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("\(sessions) сессий · \(seconds / 60) мин")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }

    private var periodChart: some View {
        Chart {
            ForEach(days, id: \.date) { item in
                BarMark(
                    x: .value("День", item.date, unit: .day),
                    y: .value(metric.label, metric.value(item.stat))
                )
                .foregroundStyle(metric.color.gradient)
                .cornerRadius(period == .week ? 5 : 2)
            }
            if metric == .minutes {
                RuleMark(y: .value("Жёлтая зона", yellow))
                    .foregroundStyle(.yellow)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                RuleMark(y: .value("Красная зона", red))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartXAxis {
            if period == .week {
                AxisMarks(values: days.map(\.date)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            } else {
                AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
        }
    }

    private var todayColor: Color {
        guard WarningSettings.isEnabled else { return .blue }
        let m = todaySec / 60
        if m >= red    { return .red }
        if m >= yellow { return .orange }
        return .blue
    }

    private func refresh() {
        days   = SessionStats.lastDays(period.days)
        todayW = SessionStats.wordCountToday;     todayS = SessionStats.sessionCountToday;     todaySec = SessionStats.secondsToday
        ydayW  = SessionStats.wordCountYesterday; ydayS  = SessionStats.sessionCountYesterday; ydaySec  = SessionStats.secondsYesterday
        allW   = SessionStats.wordCount;          allS   = SessionStats.sessionCount;          allSec   = SessionStats.secondsTotal
        yellow = WarningSettings.yellowMinutes
        red    = WarningSettings.redMinutes
    }
}
