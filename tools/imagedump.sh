#!/bin/bash
# Every Studio option and a set of hand-built poses, each as its own PNG, for
# the Windows port to be compared with (see tools/imagedump/main.swift).
#
#   ./tools/imagedump.sh [outdir]       (default build/images)
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export SWIFT_DETERMINISTIC_HASHING=1
mkdir -p build
FILES="Math Surfaces WindowTracker Spider Beat Memory SpiderRenderer AppIcon SpiderDesign Skin Prey Toys Traces Habitat HabitatObjects HabitatGeometry HabitatStructures HabitatPieces HabitatNature HabitatSemantics HabitatKnowledge HabitatPlaces HabitatEcology HabitatNav Studio SpiderLibrary"
SRC=""
for f in $FILES; do [ -f "Sources/DesktopSpider/$f.swift" ] && SRC="$SRC Sources/DesktopSpider/$f.swift"; done
# shellcheck disable=SC2086
xcrun swiftc -O -swift-version 5 -DSHAPED -framework AppKit -o build/ImageDump \
  $SRC tools/trace/Encode.swift tools/imagedump/main.swift
./build/ImageDump "$@"
