import SwiftUI

struct StatsPopoverView: View {
    var onOpenSettings: () -> Void = {}

    // Экраны счётчика: тап листает Сегодня → Вчера → Всё время.
    private enum Screen: Int, CaseIterable {
        case today, yesterday, allTime

        var title: String {
            switch self {
            case .today:     return "Сегодня"
            case .yesterday: return "Вчера"
            case .allTime:   return "Всё время"
            }
        }

        var icon: String {
            switch self {
            case .today:     return "calendar"
            case .yesterday: return "clock.arrow.circlepath"
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
    @State private var yellowThreshold = WarningSettings.yellowMinutes
    @State private var redThreshold = WarningSettings.redMinutes

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: screen.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(currentAccent)
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
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(currentAccent)
                .frame(width: 3)
        }
        .animation(.easeInOut(duration: 0.18), value: screen)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .statsDidUpdate)) { _ in refresh() }
    }

    private var pageDots: some View {
        HStack(spacing: 4) {
            ForEach(Screen.allCases, id: \.rawValue) { item in
                Circle()
                    .fill(item == screen ? currentAccent : Color.secondary.opacity(0.22))
                    .frame(width: item == screen ? 6 : 4, height: item == screen ? 6 : 4)
            }
        }
        .frame(width: 28, alignment: .trailing)
    }

    private var currentWords: Int {
        switch screen {
        case .today:     return wordCountToday
        case .yesterday: return wordCountYesterday
        case .allTime:   return wordCount
        }
    }

    private var currentSessions: Int {
        switch screen {
        case .today:     return sessionCountToday
        case .yesterday: return sessionCountYesterday
        case .allTime:   return sessionCount
        }
    }

    private var currentSeconds: Int {
        switch screen {
        case .today:     return secondsToday
        case .yesterday: return secondsYesterday
        case .allTime:   return secondsTotal
        }
    }

    private var currentAccent: Color {
        guard screen == .today else { return Color(red: 0.44, green: 0.48, blue: 0.56) }
        return todayZoneColor
    }

    private var todayZoneColor: Color {
        guard WarningSettings.isEnabled else { return Color(red: 0.18, green: 0.42, blue: 0.92) }
        let minutes = secondsToday / 60
        if minutes >= redThreshold { return Color(red: 0.82, green: 0.18, blue: 0.20) }
        if minutes >= yellowThreshold { return Color(red: 0.82, green: 0.48, blue: 0.10) }
        return Color(red: 0.18, green: 0.56, blue: 0.34)
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
        yellowThreshold = WarningSettings.yellowMinutes
        redThreshold = WarningSettings.redMinutes
    }
}
