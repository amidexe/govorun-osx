import Foundation

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

    // MARK: - Today (сброс по дате без будильника)

    private static var today: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
    private static var storedDate: String? { d.string(forKey: "statsTodayDate") }
    private static var isToday: Bool { storedDate == today }

    static var sessionCountToday: Int { isToday ? d.integer(forKey: "statsSessionsToday") : 0 }
    static var wordCountToday:    Int { isToday ? d.integer(forKey: "statsWordsToday")    : 0 }
    static var secondsToday:      Int { isToday ? d.integer(forKey: "statsSecondsToday")  : 0 }

    // MARK: - Record

    static func record(text: String, seconds: Int = 0) {
        let words = text.split(separator: " ").count
        let date  = today
        let fresh = storedDate != date

        sessionCount  += 1
        wordCount     += words
        secondsTotal  += seconds

        d.set(fresh ? 1     : sessionCountToday + 1, forKey: "statsSessionsToday")
        d.set(fresh ? words : wordCountToday + words, forKey: "statsWordsToday")
        d.set(fresh ? seconds : secondsToday + seconds, forKey: "statsSecondsToday")
        d.set(date, forKey: "statsTodayDate")
    }

    static func resetToday() {
        for key in ["statsSessionsToday","statsWordsToday","statsSecondsToday","statsTodayDate"] {
            d.removeObject(forKey: key)
        }
    }

    static func reset() {
        for key in ["statsSessions","statsWords","statsSeconds",
                    "statsSessionsToday","statsWordsToday","statsSecondsToday","statsTodayDate"] {
            d.removeObject(forKey: key)
        }
    }
}
