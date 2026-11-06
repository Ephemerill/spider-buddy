#!/bin/bash
# The pose trace exporter (see tools/trace/main.swift): runs the real Spider
# through a scripted scenario and writes one JSON line per frame, to be
# compared with the Windows port's.
#
#   ./tools/trace.sh <scenario.json> <out.jsonl>
#
#   LC_SEED=1 TR_SCALE=0.95 TR_HOUR=14 ./tools/trace.sh tests/golden/scenarios/flat-walk.json out.jsonl
#   TR_DEBUG_BUILD=1 ...   builds without optimisation (-Onone): a trace from this
#                          and one from the normal build must be identical,
#                          which shows the optimiser did not fuse arithmetic
#                          (a difference would come from it, not the logic)
#
# Like tools/legs.sh, every random draw is seeded (tools/legs/Seeded.swift) and
# `Bool.random()` is swapped for the seeded one in a copy of the sources. The
# two calendar-hour reads are swapped for TR_HOUR (tools/trace/Hour.swift).
# Set SWIFT_DETERMINISTIC_HASHING=1 too: Swift otherwise orders Set and
# Dictionary differently every run.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export SWIFT_DETERMINISTIC_HASHING=1
export TR_COMMIT="${TR_COMMIT:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
mkdir -p build

FILES="Math Surfaces WindowTracker Spider Beat Memory SpiderRenderer AppIcon SpiderDesign Skin Prey Toys Traces Habitat HabitatObjects HabitatGeometry HabitatStructures HabitatPieces HabitatNature HabitatSemantics HabitatKnowledge HabitatPlaces HabitatEcology HabitatNav Studio"
OPT="-O"
BIN="build/Trace"
if [ "${TR_DEBUG_BUILD:-}" = "1" ]; then OPT="-Onone"; BIN="build/TraceDebug"; fi
export TR_BUILD="$OPT $(xcrun swiftc --version | head -1)"

# TR_SKIP_BUILD=1 reuses an existing binary (tools/capture-all.sh builds once, runs many).
if [ "${TR_SKIP_BUILD:-}" != "1" ] || [ ! -x "$BIN" ]; then
  tmp="$(mktemp -d)"
  for f in $FILES; do
    [ -f "Sources/DesktopSpider/$f.swift" ] || continue
    sed -e 's/Bool\.random()/seededBool()/g' \
        -e 's/Calendar\.current\.component(\.hour, from: Date())/traceHour/g' \
        "Sources/DesktopSpider/$f.swift" > "$tmp/$f.swift"
  done
  if grep -q 'Calendar.current.component(.hour' "$tmp"/*.swift; then
    echo "warning: a calendar-hour read was not replaced; the trace will depend on the time of day" >&2
  fi
  xcrun swiftc $OPT -swift-version 5 -DSHAPED -framework AppKit -o "$BIN" \
    "$tmp"/*.swift tools/legs/Seeded.swift tools/trace/Hour.swift tools/trace/Encode.swift tools/trace/main.swift
  rm -rf "$tmp"
fi
[ "$#" -gt 0 ] || exit 0   # (build only)
"./$BIN" "$@"
