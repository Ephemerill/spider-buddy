#!/bin/bash
# Regenerates src/SwiftShims/AppKit/SymbolData.swift: Fluent System Icons sized and weighted
# as the Mac's SF Symbols. Run on a Mac (it measures SF Symbols with AppKit).
#   tools/symbols/run.sh [contact-sheet.png]
# Fetches the pinned @fluentui/svg-icons package from npm into a temporary folder.
set -euo pipefail
cd "$(dirname "$0")/../.."
VERSION=1.1.346
SHA=6426d09c820303ac400a1880a3d0e48e4912d9f137b826389d2329ca0eab0e0f
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/dl" "$tmp/bin"
curl -sSfL -o "$tmp/dl/icons.tgz" "https://registry.npmjs.org/@fluentui/svg-icons/-/svg-icons-$VERSION.tgz"
echo "$SHA  $tmp/dl/icons.tgz" | shasum -a 256 -c - >/dev/null
tar xzf "$tmp/dl/icons.tgz" -C "$tmp/dl"
swiftc -O tools/symbols/main.swift -o "$tmp/bin/symbols"
"$tmp/bin/symbols" tools/symbols/fluent-map.txt "$tmp/dl/package/icons" src/SwiftShims/AppKit/SymbolData.swift "${1:-$tmp/sheet.png}"
