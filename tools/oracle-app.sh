#!/bin/bash
# Builds the oracle Mac app: the Mac's own sources at the pinned version, as build.sh builds them, but with its own
# bundle id (com.gabriel.desktopspider.oracle), so its settings and support folder are its own and the owner's spider is
# never touched. Sparkle is left out: Updater.swift is swapped for src/SwiftWin/Updater.swift, the same stand-in the
# Windows build uses, so the two sides match there too. Output: build/oracle/Spider Oracle.app
#   tools/oracle-app.sh            build
#   tools/oracle-app.sh run ENV=.. [-- args]   run it with environment settings (and arguments), waiting for it to quit
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=build/oracle
APP="$OUT/Spider Oracle.app"
if [ "${1:-}" = "run" ]; then
  shift
  envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  env SWIFT_DETERMINISTIC_HASHING=1 ${envs[@]+"${envs[@]}"} "$APP/Contents/MacOS/DesktopSpider" "$@"
  exit
fi
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p "$OUT"
SRC=$(ls Sources/DesktopSpider/*.swift | grep -v '/Updater.swift$')
echo "==> Compiling the oracle  [$(xcrun swiftc --version 2>&1 | head -1)]"
# shellcheck disable=SC2086
xcrun swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
  -framework AppKit -framework QuartzCore -framework ServiceManagement -framework IOKit \
  -o "$OUT/DesktopSpider" $SRC src/SwiftWin/Updater.swift
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT/DesktopSpider" "$APP/Contents/MacOS/DesktopSpider"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
ditto Extension "$APP/Contents/Resources/Extension"
VERSION="$(tr -d '[:space:]' < VERSION)"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Spider Buddy</string>
  <key>CFBundleDisplayName</key><string>Spider Buddy</string>
  <key>CFBundleIdentifier</key><string>com.gabriel.desktopspider.oracle</string>
  <key>CFBundleExecutable</key><string>DesktopSpider</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true
echo "==> Done: $APP"
