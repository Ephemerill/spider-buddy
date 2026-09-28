#!/bin/bash
# Wraps an app in a .dmg with a dressed window: the backdrop tools/art.sh
# draws (Resources/dmg-background.tiff), the app and an Applications link set
# on it either side of the silk arrow, and the app's icon on the volume.
#
#   tools/dmg.sh <app> <out.dmg> [volume name]
#
# Finder lays the window out (through AppleScript), so the first run asks to
# let the terminal control Finder. tools/release.sh calls this.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$1"
DMG="$2"
VOL="${3:-$(basename "$APP" .app)}"
NAME="$(basename "$APP")"
STAGE="build/dmg-stage"
RW="build/dmg-rw.dmg"
# The window and where the icons sit on it: the same as dmgSize, appSpot and
# appsSpot in tools/art/main.swift.
W=660 H=420 APP_X=180 APPS_X=480 ICON_Y=212
# Finder's bounds take in the title bar (31 points on macOS 26).
TITLE=31

rm -rf "$STAGE" "$RW" "$DMG"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/$NAME"
ln -s /Applications "$STAGE/Applications"
cp Resources/dmg-background.tiff "$STAGE/.background/background.tiff"
cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"

# A writable image first, for Finder to arrange; compressed afterwards.
[ -d "/Volumes/$VOL" ] && hdiutil detach "/Volumes/$VOL" -force -quiet || true
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov -quiet "$RW"
rm -rf "$STAGE"
ATTACH="$(hdiutil attach "$RW" -readwrite -noverify -noautoopen)"
DEV="$(printf '%s\n' "$ATTACH" | awk '/Apple_HFS/ {print $1}')"
MOUNT="$(printf '%s\n' "$ATTACH" | awk -F'\t' '/Apple_HFS/ {print $NF}')"
DISK="$(basename "$MOUNT")"
trap 'hdiutil detach "$DEV" -force -quiet 2>/dev/null || true' EXIT

# The volume wears the app's icon.
SetFile -a C "$MOUNT"

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$DISK"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set pathbar visible of container window to false
    set the bounds of container window to {200, 120, 200 + $W, 120 + $H + $TITLE}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "$NAME" of container window to {$APP_X, $ICON_Y}
    set position of item "Applications" of container window to {$APPS_X, $ICON_Y}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

# Finder writes the layout into .DS_Store in its own time.
for _ in $(seq 1 20); do [ -f "$MOUNT/.DS_Store" ] && break; sleep 0.5; done
[ -f "$MOUNT/.DS_Store" ] || { echo "Finder did not save the window's layout"; exit 1; }
chmod -Rf go-w "$MOUNT" || true
sync
hdiutil detach "$DEV" -quiet
trap - EXIT
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -quiet -o "$DMG"
rm -f "$RW"
