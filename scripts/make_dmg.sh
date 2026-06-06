#!/bin/bash
set -e

# Имя .app — кириллицей (CFBundleName), но имя DMG-файла — ASCII:
# GitHub Releases не принимает не-ASCII имена ассетов и молча заменяет их на default.dmg.
APP=".build/Build/Products/Debug/Говорун.app"
DMG="govorun.dmg"
STAGING="/tmp/govorun_dmg_stage"
VOLUME="Говорун"

if [ ! -d "$APP" ]; then
    echo "Ошибка: $APP не найден. Сначала запустите make build."
    exit 1
fi

echo "==> Подготавливаю DMG..."
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create \
    -volname "$VOLUME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG"

rm -rf "$STAGING"
echo "==> Готово: $DMG ($(du -sh "$DMG" | cut -f1))"
