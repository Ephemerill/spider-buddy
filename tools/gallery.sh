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
  Sources/DesktopSpider/WindowTracker.swift Sources/DesktopSpider/Spider.swift Sources/DesktopSpider/Beat.swift Sources/DesktopSpider/Memory.swift \
  Sources/DesktopSpider/SpiderRenderer.swift Sources/DesktopSpider/AppIcon.swift Sources/DesktopSpider/SpiderDesign.swift Sources/DesktopSpider/Skin.swift Sources/DesktopSpider/Prey.swift Sources/DesktopSpider/Toys.swift Sources/DesktopSpider/Traces.swift Sources/DesktopSpider/Habitat.swift Sources/DesktopSpider/HabitatObjects.swift Sources/DesktopSpider/HabitatGeometry.swift Sources/DesktopSpider/HabitatStructures.swift Sources/DesktopSpider/HabitatPieces.swift Sources/DesktopSpider/HabitatNature.swift Sources/DesktopSpider/HabitatSemantics.swift Sources/DesktopSpider/HabitatKnowledge.swift Sources/DesktopSpider/HabitatPlaces.swift \
  Sources/DesktopSpider/Studio.swift tools/gallery/main.swift
./build/Gallery "${1:-build/studio.png}"
