import SwiftUI

struct StatsPopoverView: View {
    var onOpenSettings: () -> Void = {}

    @State private var sessionCount:      Int = SessionStats.sessionCount
    @State private var wordCount:         Int = SessionStats.wordCount
    @State private var secondsTotal:      Int = SessionStats.secondsTotal
    @State private var sessionCountToday: Int = SessionStats.sessionCountToday
    @State private var wordCountToday:    Int = SessionStats.wordCountToday
    @State private var secondsToday:      Int = SessionStats.secondsToday
    @State private var showToday             = true
    @State private var yellowThreshold: Int = WarningSettings.yellowSessions
    @State private var redThreshold:    Int = WarningSettings.redSessions

    var body: some View {
        Group {
            if showToday {
                statCard(label: "Сегодня",
                         big: wordCountToday.formatted(),
                         unit: "слов",
                         sub: "\(sessionCountToday) сессий · \(mins(secondsToday))")
                    .transition(.opacity)
            } else {
                statCard(label: "За всё время",
                         big: wordCount > 0 ? wordCount.formatted() : "–",
                         unit: wordCount > 0 ? "слов" : "",
                         sub: "\(sessionCount) сессий · \(mins(secondsTotal))")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showToday)
        .frame(width: 220, height: 100)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { showToday.toggle() } }
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

    private var zoneColor: Color {
        guard WarningSettings.isEnabled else { return .primary }
        if sessionCountToday >= redThreshold    { return .red }
        if sessionCountToday >= yellowThreshold { return .orange }
        return .primary
    }

    private func statCard(label: String, big: String, unit: String, sub: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.4)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(big)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(showToday ? zoneColor : .primary)
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
        sessionCount      = SessionStats.sessionCount
        wordCount         = SessionStats.wordCount
        secondsTotal      = SessionStats.secondsTotal
        sessionCountToday = SessionStats.sessionCountToday
        wordCountToday    = SessionStats.wordCountToday
        secondsToday      = SessionStats.secondsToday
        yellowThreshold   = WarningSettings.yellowSessions
        redThreshold      = WarningSettings.redSessions
    }
}
