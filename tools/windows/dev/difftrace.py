#!/usr/bin/env python3
"""Compare two pose traces frame by frame.

    difftrace.py <reference.jsonl> <other.jsonl> [--pos 0.02] [--ang 0.002] [--scalar 0.005] [--show 12]

The reference is the Mac oracle. Tolerances default to the ones in WINDOWS_DEV_WORKFLOW.md section 7.1:
positions and joints in units, angles in radians, 0-to-1 scalars. Strings and booleans must be equal.

Prints the first frame that fails, the worst value per field, and how far each field drifted over time.
Exit code 0 only if every frame passes.
"""
import argparse
import json
import math
import sys
from collections import defaultdict

ANGLES = {"heading", "spin", "facing", "headTurn", "headTilt", "headCock", "abdomenTilt", "bodyPitch", "abdomenSway"}
SCALARS = {"blink", "happy", "startled", "sleep", "ball", "grounded", "wet", "snow", "dust", "chill", "chew", "wink",
           "palpNear", "palpFar", "grabbed", "emoteT", "nameTag", "look", "stretch", "fatten", "alpha", "lift"}


def kind(path):
    leaf = path.rsplit(".", 1)[-1]
    if leaf in ANGLES:
        return "ang"
    if leaf in SCALARS:
        return "scalar"
    return "pos"


def flatten(prefix, v, out):
    if isinstance(v, dict):
        for k, x in v.items():
            flatten(prefix + "." + k if prefix else k, x, out)
    elif isinstance(v, list):
        out[prefix + ".#"] = len(v)
        for i, x in enumerate(v):
            flatten(f"{prefix}[{i}]", x, out)
    else:
        out[prefix] = v


def generic(path):
    # legs[3].foot.x -> legs[].foot.x, for grouping
    out, skip = [], False
    for ch in path:
        if ch == "[":
            out.append("[]")
            skip = True
        elif ch == "]":
            skip = False
        elif not skip:
            out.append(ch)
    return "".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("--pos", type=float, default=0.02)
    ap.add_argument("--ang", type=float, default=0.002)
    ap.add_argument("--scalar", type=float, default=0.005)
    ap.add_argument("--show", type=int, default=12)
    ap.add_argument("--ignore", default="", help="comma list of field prefixes to skip")
    ap.add_argument("--quiet", action="store_true", help="print one summary line only")
    args = ap.parse_args()
    tol = {"pos": args.pos, "ang": args.ang, "scalar": args.scalar}
    ignore = [x for x in args.ignore.split(",") if x]

    worst = defaultdict(lambda: (0.0, -1, None, None))
    failing_frames = 0
    first = None
    frames = 0
    only_a, only_b = set(), set()
    drift = []  # max position-class error by frame
    mismatch = defaultdict(int)

    with open(args.a) as fa, open(args.b) as fb:
        ha, hb = json.loads(fa.readline()), json.loads(fb.readline())
        for k in ("scenario", "seed", "scale", "dt"):
            if ha.get(k) != hb.get(k):
                print(f"warning: header differs on {k}: {ha.get(k)} vs {hb.get(k)}")
        while True:
            la, lb = fa.readline(), fb.readline()
            if not la or not lb:
                if la or lb:
                    print(f"warning: length differs: one file ended at frame {frames}")
                break
            A, B = {}, {}
            flatten("", json.loads(la), A)
            flatten("", json.loads(lb), B)
            bad = []
            frame_pos = 0.0
            for key in A.keys() | B.keys():
                if any(key.startswith(p) for p in ignore):
                    continue
                if key not in B:
                    only_a.add(generic(key)); continue
                if key not in A:
                    only_b.add(generic(key)); continue
                x, y = A[key], B[key]
                if isinstance(x, bool) or isinstance(y, bool) or not isinstance(x, (int, float)) or not isinstance(y, (int, float)):
                    if x != y:
                        bad.append((key, x, y, math.inf))
                        mismatch[generic(key)] += 1
                    continue
                d = abs(float(x) - float(y))
                k = kind(key)
                g = generic(key)
                if d > worst[g][0]:
                    worst[g] = (d, frames, x, y)
                if k == "pos":
                    frame_pos = max(frame_pos, d)
                if d > tol[k]:
                    bad.append((key, x, y, d))
            drift.append(frame_pos)
            if bad:
                failing_frames += 1
                if first is None:
                    first = (frames, sorted(bad, key=lambda t: -t[3])[:args.show])
            frames += 1

    ok = failing_frames == 0 and frames > 0
    if args.quiet:
        at = first[0] if first else -1
        wp = max(drift) if drift else 0
        print(f"{'PASS' if ok else 'FAIL'} frames={frames} failing={failing_frames} first={at} worstPos={wp:.3g}")
        return 0 if ok else 1

    print(f"{args.a}\n  vs {args.b}")
    print(f"frames {frames}, failing {failing_frames}, {'PASS' if ok else 'FAIL'}")
    if first:
        print(f"\nfirst failure at frame {first[0]}:")
        for key, x, y, d in first[1]:
            print(f"  {key:34} {x!r:>24} {y!r:>24}  diff {d:.3g}")
    print("\nworst per field (over tolerance marked *):")
    ranked = sorted(worst.items(), key=lambda kv: -kv[1][0])
    for g, (d, f, x, y) in ranked[:args.show]:
        mark = "*" if d > tol[kind(g)] else " "
        print(f" {mark} {g:32} {d:10.3g} at frame {f}")
    if mismatch:
        print("\nnon-numeric mismatches (frames):")
        for g, n in sorted(mismatch.items(), key=lambda kv: -kv[1])[:args.show]:
            print(f"  {g:32} {n}")
    if drift:
        steps = max(1, len(drift) // 8)
        print("\nworst position error over time:")
        print("  " + "  ".join(f"f{i}:{max(drift[i:i+steps]):.2g}" for i in range(0, len(drift), steps)))
    if only_a:
        print("\nonly in reference:", ", ".join(sorted(only_a)[:12]))
    if only_b:
        print("\nonly in other:", ", ".join(sorted(only_b)[:12]))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
