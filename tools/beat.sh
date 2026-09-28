#!/bin/bash
# The beat tracker, offline, against loops, made-up patterns, songs and
# speech (see tools/beat/main.swift for the modes).
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p build
xcrun swiftc -O -swift-version 5 -framework AVFoundation -o build/Beat \
  Sources/DesktopSpider/Math.swift Sources/DesktopSpider/Beat.swift tools/beat/main.swift
./build/Beat "$@"
