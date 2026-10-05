#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Lumo.xcodeproj"
BUILD="$ROOT/build-installer"
DERIVED="$BUILD/DerivedData"
OUT="$ROOT/dist"
APP="$DERIVED/Build/Products/Release/Lumo.app"
DMG_RW="$BUILD/Lumo-rw.dmg"
DMG_FINAL="$OUT/Lumo-Installer.dmg"
VOLUME="Lumo"
BACKGROUND="$ROOT/Installer/dmg-background.png"

printf '\n✨ Lumo — création de l’installateur macOS\n\n'
command -v xcodebuild >/dev/null || { echo "Xcode est requis."; exit 1; }
command -v hdiutil >/dev/null || { echo "hdiutil est requis (macOS)."; exit 1; }
rm -rf "$BUILD" "$OUT"
mkdir -p "$BUILD" "$OUT"

printf '1/4  Compilation Release…\n'
xcodebuild -project "$PROJECT" -scheme Lumo -configuration Release \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build

[ -d "$APP" ] || { echo "Lumo.app introuvable après compilation."; exit 1; }

printf '2/4  Signature locale…\n'
if [ -n "${LUMO_SIGN_IDENTITY:-}" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$LUMO_SIGN_IDENTITY" "$APP"
else
  codesign --force --deep --sign - "$APP"
fi

printf '3/4  Création du disque d’installation…\n'
hdiutil create -quiet -size 420m -fs HFS+ -volname "$VOLUME" "$DMG_RW"
MOUNT_INFO="$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_RW")"
DEVICE="$(echo "$MOUNT_INFO" | awk '/Apple_HFS/ {print $1; exit}')"
MOUNT="/Volumes/$VOLUME"
cleanup() { hdiutil detach "$DEVICE" -quiet 2>/dev/null || true; }
trap cleanup EXIT

cp -R "$APP" "$MOUNT/Lumo.app"
ln -s /Applications "$MOUNT/Applications"
mkdir -p "$MOUNT/.background"
cp "$BACKGROUND" "$MOUNT/.background/background.png"

# Finder layout: app on left, Applications on right, matching the Lumo visual.
osascript <<APPLESCRIPT || true
tell application "Finder"
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {180, 120, 900, 600}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 104
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "Lumo.app" of container window to {210, 305}
    set position of item "Applications" of container window to {510, 305}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$DEVICE" -quiet
trap - EXIT

printf '4/4  Compression du DMG…\n'
hdiutil convert "$DMG_RW" -quiet -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL"
rm -f "$DMG_RW"

printf '\n✅ Installateur créé :\n%s\n' "$DMG_FINAL"
printf '\nOuvre le DMG puis glisse Lumo dans Applications.\n'
