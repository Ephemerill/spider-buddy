#!/bin/bash
# Rebuild and restart the spider.
set -euo pipefail
cd "$(dirname "$0")"
pkill -x DesktopSpider 2>/dev/null || true
./build.sh "${1:-release}"
open Spider.app
