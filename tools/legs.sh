#!/bin/bash
# The leg check (see tools/legs/main.swift): every leg, every frame, on
# awkward desktops and in every habitat. Every random draw is seeded, so two
# builds live the same lives frame for frame.
#
#   ./tools/legs.sh [all|desk|hab|flat|<world>…]   this tree
#   ./tools/legs.sh ab [worlds]                    this tree against HEAD (or BASE=<ref>):
#                                                  flat window tops must come out identical,
#                                                  then every world side by side, before > after
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p build
FILES="Math Surfaces WindowTracker Spider Beat Memory SpiderRenderer AppIcon SpiderDesign Skin Prey Toys Traces Habitat HabitatObjects HabitatGeometry HabitatStructures HabitatPieces HabitatNature Studio"

# build <sources dir> <binary>: `Bool.random()` has no seedable overload to
# shadow, so it is swapped for the seeded one in a copy of the sources.
build() {
  local tmp
  tmp="$(mktemp -d)"
  # (Older trees may lack a file; they do not use it either.)
  for f in $FILES; do [ -f "$1/$f.swift" ] || continue; sed -e 's/Bool\.random()/seededBool()/g' "$1/$f.swift" > "$tmp/$f.swift"; done
  # (Trees with shaped furniture — HabitatGeometry.swift — build with SHAPED.)
  local shaped=""
  [ -f "$1/HabitatGeometry.swift" ] && shaped="-DSHAPED"
  xcrun swiftc -O -swift-version 5 $shaped -framework AppKit -o "$2" "$tmp"/*.swift tools/legs/Seeded.swift tools/legs/main.swift
  rm -rf "$tmp"
}

if [ "${1:-}" = "ab" ]; then
  shift
  base="$(mktemp -d)"
  for f in $FILES; do
    git show "${BASE:-HEAD}:Sources/DesktopSpider/$f.swift" > "$base/$f.swift" 2>/dev/null || rm -f "$base/$f.swift"
  done
  build "$base" build/LegsBase &
  build Sources/DesktopSpider build/Legs
  wait
  rm -rf "$base"
  LC_SEEDS="${LC_SEEDS:-24}" LC_DUMP=build/legs-flat-base.txt ./build/LegsBase flat > /dev/null
  LC_SEEDS="${LC_SEEDS:-24}" LC_DUMP=build/legs-flat.txt ./build/Legs flat > /dev/null
  if cmp -s build/legs-flat-base.txt build/legs-flat.txt; then
    echo "flat window tops: identical ($(wc -l < build/legs-flat.txt | tr -d ' ') frames)"
  else
    echo "flat window tops: DIFFER ($(diff build/legs-flat-base.txt build/legs-flat.txt | grep -c '^<') frames)"
  fi
  LC_RUNS="${LC_RUNS:-3}" LC_SECS="${LC_SECS:-60}" ./build/LegsBase "${1:-all}" > build/legs-base.txt &
  LC_RUNS="${LC_RUNS:-3}" LC_SECS="${LC_SECS:-60}" ./build/Legs "${1:-all}" > build/legs.txt
  wait
  ./build/Legs table build/legs-base.txt build/legs.txt
  rm -f build/legs-flat-base.txt build/legs-flat.txt build/legs-base.txt build/legs.txt build/LegsBase
  exit 0
fi

build Sources/DesktopSpider build/Legs
./build/Legs "$@"
