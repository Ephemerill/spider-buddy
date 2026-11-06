#!/bin/bash
# Random-number fixtures for the Windows port (see tools/rngprobe/main.swift).
#
#   ./tools/rngprobe.sh > rng.json
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p build
xcrun swiftc -O -swift-version 5 -o build/RngProbe tools/legs/Seeded.swift tools/rngprobe/main.swift 1>&2
./build/RngProbe
