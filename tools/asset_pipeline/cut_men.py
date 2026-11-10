"""Cut soldier figures out of the game's men sheet (men-top.png) into the layout pack_original.py reads.

The sheet is 16 facings wide (48 px frames, column 0 east, clockwise). Each pose of a figure has three
rows: colour, paint (tinted by the side colour) and shape (rim and shadow). The pose rows come from the
game's own men table; they are given in a local spec file, never in this script. Each row becomes one
PNG strip in assets/sprites/source/original/unit_infantry_<name>/r1/<pose>_<layer>.png (git-ignored: it
is the game's art), with a source.json.

Usage: python tools/asset_pipeline/cut_men.py <men-top.png> <spec.json>
spec.json (local): { "unit_infantry_engineer": { "walk0": 213, "stand": 225, ... }, ... }
"""
import hashlib
import json
import os
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "source", "original")
F = 48
LAYERS = ("colour", "paint", "shape")


def main():
    sheet_path, spec_path = sys.argv[1], sys.argv[2]
    sheet = Image.open(sheet_path).convert("RGBA")
    if sheet.size[0] != 16 * F:
        raise SystemExit(f"{sheet_path}: width {sheet.size[0]}, expected {16 * F}")
    sha = hashlib.sha256(open(sheet_path, "rb").read()).hexdigest()
    spec = json.load(open(spec_path))
    for name, poses in spec.items():
        d = os.path.join(OUT, name, "r1")
        os.makedirs(d, exist_ok=True)
        frames = []
        for pose, row in poses.items():
            for i, layer in enumerate(LAYERS):
                r = row + i
                rect = (0, r * F, 16 * F, F)
                if (r + 1) * F > sheet.size[1]:
                    raise SystemExit(f"{name} {pose}: row {r} is past the sheet")
                strip = sheet.crop((0, r * F, 16 * F, (r + 1) * F))
                file = f"{pose}_{layer}.png"
                strip.save(os.path.join(d, file))
                alpha = sum(1 for a in strip.getchannel("A").getdata() if a > 0)
                frames.append({"file": file, "group": pose, "layer": layer, "sheetRow": r, "rect": list(rect), "alphaPixels": alpha})
        meta = {
            "assetId": name,
            "origin": "original-game",
            "sheet": "dist/tiles/men-top.png",
            "sheetSha256": sha,
            "frame": F,
            "facings": 16,
            "order": "column 0 = east, clockwise in 22.5 deg steps",
            "pivot": [F / 2, F / 2],
            "note": "men sheet; 3 rows a pose",
            "frames": frames,
        }
        json.dump(meta, open(os.path.join(d, "source.json"), "w"), indent=1)
        print(f"{name}: {len(poses)} poses")


if __name__ == "__main__":
    main()
