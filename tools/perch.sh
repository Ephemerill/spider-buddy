#!/bin/bash
# The perch check (see tools/perch/main.swift): are the habitat's surfaces
# where its pictures are?
#
#   ./tools/perch.sh sheet out.png                 every kind, its shape over its picture
#   ./tools/perch.sh world <preset> out.png [x w]  a stretch of a ready-made tank
#   ./tools/perch.sh air [preset…]                 planted feet on nothing painted
#   ./tools/perch.sh ab [preset…]                  `air` on HEAD (or BASE=<ref>) and this tree
#   ./tools/perch.sh pieces out.png                every structure piece, its shape and ports
#   ./tools/perch.sh build [prefix]                structures built by snapping, checked (pictures to prefix_*.png)
#   ./tools/perch.sh nature                        the natural world: reach, shelters, the spider on each, supports
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p build
FILES="Math Surfaces WindowTracker Spider Beat Memory SpiderRenderer AppIcon SpiderDesign Skin Prey Toys Traces Habitat HabitatObjects HabitatGeometry HabitatStructures HabitatPieces HabitatNature HabitatArt HabitatItems HabitatPieceArt HabitatHomeArt HabitatNatureArt Studio"

# build <sources dir> <binary>: seeded, as the leg check is (tools/legs).
build() {
  local tmp shaped=""
  tmp="$(mktemp -d)"
  for f in $FILES; do [ -f "$1/$f.swift" ] || continue; sed -e 's/Bool\.random()/seededBool()/g' "$1/$f.swift" > "$tmp/$f.swift"; done
  [ -f "$1/HabitatGeometry.swift" ] && shaped="-DSHAPED"
  xcrun swiftc -O -swift-version 5 $shaped -framework AppKit -o "$2" "$tmp"/*.swift tools/legs/Seeded.swift tools/perch/structures.swift tools/perch/nature.swift tools/perch/main.swift
  rm -rf "$tmp"
}

if [ "${1:-}" = "ab" ]; then
  shift
  base="$(mktemp -d)"
  for f in $FILES; do
    git show "${BASE:-HEAD}:Sources/DesktopSpider/$f.swift" > "$base/$f.swift" 2>/dev/null || rm -f "$base/$f.swift"
  done
  build "$base" build/PerchBase &
  build Sources/DesktopSpider build/Perch
  wait
  rm -rf "$base"
  echo "== before (${BASE:-HEAD})"
  ./build/PerchBase air "$@"
  echo "== after (this tree)"
  ./build/Perch air "$@"
  rm -f build/PerchBase
  exit 0
fi

build Sources/DesktopSpider build/Perch
./build/Perch "$@"
