#!/bin/bash
# Builds the app — a self-contained menu-bar app, no Xcode required.
#
# The name is APP_NAME: "spiders" for the testing build (the default, what
# ./run.sh makes), "Spider Buddy" for a release (tools/release.sh sets it).
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

echo "==> Compiling $VERSION ($CONF)  [$(xcrun swiftc --version | head -1)]"
mkdir -p build
# shellcheck disable=SC2086
xcrun swiftc $FLAGS -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
  -framework AppKit -framework QuartzCore -framework ServiceManagement -framework IOKit \
  -o "build/$BIN" Sources/DesktopSpider/*.swift

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "build/$BIN" "$APP/Contents/MacOS/$BIN"

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
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>NSHumanReadableCopyright</key><string>A friendly jumping spider for your desktop.</string>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
  echo "    (ad-hoc signing skipped)"

echo "==> Done: $(pwd)/$APP"
echo "    Run it with:  open \"$(pwd)/$APP\""
