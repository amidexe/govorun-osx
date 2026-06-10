#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Говорун"
BUNDLE_ID="com.govorun.app"
CONFIGURATION="${GOVORUN_INSTALL_CONFIGURATION:-Release}"
SRC_APP="${1:-"$ROOT/.build/Build/Products/${CONFIGURATION}/${APP_NAME}.app"}"
DST_APP="${2:-"/Applications/${APP_NAME}.app"}"
DST_EXEC="${DST_APP}/Contents/MacOS/${APP_NAME}"
ALLOW_RESTART="${GOVORUN_INSTALL_ALLOW_RESTART:-0}"
ALLOW_BUSY_RESTART="${GOVORUN_INSTALL_ALLOW_BUSY_RESTART:-0}"

if [[ ! -x "$SRC_APP/Contents/MacOS/$APP_NAME" ]]; then
    echo "Сборка не найдена: $SRC_APP" >&2
    exit 1
fi

running_pids=()
other_pids=()

while read -r pid; do
    [[ -n "$pid" ]] || continue
    command_path="$(ps -p "$pid" -o comm= | sed 's/^ *//')"
    if [[ "$command_path" == "$DST_EXEC" ]]; then
        running_pids+=("$pid")
    else
        other_pids+=("$pid:$command_path")
    fi
done < <(pgrep -x "$APP_NAME" || true)

is_app_busy() {
    local pid="$1"
    local busy busy_pid
    busy="$(defaults read "$BUNDLE_ID" runtimeBusyActive 2>/dev/null || defaults read "$BUNDLE_ID" runtimeRecordingActive 2>/dev/null || echo 0)"
    busy_pid="$(defaults read "$BUNDLE_ID" runtimeBusyPID 2>/dev/null || defaults read "$BUNDLE_ID" runtimeRecordingPID 2>/dev/null || echo "")"
    [[ "$busy" == "1" && ( -z "$busy_pid" || "$busy_pid" == "$pid" ) ]]
}

if (( ${#running_pids[@]} > 0 )) && [[ "$ALLOW_BUSY_RESTART" != "1" ]]; then
    for pid in "${running_pids[@]}"; do
        if is_app_busy "$pid"; then
            echo "Говорун сейчас пишет или обрабатывает речь: PID $pid." >&2
            echo "Установка остановлена, чтобы не потерять диктовку. Повтори позже, когда запись завершится." >&2
            exit 2
        fi
    done
fi

if (( ${#running_pids[@]} > 0 || ${#other_pids[@]} > 0 )) && [[ "$ALLOW_RESTART" != "1" ]]; then
    if (( ${#running_pids[@]} > 0 )); then
        echo "Установленный Говорун уже запущен: PID ${running_pids[*]} ($DST_EXEC)." >&2
    fi
    if (( ${#other_pids[@]} > 0 )); then
        echo "Найдены другие процессы с именем Говорун:" >&2
        printf '  %s\n' "${other_pids[@]}" >&2
    fi
    echo "Чтобы закрыть их и установить сборку, запусти: GOVORUN_INSTALL_ALLOW_RESTART=1 make install" >&2
    exit 2
fi

if (( ${#running_pids[@]} > 0 || ${#other_pids[@]} > 0 )); then
    echo "==> Закрываю запущенные экземпляры Говоруна..."
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true

    for _ in {1..40}; do
        still_running=0
        for ((i = 0; i < ${#running_pids[@]}; i++)); do
            pid="${running_pids[$i]}"
            kill -0 "$pid" >/dev/null 2>&1 && still_running=1
        done
        for ((i = 0; i < ${#other_pids[@]}; i++)); do
            entry="${other_pids[$i]}"
            pid="${entry%%:*}"
            kill -0 "$pid" >/dev/null 2>&1 && still_running=1
        done
        (( still_running == 0 )) && break
        sleep 0.25
    done

    for ((i = 0; i < ${#running_pids[@]}; i++)); do
        pid="${running_pids[$i]}"
        kill "$pid" >/dev/null 2>&1 || true
    done
    for ((i = 0; i < ${#other_pids[@]}; i++)); do
        entry="${other_pids[$i]}"
        pid="${entry%%:*}"
        kill "$pid" >/dev/null 2>&1 || true
    done
fi

echo "==> Копирую $SRC_APP -> $DST_APP"
rm -rf "$DST_APP"
/usr/bin/ditto "$SRC_APP" "$DST_APP"

echo "==> Проверяю подпись и ресурсы приложения..."
bash "$ROOT/scripts/sign_app.sh" "$DST_APP" >/dev/null
touch "$DST_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$DST_APP" >/dev/null 2>&1 || true

echo "==> Запускаю установленный Говорун..."
open "$DST_APP"
