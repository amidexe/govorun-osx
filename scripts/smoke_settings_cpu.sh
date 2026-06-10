#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${GOVORUN_SMOKE_CONFIGURATION:-Release}"
APP="${1:-"$ROOT/.build/Build/Products/${CONFIGURATION}/Говорун.app"}"
APP_NAME="Говорун"
BUNDLE_ID="com.govorun.app"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_NAME"
SAMPLE_SECONDS="${GOVORUN_SMOKE_SECONDS:-25}"
CPU_LIMIT="${GOVORUN_SMOKE_CPU_LIMIT:-45}"
HIGH_SAMPLE_LIMIT="${GOVORUN_SMOKE_HIGH_SAMPLES:-5}"
ALLOW_RESTART="${GOVORUN_SMOKE_ALLOW_RESTART:-0}"

if [[ ! -x "$APP_EXECUTABLE" ]]; then
    echo "App executable not found: $APP_EXECUTABLE" >&2
    exit 1
fi

PID=""

matching_pid_for_executable() {
    local expected="$1"
    local candidate command_path
    while read -r candidate; do
        [[ -n "$candidate" ]] || continue
        command_path="$(ps -p "$candidate" -o comm= | sed 's/^ *//')"
        if [[ "$command_path" == "$expected" ]]; then
            echo "$candidate"
            return 0
        fi
    done < <(pgrep -x "$APP_NAME" || true)
    return 1
}

cleanup() {
    launchctl unsetenv GOVORUN_OPEN_SETTINGS_ON_LAUNCH >/dev/null 2>&1 || true
    launchctl unsetenv GOVORUN_DISABLE_HOTKEY_ON_LAUNCH >/dev/null 2>&1 || true
    if [[ -n "$PID" ]] && kill -0 "$PID" >/dev/null 2>&1; then
        kill "$PID" >/dev/null 2>&1 || true
        wait "$PID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

existing_pid="$(matching_pid_for_executable "$APP_EXECUTABLE" || true)"
other_pids=()
while read -r candidate; do
    [[ -n "$candidate" ]] || continue
    command_path="$(ps -p "$candidate" -o comm= | sed 's/^ *//')"
    if [[ "$command_path" != "$APP_EXECUTABLE" ]]; then
        other_pids+=("$candidate:$command_path")
    fi
done < <(pgrep -x "$APP_NAME" || true)

if [[ -n "$existing_pid" || ${#other_pids[@]} -gt 0 ]]; then
    if [[ "$ALLOW_RESTART" != "1" ]]; then
        [[ -n "$existing_pid" ]] && echo "Говорун is already running as PID $existing_pid for $APP_EXECUTABLE." >&2
        if [[ ${#other_pids[@]} -gt 0 ]]; then
            echo "Other Говорун processes are running:" >&2
            printf '  %s\n' "${other_pids[@]}" >&2
        fi
        echo "Set GOVORUN_SMOKE_ALLOW_RESTART=1 to close them for this smoke test." >&2
        exit 2
    fi
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    sleep 1
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

launchctl setenv GOVORUN_OPEN_SETTINGS_ON_LAUNCH 1
launchctl setenv GOVORUN_DISABLE_HOTKEY_ON_LAUNCH 1
open -n "$APP"

for _ in {1..60}; do
    PID="$(matching_pid_for_executable "$APP_EXECUTABLE" || true)"
    if [[ -n "$PID" ]]; then
        break
    fi
    sleep 0.25
done
launchctl unsetenv GOVORUN_OPEN_SETTINGS_ON_LAUNCH >/dev/null 2>&1 || true
launchctl unsetenv GOVORUN_DISABLE_HOTKEY_ON_LAUNCH >/dev/null 2>&1 || true

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
