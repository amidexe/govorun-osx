#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${GOVORUN_KEYCHAIN_TEST_CONFIGURATION:-Release}"
APP="${GOVORUN_KEYCHAIN_TEST_APP:-$ROOT/.build/Build/Products/${CONFIGURATION}/Говорун.app}"
BIN="$APP/Contents/MacOS/Говорун"

if [[ ! -x "$BIN" ]]; then
    echo "keychain regression failed: app binary is missing: $BIN" >&2
    exit 1
fi

GOVORUN_KEYCHAIN_SELFTEST=1 "$BIN"
