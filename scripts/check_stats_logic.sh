#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/main.swift" <<'SWIFT'
import Foundation

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!

let formatter = DateFormatter()
formatter.locale = Locale(identifier: "en_US_POSIX")
formatter.timeZone = calendar.timeZone
formatter.dateFormat = "yyyy-MM-dd"

func assertWeekStart(_ input: String, _ expected: String) {
    guard let date = formatter.date(from: input) else {
        fatalError("bad test date \(input)")
    }
    let actual = formatter.string(from: SessionStats.weekStart(for: date, calendar: calendar))
    if actual != expected {
        fatalError("weekStart(\(input)) = \(actual), expected \(expected)")
    }
}

assertWeekStart("2026-06-08", "2026-06-08")
assertWeekStart("2026-06-10", "2026-06-08")
assertWeekStart("2026-06-14", "2026-06-08")
assertWeekStart("2026-06-15", "2026-06-15")

print("stats logic checks: ok")
SWIFT

swiftc "$ROOT/Govorun/Stats/SessionStats.swift" "$TMP_DIR/main.swift" -o "$TMP_DIR/check_stats_logic"
"$TMP_DIR/check_stats_logic"
