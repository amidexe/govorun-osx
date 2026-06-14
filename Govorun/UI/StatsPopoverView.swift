import SwiftUI

struct StatsPopoverView: View {
    var onOpenSettings: () -> Void = {}

    // Экраны счётчика: тап листает Сегодня → Вчера → Неделя → Всего.
    private enum Screen: Int, CaseIterable {
        case today, yesterday, week, allTime

        var title: String {
            switch self {
            case .today:     return "Сегодня"
            case .yesterday: return "Вчера"
            case .week:      return "Неделя"
            case .allTime:   return "Всего"
            }
        }

        var icon: String {
            switch self {
            case .today:     return "calendar"
            case .yesterday: return "clock.arrow.circlepath"
            case .week:      return "calendar.badge.clock"
            case .allTime:   return "sum"
            }
        }
    }

    @State private var screen: Screen = .today

    @State private var sessionCount = SessionStats.sessionCount
    @State private var wordCount = SessionStats.wordCount
    @State private var secondsTotal = SessionStats.secondsTotal
    @State private var sessionCountToday = SessionStats.sessionCountToday
    @State private var wordCountToday = SessionStats.wordCountToday
    @State private var secondsToday = SessionStats.secondsToday
    @State private var sessionCountYesterday = SessionStats.sessionCountYesterday
    @State private var wordCountYesterday = SessionStats.wordCountYesterday
    @State private var secondsYesterday = SessionStats.secondsYesterday
    @State private var sessionCountWeek = SessionStats.currentWeekStat.sessions
    @State private var wordCountWeek = SessionStats.currentWeekStat.words
    @State private var secondsWeek = SessionStats.currentWeekStat.seconds
    @State private var yellowThreshold = WarningSettings.yellowMinutes
    @State private var redThreshold = WarningSettings.redMinutes

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: screen.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(currentAccent)
                    .shadow(color: currentHalo, radius: currentHaloRadius)
                Text(screen.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { onOpenSettings() } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(currentWords.formatted())
                    .font(.system(size: 29, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(plural(currentWords, one: "слово", few: "слова", many: "слов"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text("\(sessionsText(currentSessions)) • \(minutesText(currentSeconds))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 0)
                pageDots
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(width: 236, height: 116)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { cycleScreen() } }
        .background(GovorunTheme.surface)
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(currentAccent)
                .frame(width: 3)
                .shadow(color: currentHalo, radius: currentHaloRadius, x: 0, y: 0)
        }
        .animation(.easeInOut(duration: 0.18), value: screen)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .statsDidUpdate)) { _ in refresh() }
    }

    private var pageDots: some View {
        HStack(spacing: 4) {
            ForEach(Screen.allCases, id: \.rawValue) { item in
                Circle()
                    .fill(pageDotColor(for: item))
                    .frame(width: item == screen ? 6 : 4, height: item == screen ? 6 : 4)
                    .shadow(
                        color: item == screen ? currentHalo : .clear,
                        radius: item == screen ? currentHaloRadius : 0
                    )
            }
        }
        .frame(width: 36, alignment: .trailing)
    }

    private func pageDotColor(for item: Screen) -> Color {
        if item == screen { return currentAccent }
        return isCalmToday ? Color(nsColor: GovorunTheme.calm).opacity(0.22) : Color.secondary.opacity(0.22)
    }

    private var currentWords: Int {
        switch screen {
        case .today:     return wordCountToday
        case .yesterday: return wordCountYesterday
        case .week:      return wordCountWeek
        case .allTime:   return wordCount
        }
    }

    private var currentSessions: Int {
        switch screen {
        case .today:     return sessionCountToday
        case .yesterday: return sessionCountYesterday
        case .week:      return sessionCountWeek
        case .allTime:   return sessionCount
        }
    }

    private var currentSeconds: Int {
        switch screen {
        case .today:     return secondsToday
        case .yesterday: return secondsYesterday
        case .week:      return secondsWeek
        case .allTime:   return secondsTotal
        }
    }

    private var currentAccent: Color {
        guard screen == .today else { return Color(nsColor: .secondaryLabelColor) }
        return todayZoneColor
    }

    private var currentHalo: Color {
        isCalmToday ? Color(nsColor: GovorunTheme.calmHalo).opacity(0.34) : .clear
    }

    private var currentHaloRadius: CGFloat {
        isCalmToday ? 3 : 0
    }

    private var isCalmToday: Bool {
        screen == .today && todayZone == .green
    }

    private var todayZoneColor: Color {
        switch todayZone {
        case .green:
            return Color(nsColor: GovorunTheme.calm)
        case .yellow:
            return Color(nsColor: GovorunTheme.amber)
        case .red:
            return Color(nsColor: GovorunTheme.red)
        }
    }

    private var todayZone: WarningZone {
        guard WarningSettings.isEnabled else { return .green }
        let minutes = secondsToday / 60
        if minutes >= redThreshold { return .red }
        if minutes >= yellowThreshold { return .yellow }
        return .green
    }

    private func cycleScreen() {
        let all = Screen.allCases
        let next = (screen.rawValue + 1) % all.count
        screen = all[next]
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

    private func refresh() {
        sessionCount = SessionStats.sessionCount
        wordCount = SessionStats.wordCount
        secondsTotal = SessionStats.secondsTotal
        sessionCountToday = SessionStats.sessionCountToday
        wordCountToday = SessionStats.wordCountToday
        secondsToday = SessionStats.secondsToday
        sessionCountYesterday = SessionStats.sessionCountYesterday
        wordCountYesterday = SessionStats.wordCountYesterday
        secondsYesterday = SessionStats.secondsYesterday
        let week = SessionStats.currentWeekStat
        sessionCountWeek = week.sessions
        wordCountWeek = week.words
        secondsWeek = week.seconds
        yellowThreshold = WarningSettings.yellowMinutes
        redThreshold = WarningSettings.redMinutes
    }
}
