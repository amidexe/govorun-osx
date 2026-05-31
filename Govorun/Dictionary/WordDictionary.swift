import Foundation

struct WordReplacement: Codable, Identifiable {
    var id:   UUID   = UUID()
    var from: String // может быть несколько вариантов через запятую
    var to:   String // пусто = удалить слово
}

enum WordDictionary {
    private static let key = "wordDictionary"

    static var entries: [WordReplacement] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let list = try? JSONDecoder().decode([WordReplacement].self, from: data) else { return [] }
            return list
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func add(from: String, to: String) {
        var list = entries
        list.append(WordReplacement(from: from, to: to))
        entries = list
    }

    static func update(_ replacement: WordReplacement) {
        var list = entries
        if let i = list.firstIndex(where: { $0.id == replacement.id }) {
            list[i] = replacement
        }
        entries = list
    }

    static func remove(_ replacement: WordReplacement) {
        entries = entries.filter { $0.id != replacement.id }
    }

    // MARK: - Text serialization

    static func toText() -> String {
        entries.map { e in
            e.to.isEmpty ? "\(e.from) =" : "\(e.from) = \(e.to)"
        }.joined(separator: "\n")
    }

    static func fromText(_ text: String) {
        let lines = text.components(separatedBy: .newlines)
        var result: [WordReplacement] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            var parsed = false
            for sep in [" → ", " = "] {
                if let range = trimmed.range(of: sep) {
                    let from = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let to   = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !from.isEmpty { result.append(WordReplacement(from: from, to: to)); parsed = true; break }
                }
            }
            if !parsed, let eqRange = trimmed.range(of: "=") {
                let from = String(trimmed[..<eqRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let to   = String(trimmed[eqRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !from.isEmpty { result.append(WordReplacement(from: from, to: to)) }
            }
        }
        entries = result
    }

    // MARK: - Применяется к тексту до LLM
    static func apply(to text: String) -> String {
        var result = text
        for entry in entries {
            let patterns = entry.from
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for pattern in patterns {
                let escaped = NSRegularExpression.escapedPattern(for: pattern)
                let wordChars = CharacterSet.letters.union(.decimalDigits)
                let isWord = pattern.count > 1 &&
                    pattern.unicodeScalars.allSatisfy { wordChars.contains($0) }
                let regexStr = isWord
                    ? "(?i)(?<![а-яёА-ЯЁa-zA-Z0-9])\(escaped)(?![а-яёА-ЯЁa-zA-Z0-9])"
                    : "(?i)\(escaped)"
                guard let regex = try? NSRegularExpression(pattern: regexStr) else { continue }
                let tpl = NSRegularExpression.escapedTemplate(for: entry.to)
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: tpl)
            }
        }
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
