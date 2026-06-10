#!/bin/bash
set -euo pipefail

# Имя .app — кириллицей (CFBundleName), но имя DMG-файла — ASCII:
# GitHub Releases не принимает не-ASCII имена ассетов и молча заменяет их на default.dmg.
CONFIGURATION="${GOVORUN_DMG_CONFIGURATION:-${CONFIGURATION:-Release}}"
APP="${GOVORUN_DMG_APP:-.build/Build/Products/${CONFIGURATION}/Говорун.app}"
DMG="${GOVORUN_DMG_OUTPUT:-dist/govorun.dmg}"
STAGING="/tmp/govorun_dmg_stage"
VOLUME="Говорун"

if [ ! -d "$APP" ]; then
    echo "Ошибка: $APP не найден. Сначала запустите make build."
    exit 1
fi

echo "==> Подготавливаю DMG..."
rm -rf "$STAGING"
mkdir -p "$STAGING"
/usr/bin/ditto "$APP" "$STAGING/Говорун.app"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$(dirname "$DMG")"
rm -f "$DMG"
hdiutil create \
    -volname "$VOLUME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG"

rm -rf "$STAGING"
echo "==> Готово: $DMG ($(du -sh "$DMG" | cut -f1))"
