#!/bin/bash
# Rebuilds Resources/AppIcon.ico, the Windows app icon, from the Mac's Resources/AppIcon.icns (which tools/art.sh draws;
# never run that here). Run on a Mac. Each size Windows asks for (16, 20, 24, 32, 40, 48, 64, 128, 256) comes from the
# Mac's own drawing at that size where there is one, else resampled from the next drawing up. Stored as PNG entries.
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
iconutil -c iconset Resources/AppIcon.icns -o "$tmp/AppIcon.iconset"
python3 - "$tmp/AppIcon.iconset" Resources/AppIcon.ico <<'PY'
import sys, os, io, struct
from PIL import Image
src, out = sys.argv[1], sys.argv[2]
drawn = {}
for n in os.listdir(src):
    if n.endswith(".png"):
        im = Image.open(os.path.join(src, n)).convert("RGBA")
        drawn.setdefault(im.width, im)     # same pixels whichever name (16@2x and 32 are both 32)
sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
entries = []
for s in sizes:
    if s in drawn: im = drawn[s]
    else:
        up = min(w for w in drawn if w > s)
        im = drawn[up].resize((s, s), Image.LANCZOS)
    b = io.BytesIO(); im.save(b, "PNG"); entries.append((s, b.getvalue()))
head = struct.pack("<HHH", 0, 1, len(entries))
offset = 6 + 16 * len(entries)
dirs, blobs = b"", b""
for s, data in entries:
    dirs += struct.pack("<BBBBHHII", s % 256, s % 256, 0, 0, 1, 32, len(data), offset + len(blobs))
    blobs += data
open(out, "wb").write(head + dirs + blobs)
print(out, "sizes", [s for s, _ in entries], "from drawings", sorted(drawn))
PY
