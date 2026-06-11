#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${GOVORUN_WATCHDOG_TEST_CONFIGURATION:-Release}"
APP="${GOVORUN_WATCHDOG_TEST_APP:-$ROOT/.build/Build/Products/${CONFIGURATION}/Говорун.app}"
BIN="$APP/Contents/MacOS/Говорун"

if [[ ! -x "$BIN" ]]; then
    echo "watchdog sleep/wake regression failed: app binary is missing: $BIN" >&2
    exit 1
fi

GOVORUN_WATCHDOG_SLEEP_SELFTEST=1 "$BIN"
