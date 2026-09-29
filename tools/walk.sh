#!/bin/bash
# The walk harness (see tools/walk/main.swift): films and measures walking on
# a flat window top — bone stretch, reach, planted-foot slip, pops, cadence.
# NAT=1 walks the natural way (Gait.natural). Seeded, like the leg check.
#
#   ./tools/walk.sh strip   frames of one walk   (SC ACT NAT FROM N EVERY SECS SKEL ZOOM COLS OUT)
#   ./tools/walk.sh trace   foot (and, with LEG=n, knee) paths in the world
#   ./tools/walk.sh stats   every size × pace × stance, walk / scurry / sneak
#   ./tools/walk.sh why     frames with a bone off its length or a joint popping (POP, ALL, TIMING)
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p build
FILES="Math Surfaces WindowTracker Spider Beat Memory SpiderRenderer AppIcon SpiderDesign Skin Prey Toys Traces Habitat HabitatObjects HabitatGeometry HabitatStructures HabitatPieces HabitatNature HabitatSemantics HabitatKnowledge HabitatPlaces HabitatEcology Studio"
tmp="$(mktemp -d)"
for f in $FILES; do sed -e 's/Bool\.random()/seededBool()/g' "Sources/DesktopSpider/$f.swift" > "$tmp/$f.swift"; done
xcrun swiftc -O -swift-version 5 -framework AppKit -o build/Walk "$tmp"/*.swift tools/legs/Seeded.swift tools/walk/main.swift
rm -rf "$tmp"
./build/Walk "$@"
