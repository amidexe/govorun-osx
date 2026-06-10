import SwiftUI

struct StatsPopoverView: View {
    var onOpenSettings: () -> Void = {}

    // Экраны счётчика: тап листает Сегодня → Вчера → Всё время.
    private enum Screen: Int, CaseIterable { case today, yesterday, allTime }
    @State private var screen: Screen = .today

    @State private var sessionCount:      Int = SessionStats.sessionCount
    @State private var wordCount:         Int = SessionStats.wordCount
    @State private var secondsTotal:      Int = SessionStats.secondsTotal
    @State private var sessionCountToday: Int = SessionStats.sessionCountToday
    @State private var wordCountToday:    Int = SessionStats.wordCountToday
    @State private var secondsToday:      Int = SessionStats.secondsToday
    @State private var sessionCountYesterday: Int = SessionStats.sessionCountYesterday
    @State private var wordCountYesterday:    Int = SessionStats.wordCountYesterday
    @State private var secondsYesterday:      Int = SessionStats.secondsYesterday
    @State private var yellowThreshold: Int = WarningSettings.yellowMinutes
    @State private var redThreshold:    Int = WarningSettings.redMinutes

    var body: some View {
        Group {
            switch screen {
            case .today:
                statCard(label: "Сегодня", colored: true,
                         big: wordCountToday.formatted(), unit: "слов",
                         sub: "\(sessionCountToday) сессий · \(mins(secondsToday))")
                    .transition(.opacity)
            case .yesterday:
                statCard(label: "Вчера", colored: false,
                         big: wordCountYesterday > 0 ? wordCountYesterday.formatted() : "–",
                         unit: wordCountYesterday > 0 ? "слов" : "",
                         sub: "\(sessionCountYesterday) сессий · \(mins(secondsYesterday))")
                    .transition(.opacity)
            case .allTime:
                statCard(label: "За всё время", colored: false,
                         big: wordCount > 0 ? wordCount.formatted() : "–",
                         unit: wordCount > 0 ? "слов" : "",
                         sub: "\(sessionCount) сессий · \(mins(secondsTotal))")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: screen)
        .frame(width: 220, height: 100)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { cycleScreen() } }
        .background(.thinMaterial)
        .overlay(alignment: .topTrailing) {
            Button { onOpenSettings() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(.tertiary)
                    .padding(12)
            }
            .buttonStyle(.plain)
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .statsDidUpdate)) { _ in refresh() }
    }

    private func cycleScreen() {
        let all = Screen.allCases
        let next = (screen.rawValue + 1) % all.count
        screen = all[next]
    }

    // Цвет зоны — по минутам речи сегодня (только на экране «Сегодня»).
    private var zoneColor: Color {
        guard WarningSettings.isEnabled else { return .primary }
        let minutes = secondsToday / 60
        if minutes >= redThreshold    { return .red }
        if minutes >= yellowThreshold { return .orange }
        return .primary
    }

    private func statCard(label: String, colored: Bool, big: String, unit: String, sub: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.4)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(big)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(colored ? zoneColor : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(sub)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func mins(_ s: Int) -> String {
        let m = s / 60; return m == 0 ? "< 1 мин" : "\(m) мин"
    }

    private func refresh() {
        sessionCount          = SessionStats.sessionCount
        wordCount             = SessionStats.wordCount
        secondsTotal          = SessionStats.secondsTotal
        sessionCountToday     = SessionStats.sessionCountToday
        wordCountToday        = SessionStats.wordCountToday
        secondsToday          = SessionStats.secondsToday
        sessionCountYesterday = SessionStats.sessionCountYesterday
        wordCountYesterday    = SessionStats.wordCountYesterday
        secondsYesterday      = SessionStats.secondsYesterday
        yellowThreshold       = WarningSettings.yellowMinutes
        redThreshold          = WarningSettings.redMinutes
    }
}
