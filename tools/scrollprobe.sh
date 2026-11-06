#!/bin/bash
# What the Mac's scroll events look like (see tools/scrollprobe/main.swift).
#
#   ./tools/scrollprobe.sh [seconds] > scroll.txt
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p build
xcrun swiftc -O -swift-version 5 -framework AppKit -o build/ScrollProbe tools/scrollprobe/main.swift 1>&2
./build/ScrollProbe "$@"
