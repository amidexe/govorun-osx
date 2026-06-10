#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:?usage: scripts/sign_app.sh /path/to/Говорун.app}"
BUNDLE_ID="${GOVORUN_BUNDLE_ID:-com.govorun.app}"
IDENTITY="${GOVORUN_CODE_SIGN_IDENTITY:-}"
ENTITLEMENTS="${GOVORUN_CODE_SIGN_ENTITLEMENTS:-$ROOT/Govorun/Govorun.entitlements}"
LOCAL_IDENTITY_NAME="${GOVORUN_LOCAL_CODE_SIGN_IDENTITY:-Govorun Local Development}"
LOCAL_KEYCHAIN="${GOVORUN_LOCAL_CODE_SIGN_KEYCHAIN:-$HOME/Library/Keychains/govorun-local-signing.keychain-db}"
LOCAL_PASSWORD_FILE="${GOVORUN_LOCAL_CODE_SIGN_PASSWORD_FILE:-$HOME/Library/Application Support/Govorun/local-signing-password}"

if [[ ! -d "$APP/Contents" ]]; then
    echo "App bundle not found: $APP" >&2
    exit 1
fi

find_local_identity() {
    if [[ -f "$LOCAL_KEYCHAIN" && -f "$LOCAL_PASSWORD_FILE" ]]; then
        security unlock-keychain -p "$(cat "$LOCAL_PASSWORD_FILE")" "$LOCAL_KEYCHAIN" >/dev/null 2>&1 || true
        security find-identity -v -p codesigning "$LOCAL_KEYCHAIN" 2>/dev/null \
            | awk -v name="$LOCAL_IDENTITY_NAME" '$0 ~ name { print $2; exit }'
        return
    fi

    security find-identity -v -p codesigning 2>/dev/null \
        | awk -v name="$LOCAL_IDENTITY_NAME" '$0 ~ name { print $2; exit }'
}

if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(find_local_identity)"
    if [[ -z "$IDENTITY" ]]; then
        IDENTITY="-"
    fi
fi

sign_one() {
    local target="$1"
    codesign --force --sign "$IDENTITY" "$target"
}

if [[ -d "$APP/Contents/Frameworks" ]]; then
    while IFS= read -r nested; do
        sign_one "$nested"
    done < <(
        find "$APP/Contents/Frameworks" \
            \( -name '*.framework' -o -name '*.dylib' -o -perm -111 \) \
            -maxdepth 2 -print 2>/dev/null | sort -r
    )
fi

sign_args=(--force --sign "$IDENTITY" --identifier "$BUNDLE_ID")
if [[ -f "$ENTITLEMENTS" ]]; then
    sign_args+=(--entitlements "$ENTITLEMENTS")
fi

codesign "${sign_args[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP" >/dev/null
codesign -dv "$APP" 2>&1 | sed -n '1,12p'
