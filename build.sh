#!/bin/bash
# Builds the app — a self-contained menu-bar app, no Xcode required.
#
# The name is APP_NAME: "spiders" for the testing build (the default, what
# ./run.sh makes), "Spider Buddy" for a release (tools/release.sh sets it).
# SIGN_IDENTITY="Developer ID Application: …" signs it for distribution;
# without it the app is signed ad hoc.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="${APP_NAME:-spiders}"
APP="$APP_NAME.app"
BIN="DesktopSpider"
CONF="${1:-release}"
VERSION="$(tr -d '[:space:]' < VERSION)"

if [ "$CONF" = "debug" ]; then
  FLAGS="-Onone -g"
else
  FLAGS="-O"
fi

# Prefer Xcode's toolchain: the bare Command Line Tools ship an SDK whose Swift
# build does not match their compiler, which makes every build recompile the
# system module interfaces (slowly, and sometimes not at all).
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# Updates come through Sparkle (fetched into build/Sparkle the first time).
# The feed is served by GitHub Pages from the repo's gh-pages branch, which
# tools/release.sh updates with each release. It and every update are signed
# with the EdDSA key whose public half is below; the private half lives in
# the release machine's keychain. Every shipped copy reads this address, so
# it must never move.
SPARKLE="$(tools/sparkle.sh)"
FEED_URL="https://ephemerill.github.io/spider-buddy/appcast.xml"
SPARKLE_PUBLIC_KEY="XOyzaJD04viRmPjvWSW7qP2/DWJhofgLGDLXi0+Bcv4="

# Bug reports go through a Cloudflare Worker (tools/report-worker), which
# holds the Discord webhook as a secret and passes reports on to it. The
# Worker's own address isn't secret: every build reports to it.
REPORT_URL="https://spider-buddy-reports.ephemerill.workers.dev"

echo "==> Compiling $VERSION ($CONF)  [$(xcrun swiftc --version | head -1)]"
mkdir -p build
# shellcheck disable=SC2086
xcrun swiftc $FLAGS -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
  -framework AppKit -framework QuartzCore -framework ServiceManagement -framework IOKit \
  -F "$SPARKLE" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "build/$BIN" Sources/DesktopSpider/*.swift

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "build/$BIN" "$APP/Contents/MacOS/$BIN"
ditto "$SPARKLE/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
# Its icon, drawn by tools/art.sh (the menu bar spider on a tile).
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>com.gabriel.desktopspider</string>
  <key>CFBundleExecutable</key><string>DesktopSpider</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>NSHumanReadableCopyright</key><string>A friendly jumping spider for your desktop.</string>
  <key>SUFeedURL</key><string>$FEED_URL</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
  <key>SURequireSignedFeed</key><true/>
  <key>SUVerifyUpdateBeforeExtraction</key><true/>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
  <key>SpiderReportEndpoint</key><string>$REPORT_URL</string>
  <key>NSAudioCaptureUsageDescription</key><string>Your spider listens for the beat of whatever music is playing, so it can dance along. Nothing is recorded or kept.</string>
</dict>
</plist>
PLIST

if [ -n "${SIGN_IDENTITY:-}" ]; then
  # A Developer ID signature with the hardened runtime and a secure timestamp,
  # as notarization requires (tools/release.sh sets SIGN_IDENTITY). Signed
  # inside out: Sparkle's helpers, then the framework, then the app. The app
  # needs no entitlements. The Downloader keeps its own (it is sandboxed).
  echo "==> Signing as $SIGN_IDENTITY"
  sign() { codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$@"; }
  FW="$APP/Contents/Frameworks/Sparkle.framework"
  sign "$FW/Versions/B/XPCServices/Installer.xpc"
  sign --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
  sign "$FW/Versions/B/Autoupdate"
  sign "$FW/Versions/B/Updater.app"
  sign "$FW"
  sign "$APP"
  codesign --verify --deep --strict "$APP"
else
  echo "==> Signing (ad-hoc)"
  codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
    echo "    (ad-hoc signing skipped)"
fi

echo "==> Done: $(pwd)/$APP"
echo "    Run it with:  open \"$(pwd)/$APP\""
