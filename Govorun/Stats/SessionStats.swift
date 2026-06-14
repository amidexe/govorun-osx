import Foundation

/// Статистика за один день. Codable — храним историю по дням в UserDefaults.
struct DayStat: Codable {
    var sessions: Int = 0
    var words:    Int = 0
    var seconds:  Int = 0
}

enum SessionStats {
    private static let d = UserDefaults.standard

    // MARK: - All time

    static var sessionCount: Int {
        get { d.integer(forKey: "statsSessions") }
        set { d.set(newValue, forKey: "statsSessions") }
    }
    static var wordCount: Int {
        get { d.integer(forKey: "statsWords") }
        set { d.set(newValue, forKey: "statsWords") }
    }
    static var secondsTotal: Int {
        get { d.integer(forKey: "statsSeconds") }
        set { d.set(newValue, forKey: "statsSeconds") }
    }

    // MARK: - Daily history (источник для «сегодня», «вчера», текущей недели)

    private static let historyKey  = "statsDailyHistory"

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func key(for date: Date) -> String { dateFmt.string(from: date) }
    private static var todayKey: String { key(for: Date()) }
    private static var yesterdayKey: String {
        key(for: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
    }

    private static func loadHistory() -> [String: DayStat] {
        migrateLegacyIfNeeded()
        guard let data = d.data(forKey: historyKey),
              let dict = try? JSONDecoder().decode([String: DayStat].self, from: data)
        else { return [:] }
        return dict
    }

    private static func saveHistory(_ dict: [String: DayStat]) {
        if let data = try? JSONEncoder().encode(dict) {
            d.set(data, forKey: historyKey)
        }
    }

    private static func stat(forKey key: String) -> DayStat {
        loadHistory()[key] ?? DayStat()
    }

    // MARK: - Today / Yesterday (сброс по дате — будильник не нужен)

    static var sessionCountToday: Int { stat(forKey: todayKey).sessions }
    static var wordCountToday:    Int { stat(forKey: todayKey).words }
    static var secondsToday:      Int { stat(forKey: todayKey).seconds }
    static var minutesToday:      Int { secondsToday / 60 }

    static var sessionCountYesterday: Int { stat(forKey: yesterdayKey).sessions }
    static var wordCountYesterday:    Int { stat(forKey: yesterdayKey).words }
    static var secondsYesterday:      Int { stat(forKey: yesterdayKey).seconds }

    // MARK: - Chart data

    /// Текущая календарная неделя: понедельник → воскресенье.
    static func currentWeekDays() -> [(date: Date, stat: DayStat)] {
        let hist = loadHistory()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let monday = weekStart(for: today, calendar: cal)

        return (0..<7).map { offset in
            let day = cal.date(byAdding: .day, value: offset, to: monday) ?? monday
            return (day, hist[key(for: day)] ?? DayStat())
        }
    }

    static func weekStart(for date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: day) ?? day
    }

    static var currentWeekStat: DayStat {
        aggregate(currentWeekDays())
    }

    private static func aggregate(_ days: [(date: Date, stat: DayStat)]) -> DayStat {
        days.reduce(into: DayStat()) { result, item in
            result.sessions += item.stat.sessions
            result.words += item.stat.words
            result.seconds += item.stat.seconds
        }
    }

    // MARK: - Record

    static func record(text: String, seconds: Int = 0) {
        let words = text.split(separator: " ").count

        sessionCount += 1
        wordCount    += words
        secondsTotal += seconds

        var hist = loadHistory()
        var day  = hist[todayKey] ?? DayStat()
        day.sessions += 1
        day.words    += words
        day.seconds  += seconds
        hist[todayKey] = day
        saveHistory(hist)
    }

    static func reset() {
        for k in ["statsSessions", "statsWords", "statsSeconds"] { d.removeObject(forKey: k) }
        d.removeObject(forKey: historyKey)
        // Легаси-ключи «сегодня» (на случай отката)
        for k in ["statsSessionsToday", "statsWordsToday", "statsSecondsToday", "statsTodayDate"] {
            d.removeObject(forKey: k)
        }
    }

    // MARK: - Миграция легаси «сегодня» → история (однократно)

    private static func migrateLegacyIfNeeded() {
        guard !d.bool(forKey: "statsMigratedV2") else { return }
        d.set(true, forKey: "statsMigratedV2")

        guard let storedDate = d.string(forKey: "statsTodayDate") else { return }
        let s   = d.integer(forKey: "statsSessionsToday")
        let w   = d.integer(forKey: "statsWordsToday")
        let sec = d.integer(forKey: "statsSecondsToday")
        guard s != 0 || w != 0 || sec != 0 else { return }

        var hist: [String: DayStat] = {
            guard let data = d.data(forKey: historyKey),
                  let dict = try? JSONDecoder().decode([String: DayStat].self, from: data)
            else { return [:] }
            return dict
        }()
        if hist[storedDate] == nil {
            hist[storedDate] = DayStat(sessions: s, words: w, seconds: sec)
            if let data = try? JSONEncoder().encode(hist) { d.set(data, forKey: historyKey) }
        }
    }
}
