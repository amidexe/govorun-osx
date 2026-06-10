#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-"$ROOT/.build/Build/Products/Debug/Говорун.app"}"
APP_NAME="Говорун"
BUNDLE_ID="com.govorun.app"
SAMPLE_SECONDS="${GOVORUN_SMOKE_SECONDS:-25}"
CPU_LIMIT="${GOVORUN_SMOKE_CPU_LIMIT:-45}"
HIGH_SAMPLE_LIMIT="${GOVORUN_SMOKE_HIGH_SAMPLES:-5}"

if [[ ! -x "$APP/Contents/MacOS/$APP_NAME" ]]; then
    echo "App executable not found: $APP/Contents/MacOS/$APP_NAME" >&2
    exit 1
fi

PID=""

cleanup() {
    launchctl unsetenv GOVORUN_OPEN_SETTINGS_ON_LAUNCH >/dev/null 2>&1 || true
    if [[ -n "$PID" ]] && kill -0 "$PID" >/dev/null 2>&1; then
        kill "$PID" >/dev/null 2>&1 || true
        wait "$PID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
sleep 1

launchctl setenv GOVORUN_OPEN_SETTINGS_ON_LAUNCH 1
open -n "$APP"

for _ in {1..60}; do
    PID="$(pgrep -nx "$APP_NAME" || true)"
    if [[ -n "$PID" ]]; then
        break
    fi
    sleep 0.25
done
launchctl unsetenv GOVORUN_OPEN_SETTINGS_ON_LAUNCH >/dev/null 2>&1 || true

if [[ -z "$PID" ]]; then
    echo "Говорун did not start" >&2
    exit 1
fi

sleep 6

high_samples=0
max_cpu=0

for ((i = 1; i <= SAMPLE_SECONDS; i++)); do
    raw_cpu="$(ps -p "$PID" -o %cpu= || true)"
    cpu="$(awk 'NF { printf "%.0f", $1 }' <<< "$raw_cpu")"
    cpu="${cpu:-0}"

    if (( cpu > max_cpu )); then
        max_cpu="$cpu"
    fi
    if (( cpu > CPU_LIMIT )); then
        high_samples=$((high_samples + 1))
    fi

    if ! kill -0 "$PID" >/dev/null 2>&1; then
        echo "Говорун exited during CPU sampling" >&2
        exit 1
    fi
    sleep 1
done

echo "settings smoke: max_cpu=${max_cpu}%, high_samples=${high_samples}/${SAMPLE_SECONDS}"

if (( high_samples > HIGH_SAMPLE_LIMIT )); then
    echo "CPU stayed above ${CPU_LIMIT}% for too long" >&2
    exit 1
fi

osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null

for _ in {1..40}; do
    if ! kill -0 "$PID" >/dev/null 2>&1; then
        trap - EXIT
        echo "settings smoke: quit ok"
        exit 0
    fi
    sleep 0.25
done

echo "Говорун did not quit after AppleScript quit" >&2
exit 1
