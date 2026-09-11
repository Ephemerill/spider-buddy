#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p build
xcrun swiftc -O -swift-version 5 -framework AppKit -o build/Film \
  Sources/DesktopSpider/Math.swift Sources/DesktopSpider/Surfaces.swift \
  Sources/DesktopSpider/WindowTracker.swift Sources/DesktopSpider/Spider.swift \
  Sources/DesktopSpider/SpiderRenderer.swift Sources/DesktopSpider/SpiderDesign.swift Sources/DesktopSpider/Prey.swift Sources/DesktopSpider/Studio.swift Sources/DesktopSpider/OverlayWindow.swift tools/film/main.swift
./build/Film "${1:-build/film.png}" "${2:-}" "${3:-}" "${4:-}"
