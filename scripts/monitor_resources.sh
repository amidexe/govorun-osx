#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${GOVORUN_RESOURCE_APP_NAME:-Говорун}"
BUNDLE_ID="${GOVORUN_RESOURCE_BUNDLE_ID:-com.govorun.app}"
APP_EXECUTABLE="${GOVORUN_RESOURCE_APP_EXECUTABLE:-/Applications/${APP_NAME}.app/Contents/MacOS/${APP_NAME}}"
SAMPLE_SECONDS="${GOVORUN_RESOURCE_SECONDS:-30}"
CPU_LIMIT="${GOVORUN_RESOURCE_CPU_LIMIT:-20}"
HIGH_SAMPLE_LIMIT="${GOVORUN_RESOURCE_HIGH_SAMPLES:-3}"
RSS_LIMIT_MB="${GOVORUN_RESOURCE_RSS_LIMIT_MB:-1000}"
PID="${GOVORUN_RESOURCE_PID:-}"

if [[ -z "$PID" ]]; then
    while read -r candidate; do
        [[ -n "$candidate" ]] || continue
        command_path="$(ps -p "$candidate" -o comm= | sed 's/^ *//')"
        if [[ "$command_path" == "$APP_EXECUTABLE" ]]; then
            PID="$candidate"
            break
        fi
    done < <(pgrep -x "$APP_NAME" || true)
fi

if [[ -z "$PID" ]]; then
    echo "Говорун не запущен по пути $APP_EXECUTABLE: нечего мониторить" >&2
    exit 2
fi

if ! kill -0 "$PID" >/dev/null 2>&1; then
    echo "Процесс $PID не найден" >&2
    exit 2
fi

COMMAND_PATH="$(ps -p "$PID" -o comm= | sed 's/^ *//')"
if [[ "$COMMAND_PATH" != "$APP_EXECUTABLE" ]]; then
    echo "PID $PID не совпадает с ожидаемым приложением: $COMMAND_PATH" >&2
    echo "Ожидалось: $APP_EXECUTABLE" >&2
    exit 2
fi

is_app_busy() {
    local busy busy_pid
    busy="$(defaults read "$BUNDLE_ID" runtimeBusyActive 2>/dev/null || defaults read "$BUNDLE_ID" runtimeRecordingActive 2>/dev/null || echo 0)"
    busy_pid="$(defaults read "$BUNDLE_ID" runtimeBusyPID 2>/dev/null || defaults read "$BUNDLE_ID" runtimeRecordingPID 2>/dev/null || echo "")"
    [[ "$busy" == "1" && ( -z "$busy_pid" || "$busy_pid" == "$PID" ) ]]
}

if is_app_busy; then
    echo "Говорун сейчас занят диктовкой/обработкой; idle-мониторинг пропущен" >&2
    exit 2
fi

high_samples=0
max_cpu=0
sum_cpu=0
samples=0
max_rss_kb=0

for ((i = 1; i <= SAMPLE_SECONDS; i++)); do
    if ! kill -0 "$PID" >/dev/null 2>&1; then
        echo "Говорун завершился во время мониторинга" >&2
        exit 1
    fi
    if is_app_busy; then
        echo "Говорун начал диктовку/обработку во время idle-мониторинга; проверка пропущена" >&2
        exit 2
    fi

    read -r raw_cpu raw_rss < <(ps -p "$PID" -o %cpu= -o rss= | awk 'NF { print $1, $2 }')
    cpu="$(awk 'BEGIN { printf "%.0f", '"${raw_cpu:-0}"' }')"
    rss_kb="${raw_rss:-0}"

    samples=$((samples + 1))
    sum_cpu=$((sum_cpu + cpu))

    if (( cpu > max_cpu )); then
        max_cpu="$cpu"
    fi
    if (( rss_kb > max_rss_kb )); then
        max_rss_kb="$rss_kb"
    fi
    if (( cpu > CPU_LIMIT )); then
        high_samples=$((high_samples + 1))
    fi

    sleep 1
done

avg_cpu=0
if (( samples > 0 )); then
    avg_cpu=$((sum_cpu / samples))
fi
max_rss_mb=$(((max_rss_kb + 1023) / 1024))

echo "idle resource monitor: pid=${PID}, command=${COMMAND_PATH}, avg_cpu=${avg_cpu}%, max_cpu=${max_cpu}%, high_samples=${high_samples}/${SAMPLE_SECONDS}, max_rss=${max_rss_mb}MB"

if (( high_samples > HIGH_SAMPLE_LIMIT )); then
    echo "CPU был выше ${CPU_LIMIT}% слишком долго" >&2
    exit 1
fi

if (( max_rss_mb > RSS_LIMIT_MB )); then
    echo "RSS выше лимита ${RSS_LIMIT_MB}MB" >&2
    exit 1
fi
