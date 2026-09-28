#!/bin/bash
# Draws the app's icon and the .dmg's backdrop from AppArt (AppIcon.swift):
#   Resources/AppIcon.icns          the bundle's icon (build.sh copies it in)
#   Resources/dmg-background.tiff   the .dmg window (tools/release.sh), 1x + 2x
# Previews land in build/art (icon.png, dmg-background.png).
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p build/art Resources
xcrun swiftc -O -swift-version 5 -framework AppKit -o build/Painter \
  Sources/DesktopSpider/AppIcon.swift tools/art/main.swift
./build/Painter build/art >/dev/null
iconutil -c icns build/art/AppIcon.iconset -o Resources/AppIcon.icns
tiffutil -cathidpicheck build/art/dmg-background.png build/art/dmg-background@2x.png \
  -out Resources/dmg-background.tiff 2>/dev/null
echo "Resources/AppIcon.icns, Resources/dmg-background.tiff (previews in build/art)"
