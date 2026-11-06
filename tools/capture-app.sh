#!/bin/bash
# Screenshots and timing text from the REAL app, using its built-in test hooks
# (SPIDER_*_SHOT and friends in AppDelegate.swift). Each hook opens a window,
# writes pictures to a folder, and quits the app.
#
#   ./tools/capture-app.sh [outdir]          (default: capture/app)
#
# Needs the app built (./build.sh makes spiders.app; it fetches Sparkle the first
# time, so it needs the network once). Quit any running copy first.
#
# The hooks read the app's saved settings, so for repeatable pictures this
# runs the app against an empty settings domain and empty spider and habitat
# libraries, and puts your real settings back afterwards. Your settings are
# copied to ~/Desktop/spider-prefs-backup.plist first. If anything goes wrong,
# restore with:  defaults import com.gabriel.desktopspider ~/Desktop/spider-prefs-backup.plist
#
# The panel hook draws the dark panel only (AppDelegate.swift passes dark: true).
# For the light panel, PANEL_LIGHT=1 rebuilds from a temporary copy of the
# source with dark: false (the working tree is not touched).
set -uo pipefail
cd "$(dirname "$0")/.."
CAP="${1:-capture/app}"
mkdir -p "$CAP"/{panel-dark,panel-light,studio,studio-custom,studio-voice,welcome,bug,habitat,weather,habitat-tour,entrance}
ID=com.gabriel.desktopspider
APP="${APP:-spiders.app}"
BIN="$APP/Contents/MacOS/DesktopSpider"
[ -x "$BIN" ] || { echo "build the app first: ./build.sh  (makes spiders.app)"; exit 1; }
if pgrep -x DesktopSpider >/dev/null; then echo "quit the running Spider Buddy first"; exit 1; fi

PREFS="$HOME/Library/Preferences/$ID.plist"
BACKUP="$HOME/Desktop/spider-prefs-backup.plist"
[ -f "$PREFS" ] && cp "$PREFS" "$BACKUP" && echo "settings backed up to $BACKUP"
restore() { [ -f "$BACKUP" ] && defaults import "$ID" "$BACKUP" && echo "settings restored"; }
trap restore EXIT

fresh() { # a clean settings domain: welcomed, so no welcome window gets in the way
  defaults delete "$ID" 2>/dev/null || true
  killall cfprefsd 2>/dev/null || true
  defaults write "$ID" welcomed -bool true
  defaults write "$ID" askedToSeePages -bool true
}
export SPIDER_LIBRARY="$PWD/$CAP/.lib-spiders" SPIDER_HABITAT_LIBRARY="$PWD/$CAP/.lib-habitats"
mkdir -p "$SPIDER_LIBRARY" "$SPIDER_HABITAT_LIBRARY"

hook() { # <label> <app binary> then env settings come from the caller
  echo "==> $1"
  shift
  "$@" > /dev/null 2>> "$CAP/capture-app.log" || echo "    (exit $?)"
}

fresh
SPIDER_PANEL_SHOT="$PWD/$CAP/panel-dark" hook "panel (dark)" "./$BIN"

if [ "${PANEL_LIGHT:-}" = "1" ]; then
  tmp="$(mktemp -d)"; cp -R Sources "$tmp/Sources"; cp -R tools "$tmp/tools"; cp -R Resources "$tmp/Resources"; cp -R Extension "$tmp/Extension"; cp VERSION build.sh "$tmp/" 2>/dev/null
  sed -i '' 's/page: i, dark: true/page: i, dark: false/' "$tmp/Sources/DesktopSpider/AppDelegate.swift"
  ( cd "$tmp" && APP_NAME=spiders-light ./build.sh >/dev/null 2>&1 )
  fresh
  SPIDER_PANEL_SHOT="$PWD/$CAP/panel-light" hook "panel (light)" "$tmp/spiders-light.app/Contents/MacOS/DesktopSpider"
  rm -rf "$tmp"
fi

fresh; SPIDER_STUDIO_SHOT="$PWD/$CAP/studio" hook "studio, 12 tabs" "./$BIN"
fresh; SPIDER_STUDIO_SHOT="$PWD/$CAP/studio-custom" SPIDER_STUDIO_SHOT_CUSTOM=1 hook "studio, hand-shaping" "./$BIN"
for v in pictures phrases intelligence; do
  mkdir -p "$CAP/studio-voice/$v"
  fresh; SPIDER_STUDIO_SHOT="$PWD/$CAP/studio-voice/$v" SPIDER_STUDIO_SHOT_VOICE=$v hook "studio, thoughts tab: $v" "./$BIN"
done
fresh; SPIDER_WELCOME_SHOT="$PWD/$CAP/welcome" hook "welcome pages" "./$BIN"
fresh; SPIDER_BUG_SHOT="$PWD/$CAP/bug" hook "bug report" "./$BIN"
fresh; SPIDER_HABITAT_SHOT="$PWD/$CAP/habitat" hook "habitat shots" "./$BIN"
fresh; SPIDER_WEATHER_SHOT="$PWD/$CAP/weather" hook "habitat weather, every kind and biome" "./$BIN"
fresh; SPIDER_HABITAT_TOUR="$PWD/$CAP/habitat-tour" hook "habitat tours, weather panel, My Habitats" "./$BIN"

# The first entrance: the spider's position every quarter second, as text.
fresh
echo "==> first entrance (positions)"
SPIDER_ENTRANCE_TEST=8 "./$BIN" > "$CAP/entrance/entrance-positions.txt" 2>> "$CAP/capture-app.log" || true

# Timing meters of the real app: per-second frame meter and per-phase times, 30 s idle.
fresh
echo "==> frame meter, 30 s (idle)"
( SPIDER_FRAMES=1 SPIDER_TIMING=1 SPIDER_STATS=1 "./$BIN" > "$CAP/frames-idle.txt" 2>&1 & p=$!; sleep 35; kill $p 2>/dev/null ) || true

# The panel / studio / habitat open times.
fresh
echo "==> open timing"
( SPIDER_OPEN_TIMING=1 SPIDER_STUDIO=1 "./$BIN" > "$CAP/open-timing.txt" 2>&1 & p=$!; sleep 15; kill $p 2>/dev/null ) || true

echo
echo "Done: $CAP"
find "$CAP" -name '*.png' | wc -l | xargs echo "pictures:"
