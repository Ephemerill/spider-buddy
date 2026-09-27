#!/bin/bash
# Builds Spider Buddy.app, wraps it in a .dmg, writes the Sparkle appcast,
# and publishes a GitHub release.
#
#   tools/release.sh                     # package build/SpiderBuddy-<VERSION>.dmg + build/appcast.xml
#   tools/release.sh --publish           # ...create the GitHub release with the .dmg,
#                                        # then put the appcast on GitHub Pages
#   NOTES=notes.md tools/release.sh --publish   # the same, with a "What's new"
#   tools/release.sh --appcast           # rewrite and re-publish the appcast of the
#                                        # current VERSION's release, after its notes
#                                        # were edited (gh release edit --notes)
#
# The version comes from the VERSION file at the repo root; bump it first.
# The tag is always "v<VERSION>".
#
# The app finds updates through the appcast GitHub Pages serves from the
# repo's gh-pages branch (https://ephemerill.github.io/spider-buddy/appcast.xml,
# SUFeedURL in build.sh). Publishing commits the new appcast.xml straight to
# that branch through the GitHub API; the local checkout is not touched. Pages
# serves it within ~10 minutes (a build, then its cache). The appcast goes up only after the .dmg
# it points at is on the release. The .dmg and
# the appcast are signed with the Sparkle EdDSA key in this Mac's keychain
# (made once with build/Sparkle/bin/generate_keys); SPARKLE_KEY_FILE=<file>
# uses an exported copy instead. Lose that key and installed copies can never
# be updated again, so keep a backup (generate_keys -x <file>).
#
# The release notes shown in the update window are the release's notes up to
# the "<!-- install -->" marker; the install instructions after it are for
# people downloading by hand. Versions before 0.8.0 update themselves by
# fetching the release's .dmg, so there must only be one .dmg attached.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"
NAME="Spider Buddy"
APP="$NAME.app"
DMG="build/SpiderBuddy-$VERSION.dmg"
APPCAST="build/appcast.xml"
VOL="$NAME $VERSION"
STAGE="build/dmg-stage"
REPO="Ephemerill/spider-buddy"
MODE="${1:-}"
MARKER="<!-- install -->"

SPARKLE_BIN="$(tools/sparkle.sh)/bin"
KEY_ARGS=()
[ -n "${SPARKLE_KEY_FILE:-}" ] && KEY_ARGS=(--ed-key-file "$SPARKLE_KEY_FILE")

need_gh() {
  command -v gh >/dev/null || { echo "gh is not installed: brew install gh"; exit 1; }
}

# The appcast for this version's .dmg, with $1 (markdown) as its notes.
write_appcast() {
  local notes="$1" sig archs hw="" description=""
  sig="$("$SPARKLE_BIN/sign_update" ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} "$DMG")"
  case "$sig" in *sparkle:edSignature=*) ;; *) echo "sign_update failed: $sig"; exit 1 ;; esac
  archs="$(lipo -archs "$APP/Contents/MacOS/DesktopSpider")"
  [ "$archs" = "arm64" ] && hw="
      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>"
  if [ -n "$notes" ]; then
    # CDATA can't hold "]]>"; split it across two sections.
    description="
      <description sparkle:format=\"markdown\"><![CDATA[${notes//]]>/]]]]><![CDATA[>}]]></description>"
  fi
  cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$NAME</title>
    <link>https://github.com/$REPO/releases</link>
    <item>
      <title>$NAME $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>$hw
      <sparkle:fullReleaseNotesLink>https://github.com/$REPO/releases/tag/$TAG</sparkle:fullReleaseNotesLink>$description
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/$(basename "$DMG")" type="application/octet-stream" $sig/>
    </item>
  </channel>
</rss>
XML
  # Signs the feed itself (the app requires it: SURequireSignedFeed).
  "$SPARKLE_BIN/sign_update" ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} --disable-signing-warning "$APPCAST" >/dev/null
  "$SPARKLE_BIN/sign_update" ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} --verify "$APPCAST" >/dev/null || {
    echo "The appcast's signature does not verify"; exit 1; }
  echo "    $APPCAST"
}

# Commits build/appcast.xml to the gh-pages branch, which Pages serves.
publish_appcast() {
  local path="repos/$REPO/contents/appcast.xml" sha
  sha="$(gh api "$path?ref=gh-pages" --jq .sha 2>/dev/null || true)"
  echo "==> Publishing the appcast to GitHub Pages"
  gh api -X PUT "$path" --silent \
    -f message="Appcast for $NAME $VERSION" \
    -f branch=gh-pages \
    -f content="$(base64 -i "$APPCAST" | tr -d '\n')" \
    ${sha:+-f sha="$sha"}
  echo "    https://ephemerill.github.io/spider-buddy/appcast.xml (apps see it within ~10 minutes)"
}

if [ "$MODE" = "--appcast" ]; then
  need_gh
  body="$(gh release view "$TAG" -R "$REPO" --json body -q .body)"
  if [ ! -f "$DMG" ]; then
    echo "==> Fetching $(basename "$DMG") from the release"
    gh release download "$TAG" -R "$REPO" -p "$(basename "$DMG")" -D build
  fi
  [ -d "$APP" ] || { echo "$APP is missing (needed for its architectures); run tools/release.sh first"; exit 1; }
  echo "==> Writing the appcast for $TAG"
  write_appcast "${body%%"$MARKER"*}"
  publish_appcast
  exit 0
fi

APP_NAME="$NAME" ./build.sh release

echo "==> Packaging $DMG"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"
echo "    $(du -h "$DMG" | cut -f1)  $DMG"

NOTES_TEXT=""
[ -n "${NOTES:-}" ] && NOTES_TEXT="$(cat "$NOTES")"

echo "==> Writing the appcast"
write_appcast "$NOTES_TEXT"

if [ "$MODE" != "--publish" ]; then
  echo "==> Not publishing (pass --publish to create the GitHub release)"
  exit 0
fi

need_gh

INSTALL="$MARKER
Download the .dmg, open it, and drag Spider Buddy to Applications.

The first launch needs the usual step for an unsigned app: right-click Spider Buddy → Open, or allow it under System Settings → Privacy & Security. After that it keeps itself up to date: it looks for new versions once a day, and **Check for Updates** in the panel's App page looks straight away."

if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  echo "==> Release $TAG exists; replacing its .dmg"
  if [ -z "$NOTES_TEXT" ]; then
    # Keep the notes it already has in the update window.
    body="$(gh release view "$TAG" -R "$REPO" --json body -q .body)"
    write_appcast "${body%%"$MARKER"*}"
  fi
  gh release upload "$TAG" "$DMG" --clobber -R "$REPO"
else
  echo "==> Creating release $TAG"
  gh release create "$TAG" "$DMG" -R "$REPO" \
    --title "$NAME $VERSION" \
    --notes "${NOTES_TEXT:+$NOTES_TEXT

}$INSTALL"
fi
publish_appcast
echo "==> https://github.com/$REPO/releases/tag/$TAG"
