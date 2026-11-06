#!/bin/bash
# Everything the Windows port needs from the Mac that a script can produce,
# in one run. See MAC_HANDOFF.md for what each part is and what is left to do
# by hand (recordings, app screenshots, data files).
#
#   ./tools/capture-all.sh [outdir]            (default: capture)
#   STEPS="manifest rng images" ./tools/capture-all.sh      only some parts
#   SEEDS="1 2 3 4" SCALES="0.95" ./tools/capture-all.sh    fewer traces (a quick first pass)
#
# STEPS (default: all, in this order):
#   manifest   machine, build and git identity
#   rng        random-number fixtures                              (tools/rngprobe.sh)
#   images     every Studio option and a set of poses, as PNGs     (tools/imagedump.sh)
#   tools      the existing tools' pictures and reports            (preview, gallery, film, walk, legs, jerk, smooth, sim, bench, perch, beat, ears, art)
#   traces     scripted pose traces                                (tools/trace.sh)
#   free       the 240 s free run, 8 seeds, state only             (tools/trace.sh)
#
# Run it from a Terminal in a logged-in desktop session (the tools use AppKit
# and the main screen), on the checkout you want as the oracle. Do not run it
# over ssh. It never edits anything under Sources/ or Resources/. It does
# rebuild the binaries in build/ (some of which are tracked by git: that is
# why the instructions say to use a fresh clone).
#
# A step that fails is recorded in STATUS.tsv and the run goes on.
set -uo pipefail
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export SWIFT_DETERMINISTIC_HASHING=1

CAP="${1:-capture}"
STEPS=" ${STEPS:-manifest rng images tools traces free} "
SEEDS="${SEEDS:-1 2 3 42}"            # for the scenarios the brain plays a part in
KIN_SEEDS="${KIN_SEEDS:-1 2}"         # for plain walking (little chance in it)
SCALES="${SCALES:-0.62 0.78 0.95 1.2 1.55}"   # for plain walking: all five sizes
mkdir -p "$CAP"/{tools,traces,rng,images,free}
STATUS="$CAP/STATUS.tsv"
printf 'step\tresult\tseconds\tdetail\n' > "$STATUS"

has() { [[ "$STEPS" == *" $1 "* ]]; }

# run <label> <command...>: log it, time it, record pass or fail, carry on.
run() {
  local label="$1"; shift
  local t0=$SECONDS
  echo "==> $label"
  if "$@" >> "$CAP/capture.log" 2>&1; then
    printf '%s\tok\t%d\t\n' "$label" $((SECONDS - t0)) >> "$STATUS"
  else
    printf '%s\tFAILED\t%d\texit %d\n' "$label" $((SECONDS - t0)) $? >> "$STATUS"
    echo "    FAILED (see $CAP/capture.log)"
  fi
}
# run_to <file> <label> <command...>: as run, with stdout to a file.
run_to() {
  local file="$1"; shift
  local label="$1"; shift
  local t0=$SECONDS
  echo "==> $label"
  if "$@" > "$file" 2>> "$CAP/capture.log"; then
    printf '%s\tok\t%d\t\n' "$label" $((SECONDS - t0)) >> "$STATUS"
  else
    printf '%s\tFAILED\t%d\texit %d\n' "$label" $((SECONDS - t0)) $? >> "$STATUS"
    echo "    FAILED (see $CAP/capture.log)"
  fi
}
# limited <seconds> <command...>: stop a command that listens forever.
limited() {
  local secs="$1"; shift
  "$@" & local pid=$!
  ( sleep "$secs"; kill "$pid" 2>/dev/null ) & local killer=$!
  wait "$pid" 2>/dev/null; local rc=$?
  kill "$killer" 2>/dev/null; wait "$killer" 2>/dev/null
  return 0
}
# Several tools write their pictures to fixed names under build/ whatever the
# argument says. Keep what a run makes: touch a marker, run, copy what is newer.
MARK="$CAP/.marker"
keep_new_pngs() { # <dest dir> <prefix>
  find build -maxdepth 2 -name '*.png' -newer "$MARK" 2>/dev/null | while read -r f; do
    cp "$f" "$1/$2$(basename "$f")"
  done
}
tool() { # <label> <dest dir> <prefix> <command...>: run, then keep new build/*.png
  local label="$1" dest="$2" prefix="$3"; shift 3
  touch "$MARK"; sleep 1
  run "$label" "$@"
  keep_new_pngs "$dest" "$prefix"
}

# ---------------------------------------------------------------- manifest
if has manifest; then
  {
    echo "{"
    echo "  \"capturedAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"repoCommit\": \"$(git rev-parse HEAD 2>/dev/null || echo unknown)\","
    echo "  \"sourcesTree\": \"$(git rev-parse HEAD:Sources 2>/dev/null || echo unknown)\","
    echo "  \"worktreeDirty\": \"$(git status --porcelain Sources Resources 2>/dev/null | head -3 | tr '\n' ';')\","
    echo "  \"appVersion\": \"$(tr -d '[:space:]' < VERSION)\","
    echo "  \"macos\": \"$(sw_vers -productVersion) ($(sw_vers -buildVersion))\","
    echo "  \"machine\": \"$(sysctl -n hw.model 2>/dev/null)\","
    echo "  \"arch\": \"$(uname -m)\","
    echo "  \"swift\": \"$(xcrun swiftc --version 2>&1 | head -1 | sed 's/"/\\"/g')\","
    echo "  \"xcode\": \"$(xcodebuild -version 2>/dev/null | tr '\n' ' ')\","
    echo "  \"displays\": \"$(system_profiler SPDisplaysDataType 2>/dev/null | grep -E 'Resolution|UI Looks like|Display Type' | sed 's/^ *//' | tr '\n' ';' | sed 's/"/\\"/g')\","
    echo "  \"deterministicHashing\": \"$SWIFT_DETERMINISTIC_HASHING\","
    echo "  \"seeds\": \"$SEEDS\","
    echo "  \"scales\": \"$SCALES\","
    echo "  \"traceHour\": \"${TR_HOUR:-14}\""
    echo "}"
  } > "$CAP/MANIFEST.json"
  echo "==> manifest written"
fi

# --------------------------------------------------------------------- rng
if has rng; then
  run_to "$CAP/rng/rng.json" "rngprobe" ./tools/rngprobe.sh
fi

# ------------------------------------------------------------------ images
if has images; then
  run "imagedump" ./tools/imagedump.sh "$CAP/images"
fi

# ------------------------------------------------------------------- tools
if has tools; then
  T="$CAP/tools"
  # Contact sheet, single large pose, draw-radius test.
  tool "preview (contact sheet)" "$T" "preview-" ./tools/preview.sh "$T/contact.png"
  run "preview --single" ./build/Preview "$T/single.png" --single
  run_to "$T/cliptest.txt" "preview --cliptest" ./build/Preview "$T/cliptest.png" --cliptest

  # The Studio gallery at three cell sizes.
  tool "gallery 96" "$T" "gallery-" ./tools/gallery.sh "$T/studio-96.png"
  run "gallery 192" ./build/Gallery "$T/studio-192.png" 192 8
  run "gallery 288" ./build/Gallery "$T/studio-288.png" 288 6

  # Film strips. film.sh builds Film; the modes are then run directly.
  tool "film (edges)" "$T" "film-" ./tools/film.sh "$T/film-edges.png"
  film() { # <label> <args...>
    local label="$1"; shift
    tool "film $label" "$T" "film-$label-" ./build/Film "$T/film-$label.png" "$@"
  }
  film cycle --cycle
  film desk --desk
  film hang --hang
  film swing --swing
  film hammock --hammock
  film jump --jump
  film jump-under --jump --under
  film drop --drop
  film peekaboo --peekaboo
  film thoughts --thoughts
  film hunt-cricket --hunt cricket
  film hunt-worm --hunt worm
  film hunt-fly --hunt fly
  film dance --dance
  film dance-session --dance-session
  film seq --seq walk:2,look:1.5,rest:1.5,walk:2
  film strip-corner --strip corner
  film strip-turn --strip turn
  film strip-peek --strip peek
  for act in walk sneak scurry look rest groom sleep wave startle stretch shake wiggle bounce curious fidget scratch armsUp roll dance glance peer pushup legStretch spin eat watch greet drum stare hop doubleTake sigh; do
    film "strip-$act" --strip "$act" 2
  done

  # Walking measurements. walk.sh writes pictures to $OUT.
  touch "$MARK"; sleep 1
  OUT="$T/walk-strip.png" run_to "$T/walk-strip.txt" "walk strip" ./tools/walk.sh strip
  OUT="$T/walk-trace.png" run_to "$T/walk-trace.txt" "walk trace" ./tools/walk.sh trace
  run_to "$T/walk-stats.txt" "walk stats" ./tools/walk.sh stats
  run_to "$T/walk-why.txt" "walk why" ./tools/walk.sh why

  # Leg quality, with the per-frame joint dump of flat window tops (to diff).
  LC_SEEDS=12 LC_DUMP="$T/legs-flat-dump.txt" run_to "$T/legs-flat.txt" "legs flat" ./tools/legs.sh flat
  LC_RUNS=1 LC_SECS=60 run_to "$T/legs-all.txt" "legs all" ./tools/legs.sh all

  # Jerk, smoothness, the headless sim (three times: some checks are flaky), timing.
  run_to "$T/jerk.txt" "jerk" ./tools/jerk.sh 600 4
  run_to "$T/smooth.txt" "smooth all" ./tools/smooth.sh all
  for i in 1 2 3; do run_to "$T/sim-$i.txt" "sim run $i" ./tools/sim.sh; done
  run_to "$T/bench.txt" "bench" ./tools/bench.sh

  # Habitat: pictures, then the text reports.
  touch "$MARK"; sleep 1
  run "perch sheet" ./tools/perch.sh sheet "$T/perch-sheet.png"
  for p in forestFloor jungleCanopy desertScrub meadow cave beach tundra moonlit empty; do
    run "perch world $p" ./tools/perch.sh world "$p" "$T/perch-world-$p.png"
  done
  run "perch pieces" ./tools/perch.sh pieces "$T/perch-pieces.png"
  run "perch build" ./tools/perch.sh build "$T/perch-build"
  keep_new_pngs "$T" "perch-extra-"
  for m in nature curious places ecology nav chains; do run_to "$T/perch-$m.txt" "perch $m" ./tools/perch.sh "$m"; done
  run_to "$T/perch-air.txt" "perch air" ./tools/perch.sh air

  # Beat tracker (no microphone needed): made-up patterns, tempo changes, mixes.
  # Loops needs Apple Loops installed; songs and speech need files (see MAC_HANDOFF.md).
  for m in synth change mixes loops; do run_to "$T/beat-$m.txt" "beat $m" ./tools/beat.sh "$m"; done
  # The tap's status: which apps are playing sound. Listens until stopped.
  run_to "$T/ears.txt" "ears (15 s)" limited 15 ./tools/ears.sh

  # Icons. NOT tools/art.sh: that overwrites Resources/AppIcon.icns. This builds the
  # painter and writes previews only.
  run "painter build" xcrun swiftc -O -swift-version 5 -framework AppKit -o build/Painter Sources/DesktopSpider/AppIcon.swift tools/art/main.swift
  run "painter run" ./build/Painter "$T/art"
fi

# ------------------------------------------------------------------ traces
if has traces; then
  S=tests/golden/scenarios
  TR_SKIP_BUILD=0 run "trace build" ./tools/trace.sh
  # Does the optimiser change the arithmetic? One scenario, built both ways.
  TR_DEBUG_BUILD=1 LC_SEED=1 TR_SCALE=0.95 run "trace (-Onone) flat-walk" ./tools/trace.sh $S/flat-walk.json "$CAP/traces/flat-walk.s1.0.95.Onone.jsonl"
  # Walking on edges: all five sizes (the spec's leg rule), two seeds.
  for sc in flat-walk window-lap turn-around stop-start carried; do
    for seed in $KIN_SEEDS; do
      for scale in $SCALES; do
        TR_SKIP_BUILD=1 LC_SEED=$seed TR_SCALE=$scale run "trace $sc s$seed $scale" ./tools/trace.sh $S/$sc.json "$CAP/traces/$sc.s$seed.$scale.jsonl"
      done
    done
  done
  # Everything else: one size, more seeds (the brain is random).
  for sc in grab-throw soft-toss hang-swing hang-still jump rappel rappel-sign-flipped climb peekaboo hammock cinema pointer-watch pointer-overhead pointer-whip pointer-stroke pointer-fidget; do
    for seed in $SEEDS; do
      TR_SKIP_BUILD=1 LC_SEED=$seed TR_SCALE=0.95 run "trace $sc s$seed" ./tools/trace.sh $S/$sc.json "$CAP/traces/$sc.s$seed.0.95.jsonl"
    done
  done
  for kind in cricket worm fruitfly moth beetle ant mosquito ladybug; do
    for seed in $SEEDS; do
      TR_SKIP_BUILD=1 LC_SEED=$seed TR_SCALE=0.95 run "trace hunt-$kind s$seed" ./tools/trace.sh $S/hunt-$kind.json "$CAP/traces/hunt-$kind.s$seed.0.95.jsonl"
    done
  done
  for act in walk sneak scurry look rest groom sleep wave startle peek stretch shake wiggle bounce curious fidget scratch armsUp roll dance glance peer pushup legStretch spin eat watch greet drum stare hop fasten groove brace bask doubleTake sigh; do
    TR_SKIP_BUILD=1 TR_ACT=$act LC_SEED=1 TR_SCALE=0.95 run "trace activity $act" ./tools/trace.sh $S/activity.json "$CAP/traces/activity-$act.s1.0.95.jsonl"
  done
fi

# -------------------------------------------------------------------- free
if has free; then
  for seed in 1 2 3 4 5 6 7 8; do
    TR_SKIP_BUILD=1 LC_SEED=$seed TR_SCALE=0.95 run "free-240 s$seed" ./tools/trace.sh tests/golden/scenarios/free-240.json "$CAP/free/free-240.s$seed.jsonl"
  done
fi

rm -f "$MARK"
echo
echo "Done. Results: $STATUS"
column -t -s "$(printf '\t')" "$STATUS" | grep -v ' ok ' || true
echo "Output: $CAP ($(du -sh "$CAP" | cut -f1))"
