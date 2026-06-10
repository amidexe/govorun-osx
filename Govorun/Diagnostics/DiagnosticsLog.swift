import Foundation

struct DiagnosticEvent: Codable, Identifiable, Equatable {
    enum Level: String, Codable {
        case info
        case warning
        case error
    }

    let id: UUID
    let date: Date
    let level: Level
    let category: String
    let message: String
}

enum DiagnosticsLog {
    static let didUpdate = Notification.Name("diagnosticsLogDidUpdate")
    static let maxStoredEvents = 200

    private static let key = "diagnosticsEvents"
    private static let duplicateWindow: TimeInterval = 60
    private static let lock = NSLock()

    static func record(
        _ message: String,
        category: String,
        level: DiagnosticEvent.Level = .info
    ) {
        let cleanMessage = sanitize(message)
        let cleanCategory = sanitize(category, maxLength: 80)
        guard !cleanMessage.isEmpty, !cleanCategory.isEmpty else { return }

        var shouldPost = false
        lock.lock()
        var events = loadUnlocked()
        if let last = events.last,
           last.category == cleanCategory,
           last.message == cleanMessage,
           last.level == level,
           Date().timeIntervalSince(last.date) < duplicateWindow {
            lock.unlock()
            return
        }

        events.append(
            DiagnosticEvent(
                id: UUID(),
                date: Date(),
                level: level,
                category: cleanCategory,
                message: cleanMessage
            )
        )
        if events.count > maxStoredEvents {
            events.removeFirst(events.count - maxStoredEvents)
        }
        saveUnlocked(events)
        shouldPost = true
        lock.unlock()

        if shouldPost {
            NotificationCenter.default.post(name: didUpdate, object: nil)
        }
    }

    static func all() -> [DiagnosticEvent] {
        lock.lock()
        let events = loadUnlocked()
        lock.unlock()
        return events
    }

    static func clear() {
        lock.lock()
        UserDefaults.standard.removeObject(forKey: key)
        lock.unlock()
        NotificationCenter.default.post(name: didUpdate, object: nil)
    }

    static func textDump() -> String {
        let formatter = ISO8601DateFormatter()
        return all()
            .map { event in
                "\(formatter.string(from: event.date)) [\(event.level.rawValue)] \(event.category): \(event.message)"
            }
            .joined(separator: "\n")
    }

    private static func loadUnlocked() -> [DiagnosticEvent] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([DiagnosticEvent].self, from: data)) ?? []
    }

    private static func saveUnlocked(_ events: [DiagnosticEvent]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func sanitize(_ value: String, maxLength: Int = 500) -> String {
        var result = value.replacingOccurrences(of: "\n", with: " ")
        result = result.replacingOccurrences(of: "\r", with: " ")
        result = result.replacingOccurrences(
            of: #"sk-[A-Za-z0-9_\-]{12,}"#,
            with: "sk-<hidden>",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"AIza[A-Za-z0-9_\-]{20,}"#,
            with: "AIza<hidden>",
            options: .regularExpression
        )
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.count > maxLength {
            result = String(result.prefix(maxLength)) + "…"
        }
        return result
    }
}
