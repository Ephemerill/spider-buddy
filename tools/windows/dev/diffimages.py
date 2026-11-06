#!/usr/bin/env python3
"""Compare two image folders, Mac against Windows, by the method in WINDOWS_DEV_WORKFLOW.md section 7.2.

    diffimages.py <mac-dir> <win-dir> [--out diff-dir] [--worst 24]

Each PNG is composited over mid gray. Pass needs SSIM >= 0.985, mean error <= 3/255, and at most 0.4% of pixels off by
more than 64/255 (the share is of pixels either image draws). Prints a summary and writes a report, plus three-panel
pictures (Mac, Windows, amplified difference) for the worst images.
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageDraw


def load(path):
    im = Image.open(path).convert("RGBA")
    a = np.asarray(im, dtype=np.float64) / 255.0
    rgb, al = a[..., :3], a[..., 3:4]
    gray = 128.0 / 255.0
    return rgb * al + gray * (1 - al), al[..., 0], im


def box(img, r=3):
    # Box-filtered SSIM windows through a summed-area table: fast, and close to the Gaussian form.
    s = np.cumsum(np.cumsum(np.pad(img, ((1, 0), (1, 0))), axis=0), axis=1)
    k = 2 * r + 1
    return (s[k:, k:] - s[:-k, k:] - s[k:, :-k] + s[:-k, :-k]) / (k * k)


def ssim(x, y):
    c1, c2 = 0.01 ** 2, 0.03 ** 2
    x = x.mean(axis=2)
    y = y.mean(axis=2)
    if min(x.shape) < 8:
        return 1.0
    mx, my = box(x), box(y)
    sx, sy, sxy = box(x * x) - mx * mx, box(y * y) - my * my, box(x * y) - mx * my
    m = ((2 * mx * my + c1) * (2 * sxy + c2)) / ((mx * mx + my * my + c1) * (sx + sy + c2))
    return float(m.mean())


def compare(ap, bp):
    a, aa, ia = load(ap)
    b, ab, ib = load(bp)
    if a.shape != b.shape:
        return None
    d = np.abs(a - b)
    drawn = (aa > 0) | (ab > 0)
    n = max(int(drawn.sum()), 1)
    over = int((d.max(axis=2) * 255 > 64).sum())
    return dict(ssim=ssim(a, b), mean=float(d.mean() * 255), meanDrawn=float(d.mean(axis=2)[drawn].mean() * 255) if drawn.any() else 0.0,
                overShare=over / n, over=over, diff=d, a=a, b=b, ia=ia, ib=ib)


def panel(r, path, title):
    h, w = r["a"].shape[:2]
    amp = np.clip(r["diff"] * 4, 0, 1)
    def toimg(x):
        return Image.fromarray((x * 255).astype(np.uint8), "RGB")
    scale = 1 if w > 320 else 2
    im = Image.new("RGB", (w * 3 * scale + 20, h * scale + 22), (40, 40, 40))
    for i, x in enumerate((r["a"], r["b"], amp)):
        im.paste(toimg(x).resize((w * scale, h * scale), Image.NEAREST), (i * (w * scale + 10), 22))
    ImageDraw.Draw(im).text((4, 4), title, fill=(255, 255, 255))
    im.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mac")
    ap.add_argument("win")
    ap.add_argument("--out", default=None)
    ap.add_argument("--worst", type=int, default=24)
    ap.add_argument("--ssim", type=float, default=0.985)
    ap.add_argument("--mean", type=float, default=3.0)
    ap.add_argument("--over", type=float, default=0.004)
    args = ap.parse_args()

    rows, missing, keep = [], [], []
    for root, _, files in os.walk(args.mac):
        for f in sorted(files):
            if not f.endswith(".png"):
                continue
            mp = os.path.join(root, f)
            rel = os.path.relpath(mp, args.mac)
            wp = os.path.join(args.win, rel)
            if not os.path.exists(wp):
                missing.append(rel)
                continue
            r = compare(mp, wp)
            if r is None:
                rows.append((rel, False, 0, 999, 1.0, 0))
                continue
            ok = r["ssim"] >= args.ssim and r["mean"] <= args.mean and r["overShare"] <= args.over
            rows.append((rel, ok, r["ssim"], r["mean"], r["overShare"], r["meanDrawn"]))
            score = (1 - r["ssim"]) + r["overShare"]
            keep.append((score, rel, r))
            keep.sort(key=lambda t: -t[0])
            keep = keep[: args.worst]

    n = len(rows)
    passed = sum(1 for r in rows if r[1])
    print(f"{passed}/{n} images pass  ({len(missing)} missing)")
    if rows:
        s = np.array([r[2] for r in rows])
        m = np.array([r[3] for r in rows])
        o = np.array([r[4] for r in rows])
        print(f"SSIM   min {s.min():.4f}  median {np.median(s):.4f}")
        print(f"mean   max {m.max():.2f}  median {np.median(m):.2f}  (of 255)")
        print(f"over64 max {o.max() * 100:.2f}%  median {np.median(o) * 100:.3f}%")
    groups = {}
    for r in rows:
        g = r[0].split(os.sep)[1] if r[0].startswith("thumbs") else "poses"
        t = groups.setdefault(g, [0, 0])
        t[0] += 1
        t[1] += r[1]
    print("by group: " + ", ".join(f"{g} {p}/{t}" for g, (t, p) in sorted(groups.items())))
    print("\nworst:")
    for score, rel, r in keep[:14]:
        print(f"  {rel:58} ssim {r['ssim']:.4f}  mean {r['mean']:.2f}  over {r['overShare'] * 100:.2f}%")
    if args.out:
        os.makedirs(args.out, exist_ok=True)
        for i, (score, rel, r) in enumerate(keep):
            panel(r, os.path.join(args.out, f"{i:02d}-{rel.replace(os.sep, '_')}"), f"{rel}  ssim {r['ssim']:.4f} mean {r['mean']:.2f} over {r['overShare'] * 100:.2f}%  (Mac | Windows | diff x4)")
        with open(os.path.join(args.out, "report.tsv"), "w") as f:
            f.write("image\tpass\tssim\tmean\tover\n")
            for r in rows:
                f.write(f"{r[0]}\t{r[1]}\t{r[2]:.5f}\t{r[3]:.3f}\t{r[4]:.5f}\n")
    return 0 if passed == n and not missing else 1


if __name__ == "__main__":
    sys.exit(main())
