#!/bin/bash
# The real ears outside the app: `tools/ears.sh` lists the apps playing
# sound; `tools/ears.sh listen [seconds]` opens the tap and prints what it
# hears (macOS asks the app this runs from for permission the first time).
# SPIDER_EARS_LOG=1 logs the tap's comings and goings.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p build
xcrun swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" -framework AppKit -framework CoreAudio -framework AVFoundation -o build/Ears \
  Sources/DesktopSpider/Math.swift Sources/DesktopSpider/Beat.swift Sources/DesktopSpider/Ears.swift tools/ears/main.swift
./build/Ears "$@"
