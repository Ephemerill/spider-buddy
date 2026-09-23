#!/bin/bash
# Builds Spider Buddy.app, wraps it in a .dmg, and publishes a GitHub release.
#
#   tools/release.sh            # package build/SpiderBuddy-<VERSION>.dmg
#   tools/release.sh --publish  # ...and create the GitHub release (needs gh)
#
# The version comes from the VERSION file at the repo root; bump it first.
# The in-app "Check for Updates…" compares that number against the newest
# release's tag, so the tag is always "v<VERSION>".
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"
NAME="Spider Buddy"
APP="$NAME.app"
DMG="build/SpiderBuddy-$VERSION.dmg"
VOL="$NAME $VERSION"
STAGE="build/dmg-stage"
REPO="Ephemerill/spider-buddy"

APP_NAME="$NAME" ./build.sh release

echo "==> Packaging $DMG"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"
echo "    $(du -h "$DMG" | cut -f1)  $DMG"

if [ "${1:-}" != "--publish" ]; then
  echo "==> Not publishing (pass --publish to create the GitHub release)"
  exit 0
fi

command -v gh >/dev/null || { echo "gh is not installed: brew install gh"; exit 1; }

if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  echo "==> Release $TAG exists; replacing its .dmg"
  gh release upload "$TAG" "$DMG" --clobber -R "$REPO"
else
  echo "==> Creating release $TAG"
  gh release create "$TAG" "$DMG" -R "$REPO" \
    --title "$NAME $VERSION" \
    --notes "Download the .dmg, open it, and drag Spider Buddy to Applications.

The first launch needs the usual step for an unsigned app: right-click Spider Buddy → Open, or allow it under System Settings → Privacy & Security. After that, **Check for Updates…** in the spider's menu installs newer releases by itself."
fi
echo "==> https://github.com/$REPO/releases/tag/$TAG"
