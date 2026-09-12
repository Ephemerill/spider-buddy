#!/bin/bash
# Renders every studio option (and a few random designs) into one sheet.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p build
xcrun swiftc -O -swift-version 5 -framework AppKit -o build/Gallery \
  Sources/DesktopSpider/Math.swift Sources/DesktopSpider/Surfaces.swift \
  Sources/DesktopSpider/WindowTracker.swift Sources/DesktopSpider/Spider.swift \
  Sources/DesktopSpider/SpiderRenderer.swift Sources/DesktopSpider/SpiderDesign.swift Sources/DesktopSpider/Prey.swift Sources/DesktopSpider/Habitat.swift \
  Sources/DesktopSpider/Studio.swift tools/gallery/main.swift
./build/Gallery "${1:-build/studio.png}"
