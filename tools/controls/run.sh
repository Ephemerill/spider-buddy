#!/bin/bash
# The control gallery with real AppKit on the Mac. Usage: tools/controls/run.sh <out-dir>
# Run as an app bundle: a bare executable cannot become the active app, and AppKit draws an inactive app's controls grey.
set -e
cd "$(dirname "$0")/../.."
APP=build/Controls.app
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/controls" tools/controls/main.swift
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.gabriel.desktopspider.controls</string>
  <key>CFBundleExecutable</key><string>controls</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
OUT="$(cd "$(dirname "${1:-build/controls-mac}")" && pwd)/$(basename "${1:-build/controls-mac}")"
"$APP/Contents/MacOS/controls" "$OUT"
