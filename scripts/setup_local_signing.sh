#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="${GOVORUN_LOCAL_CODE_SIGN_IDENTITY:-Govorun Local Development}"
KEYCHAIN="${GOVORUN_LOCAL_CODE_SIGN_KEYCHAIN:-$HOME/Library/Keychains/govorun-local-signing.keychain-db}"
PASSWORD_FILE="${GOVORUN_LOCAL_CODE_SIGN_PASSWORD_FILE:-$HOME/Library/Application Support/Govorun/local-signing-password}"

mkdir -p "$(dirname "$KEYCHAIN")" "$(dirname "$PASSWORD_FILE")"

ensure_password() {
    if [[ ! -f "$PASSWORD_FILE" ]]; then
        LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 > "$PASSWORD_FILE"
        chmod 600 "$PASSWORD_FILE"
    fi
    cat "$PASSWORD_FILE"
}

keychain_in_search_list() {
    security list-keychains -d user | tr -d '"' | grep -Fxq "$KEYCHAIN"
}

add_keychain_to_search_list() {
    if keychain_in_search_list; then
        return
    fi

    local existing=()
    while IFS= read -r item; do
        item="$(printf '%s' "$item" | sed -E 's/^[[:space:]]*"?(.*?)"?[[:space:]]*$/\1/')"
        [[ -n "$item" ]] && existing+=("$item")
    done < <(security list-keychains -d user)

    security list-keychains -d user -s "$KEYCHAIN" "${existing[@]}"
}

find_identity() {
    security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null \
        | awk -v name="$IDENTITY_NAME" '$0 ~ name { print $2; exit }'
}

PASSWORD="$(ensure_password)"

if [[ ! -f "$KEYCHAIN" ]]; then
    security create-keychain -p "$PASSWORD" "$KEYCHAIN" >/dev/null
fi

security unlock-keychain -p "$PASSWORD" "$KEYCHAIN" >/dev/null
security set-keychain-settings -lut 21600 "$KEYCHAIN" >/dev/null
add_keychain_to_search_list

if identity_hash="$(find_identity)"; [[ -n "$identity_hash" ]]; then
    echo "local signing identity ready: $identity_hash \"$IDENTITY_NAME\""
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/openssl.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = v3_req
prompt = no

[ dn ]
CN = $IDENTITY_NAME

[ v3_req ]
basicConstraints = critical,CA:TRUE
keyUsage = critical,digitalSignature,keyCertSign
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF

openssl req \
    -newkey rsa:2048 \
    -nodes \
    -keyout "$tmp/key.pem" \
    -x509 \
    -days 3650 \
    -out "$tmp/cert.pem" \
    -config "$tmp/openssl.cnf" >/dev/null 2>&1

openssl pkcs12 \
    -legacy \
    -export \
    -inkey "$tmp/key.pem" \
    -in "$tmp/cert.pem" \
    -out "$tmp/cert.p12" \
    -passout "pass:$PASSWORD" >/dev/null 2>&1

security import "$tmp/cert.p12" \
    -k "$KEYCHAIN" \
    -P "$PASSWORD" \
    -T /usr/bin/codesign >/dev/null

security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$KEYCHAIN" \
    "$tmp/cert.pem" >/dev/null

security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$PASSWORD" \
    "$KEYCHAIN" >/dev/null

identity_hash="$(find_identity)"
if [[ -z "$identity_hash" ]]; then
    echo "Failed to create a valid local code-signing identity in $KEYCHAIN" >&2
    exit 1
fi

echo "local signing identity ready: $identity_hash \"$IDENTITY_NAME\""
