#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHERPA_DIR="$ROOT/Frameworks/sherpa-onnx.xcframework/macos-arm64_x86_64"
MODEL_DIR="${GOVORUN_MODEL_DIR:-$ROOT/Govorun/Resources/Model}"
AUDIO_FILE="${1:-}"

if [[ -z "$AUDIO_FILE" ]]; then
    AUDIO_FILE="$(find /var/folders /tmp -type f -name 'govorun_*.wav' 2>/dev/null | xargs ls -t 2>/dev/null | head -1 || true)"
fi

if [[ -z "$AUDIO_FILE" || ! -f "$AUDIO_FILE" ]]; then
    echo "usage: $0 /path/to/audio.wav [threads...]" >&2
    exit 2
fi

shift $(( $# > 0 ? 1 : 0 ))

BIN="${TMPDIR:-/tmp}/govorun-gigaam-bench"
xcrun swiftc -O \
    -I "$SHERPA_DIR/Headers" \
    "$ROOT/scripts/benchmark_gigaam_threads.swift" \
    "$SHERPA_DIR/libsherpa-onnx.a" \
    -lc++ \
    -o "$BIN"

"$BIN" "$MODEL_DIR" "$AUDIO_FILE" "$@"
