#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${GOVORUN_INSTALL_SAFETY_APP_NAME:-Говорун}"
BUNDLE_ID="${GOVORUN_INSTALL_SAFETY_BUNDLE_ID:-com.govorun.app}"
APP_EXECUTABLE="${GOVORUN_INSTALL_SAFETY_APP_EXECUTABLE:-/Applications/${APP_NAME}.app/Contents/MacOS/${APP_NAME}}"
CONFIGURATION="${GOVORUN_INSTALL_SAFETY_CONFIGURATION:-Release}"
SRC_APP="${GOVORUN_INSTALL_SAFETY_SRC_APP:-"$ROOT/.build/Build/Products/${CONFIGURATION}/${APP_NAME}.app"}"

pid=""
while read -r candidate; do
    [[ -n "$candidate" ]] || continue
    command_path="$(ps -p "$candidate" -o comm= | sed 's/^ *//')"
    if [[ "$command_path" == "$APP_EXECUTABLE" ]]; then
        pid="$candidate"
        break
    fi
done < <(pgrep -x "$APP_NAME" || true)

if [[ -z "$pid" ]]; then
    echo "install safety check skipped: installed Говорун is not running" >&2
    exit 2
fi

if [[ ! -x "$SRC_APP/Contents/MacOS/$APP_NAME" ]]; then
    echo "install safety check skipped: build app not found at $SRC_APP" >&2
    exit 2
fi

old_busy="$(defaults read "$BUNDLE_ID" runtimeBusyActive 2>/dev/null || echo 0)"
old_pid="$(defaults read "$BUNDLE_ID" runtimeBusyPID 2>/dev/null || echo "")"

restore_state() {
    if [[ "$old_busy" == "1" || "$old_busy" == "true" || "$old_busy" == "TRUE" || "$old_busy" == "YES" ]]; then
        defaults write "$BUNDLE_ID" runtimeBusyActive -bool true >/dev/null 2>&1 || true
    else
        defaults write "$BUNDLE_ID" runtimeBusyActive -bool false >/dev/null 2>&1 || true
    fi
    if [[ -n "$old_pid" ]]; then
        defaults write "$BUNDLE_ID" runtimeBusyPID -int "$old_pid" >/dev/null 2>&1 || true
    else
        defaults delete "$BUNDLE_ID" runtimeBusyPID >/dev/null 2>&1 || true
    fi
}
trap restore_state EXIT

defaults write "$BUNDLE_ID" runtimeBusyActive -bool true
defaults write "$BUNDLE_ID" runtimeBusyPID -int "$pid"

set +e
output="$(
    GOVORUN_INSTALL_ALLOW_RESTART=1 \
        bash "$ROOT/scripts/install_app.sh" "$SRC_APP" "/Applications/${APP_NAME}.app" 2>&1
)"
status=$?
set -e

if [[ "$status" -ne 2 ]]; then
    echo "$output" >&2
    echo "install safety check failed: install_app.sh returned $status, expected 2" >&2
    exit 1
fi

if ! grep -q "Установка остановлена" <<< "$output"; then
    echo "$output" >&2
    echo "install safety check failed: busy refusal message was not found" >&2
    exit 1
fi

if ! kill -0 "$pid" >/dev/null 2>&1; then
    echo "$output" >&2
    echo "install safety check failed: Говорун PID $pid was stopped" >&2
    exit 1
fi

current_path="$(ps -p "$pid" -o comm= | sed 's/^ *//')"
if [[ "$current_path" != "$APP_EXECUTABLE" ]]; then
    echo "install safety check failed: PID $pid changed executable: $current_path" >&2
    exit 1
fi

echo "install safety check: ok"
