#!/bin/bash
# The page-ledge check (see tools/pages/main.swift): what the spider would
# climb on a picture of a web page.
#
#   ./tools/pages.sh see <page.png> <out.png> [scale]   the ledges, drawn over the page
#   ./tools/pages.sh time <page.png> [runs]              how long a look takes
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p build
xcrun swiftc -O -swift-version 5 -framework AppKit -o build/Pages \
  Sources/DesktopSpider/PageLedges.swift \
  tools/pages/main.swift
./build/Pages "$@"
