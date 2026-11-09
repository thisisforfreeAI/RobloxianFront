#!/usr/bin/env python3
"""Validate a packed atlas against its source frames and the asset manifest.

  python tools/asset_pipeline/validate_atlas.py <runtime_dir_with_atlas.json> [--asset-id ID]

Checks (exit code 1 on any failure):
  dimensions   page size = cols*(w+2p) x rows*(h+2p), <= 1024, frames never resized
  rectangles   frame k sits at (col*(w+2p)+p, row*(h+2p)+p); no overlaps; inside the page
  pixels       every packed rectangle is byte-identical to its source frame (alpha included)
  direction    source direction i lands in column i % cols, row i // cols
  orientation  (synthetic only) the arrow's centroid points along i * 22.5 deg clockwise from east
  pivot        pivot is the frame centre; (synthetic) the magenta pivot cross sits exactly there
  transparency partial alpha survives; padding and gutters are fully transparent unless extruded
  bleed        frame edges are transparent, so a neighbour can't bleed in with Pixelated sampling
  manifest     an entry with this assetId exists and carries every required key (null allowed)
"""
import argparse, math, os, sys
from PIL import Image
from common import ROOT, load_json

REQUIRED = ["assetId", "requestId", "revision", "kind", "status", "source", "rights", "frame", "directions",
            "animations", "pivot", "atlas", "outputs", "approval", "roblox"]

class Report:
    def __init__(self):
        self.fail = 0
    def check(self, ok, name, detail=""):
        print(f"  {'ok  ' if ok else 'FAIL'}  {name}{(': ' + detail) if detail else ''}")
        self.fail += 0 if ok else 1

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("runtime_dir")
    ap.add_argument("--asset-id")
    a = ap.parse_args()
    meta = load_json(os.path.join(a.runtime_dir, "atlas.json"))
    src_dir = os.path.join(ROOT, meta["sourceDir"])
    fw, fh, p, cols = meta["frameWidth"], meta["frameHeight"], meta["padding"], meta["columns"]
    cw, ch, ndir = fw + 2 * p, fh + 2 * p, meta["directions"]["count"]
    r = Report()
    print(f"{meta['assetId']} r{meta['revision']} padding {p}: {len(meta['frames'])} frames, {len(meta['pages'])} page(s)")

    pages = []
    for pg in meta["pages"]:
        img = Image.open(os.path.join(a.runtime_dir, pg["file"]))
        r.check(img.mode == "RGBA", f"page {pg['page']} is RGBA", img.mode)
        r.check(img.size == (pg["width"], pg["height"]), f"page {pg['page']} size {img.size} matches atlas.json")
        r.check(img.width % cw == 0 and img.height % ch == 0 and img.width == cols * cw,
                f"page {pg['page']} is a whole grid of {cols} x {img.height // ch} cells of {cw}x{ch}")
        r.check(max(img.size) <= 1024, f"page {pg['page']} within Roblox's 1024 px limit")
        pages.append(img.convert("RGBA"))
    if meta["padding"] == 0 and ndir == 16 and len(meta["frames"]) == 16:
        r.check(pages[0].size == (960, 240), "16 x 120 px directions pack to exactly 960x240", str(pages[0].size))

    covered = [set() for _ in pages]
    rows_per_group = ndir // cols
    pix_ok = rect_ok = dir_ok = True
    for k, f in enumerate(meta["frames"]):
        d = f["direction"]
        group = k // ndir
        row = group * rows_per_group + d // cols
        rows_per_page = pages[0].height // ch
        exp = (d % cols * cw + p, (row % rows_per_page) * ch + p, row // rows_per_page)
        if (f["x"], f["y"], f["page"]) != exp or (f["w"], f["h"]) != (fw, fh):
            rect_ok = False
            print(f"        frame {k} dir {d}: rect {(f['x'], f['y'], f['page'])} expected {exp}")
        if k % ndir != d:
            dir_ok = False
        cell = (f["x"] // cw, f["y"] // ch)
        if cell in covered[f["page"]]:
            rect_ok = False
        covered[f["page"]].add(cell)
        src = Image.open(os.path.join(src_dir, f["source"])).convert("RGBA")
        if src.size != (fw, fh):
            pix_ok = False
        crop = pages[f["page"]].crop((f["x"], f["y"], f["x"] + fw, f["y"] + fh))
        if crop.tobytes() != src.tobytes():
            pix_ok = False
            print(f"        frame {k} pixels differ from {f['source']}")
    r.check(rect_ok, "rectangle offsets follow col = i % cols, row = i // cols, no overlaps")
    r.check(dir_ok, "source direction order preserved (0..15 in sequence)")
    r.check(pix_ok, "packed pixels identical to source frames, frames not resized")

    pv = meta["pivot"]
    r.check((pv["x"], pv["y"]) == (fw / 2, fh / 2) or (pv["x"], pv["y"]) == (fw // 2, fh // 2),
            "pivot is the frame centre", f"({pv['x']}, {pv['y']})")

    # transparency: partial alpha present; padding fully transparent unless extruded; frame edge gutter clear
    alphas = {v for v, c in enumerate(pages[0].getchannel("A").histogram()) if c}
    r.check(any(0 < x < 255 for x in alphas), "partial transparency preserved", f"{len(alphas)} alpha levels")
    if p and not meta.get("extruded"):
        pad_clear = True
        for pg in pages:
            A = pg.getchannel("A").load()
            for y in range(pg.height):
                for x in range(pg.width):
                    if (x % cw < p or x % cw >= p + fw or y % ch < p or y % ch >= p + fh) and A[x, y]:
                        pad_clear = False
        r.check(pad_clear, f"{p} px padding fully transparent")
    edge_clear = True
    for f in meta["frames"]:
        A = pages[f["page"]].getchannel("A").load()
        for t in range(fw):
            for (x, y) in ((f["x"] + t, f["y"]), (f["x"] + t, f["y"] + fh - 1), (f["x"], f["y"] + t), (f["x"] + fw - 1, f["y"] + t)):
                if A[x, y]:
                    edge_clear = False
    r.check(edge_clear, "frame edges transparent (no visible bleed between unpadded neighbours)")

    if meta.get("synthetic"):
        orient_ok = pivot_ok = True
        worst = 0.0
        for f in meta["frames"]:
            crop = pages[f["page"]].crop((f["x"], f["y"], f["x"] + fw, f["y"] + fh)).load()
            sx = sy = n = 0
            for y in range(fh):
                for x in range(fw):
                    c = crop[x, y]
                    if c[3] == 255 and max(c[:3]) - min(c[:3]) > 100 and c[:3] != (255, 0, 255):
                        dx, dy = x - pv["x"], y - pv["y"]
                        if math.hypot(dx, dy) > 30:  # arrow head region only
                            sx, sy, n = sx + dx, sy + dy, n + 1
            ang = math.degrees(math.atan2(sy, sx)) % 360
            err = abs((ang - f["direction"] * 22.5 + 180) % 360 - 180)
            worst = max(worst, err)
            if err > 3:
                orient_ok = False
                print(f"        dir {f['direction']}: arrow at {ang:.1f} deg")
            if crop[int(pv["x"]), int(pv["y"])][:3] != (255, 0, 255):
                pivot_ok = False
        r.check(orient_ok, "arrow k points k*22.5 deg clockwise from east (pixel y down)", f"worst error {worst:.2f} deg")
        r.check(pivot_ok, "magenta pivot cross at the declared pivot in every frame")

    man = load_json(os.path.join(ROOT, "assets", "manifests", "assets.json"))
    aid = a.asset_id or meta["assetId"]
    entry = next((e for e in man["assets"] if e.get("assetId") == aid), None)
    r.check(entry is not None, f"manifest entry for {aid}")
    if entry:
        missing = [k for k in REQUIRED if k not in entry]
        r.check(not missing, "manifest entry has every required key", ", ".join(missing))
        fr = entry.get("frame") or {}
        r.check((fr.get("width"), fr.get("height")) == (fw, fh), "manifest frame size matches atlas")
        pg_ok = any(ap_.get("padding") == p and ap_.get("width") == pages[0].width and ap_.get("height") == pages[0].height
                    for ap_ in (entry.get("atlas") or {}).get("layouts", []))
        r.check(pg_ok, "manifest lists this atlas layout")
    print(f"{'PASS' if not r.fail else 'FAIL'} ({r.fail} failing check(s))")
    sys.exit(1 if r.fail else 0)

if __name__ == "__main__":
    main()
