#!/bin/bash
# Fetches the Sparkle framework and its tools (sign_update, generate_keys…)
# into build/Sparkle, once. build.sh and tools/release.sh call it; it does
# nothing when the pinned version is already there.
#
#   tools/sparkle.sh        # prints the directory it lives in
set -euo pipefail
cd "$(dirname "$0")/.."

SPARKLE_VERSION="2.10.0"
SPARKLE_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
DIR="build/Sparkle"

if [ "$(cat "$DIR/.version" 2>/dev/null)" != "$SPARKLE_VERSION" ]; then
  echo "==> Fetching Sparkle $SPARKLE_VERSION" >&2
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL -o "$TMP/sparkle.tar.xz" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
  echo "$SPARKLE_SHA256  $TMP/sparkle.tar.xz" | shasum -a 256 -c - >/dev/null || {
    echo "Sparkle download does not match its checksum" >&2; exit 1; }
  rm -rf "$DIR"
  mkdir -p "$DIR"
  # tar keeps the framework's symlinks, which its signature depends on.
  tar -xf "$TMP/sparkle.tar.xz" -C "$DIR" ./Sparkle.framework ./bin
  echo "$SPARKLE_VERSION" > "$DIR/.version"
fi
echo "$DIR"
