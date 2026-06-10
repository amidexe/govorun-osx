#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${GOVORUN_PROXY_TEST_CONFIGURATION:-Release}"
APP="${GOVORUN_PROXY_TEST_APP:-$ROOT/.build/Build/Products/${CONFIGURATION}/Говорун.app}"
BIN="$APP/Contents/MacOS/Говорун"

if [[ ! -x "$BIN" ]]; then
    echo "openai proxy smoke failed: app binary is missing: $BIN" >&2
    exit 1
fi

proxy_url="${GOVORUN_OPENAI_PROXY_URL:-}"
if [[ -z "$proxy_url" ]]; then
    proxy_url="$(defaults read com.govorun.app llmProxyURL 2>/dev/null || true)"
fi

if [[ -z "$proxy_url" ]]; then
    echo "openai proxy smoke skipped: set GOVORUN_OPENAI_PROXY_URL or configure LLM proxy in the app"
    exit 0
fi

GOVORUN_OPENAI_PROXY_SELFTEST=1 \
GOVORUN_OPENAI_PROXY_URL="$proxy_url" \
"$BIN"
