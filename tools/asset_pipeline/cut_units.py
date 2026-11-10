"""Cut unit strips out of the game's units sheet (units-top.png) into the layout pack_original.py reads.

The sheet is 16 facings wide (120 px frames, column 0 east, clockwise). A unit's rows, from the game's
unit table (fa.units): row = colour, row + 1 = paint (tinted by the side colour), row + 2 = shape (rim
and shadow); a turreted unit has its turret in rows + 3 to + 5. Each row becomes one PNG strip in
assets/sprites/source/original/unit_<name>/r1/ (git-ignored: it is the game's art), with a source.json.

Usage: python tools/asset_pipeline/cut_units.py <units-top.png> <spec.json>
spec.json (local): { "unit_ifv": { "row": 12, "turret": true, "wreckRow": 102 }, ... }
  "wreckTurret": false when the wreck look has no turret rows (the game's command_wreck).
  optional "extra": { "set1": 57 } cuts more looks (states) by row, without turret rows.
"""
import hashlib
import json
import os
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "source", "original")
F = 120
LAYERS = ("colour", "paint", "shape")


def main():
    sheet_path, spec_path = sys.argv[1], sys.argv[2]
    sheet = Image.open(sheet_path).convert("RGBA")
    if sheet.size[0] != 16 * F:
        raise SystemExit(f"{sheet_path}: width {sheet.size[0]}, expected {16 * F}")
    sha = hashlib.sha256(open(sheet_path, "rb").read()).hexdigest()
    spec = json.load(open(spec_path))
    for name, s in spec.items():
        d = os.path.join(OUT, name, "r1")
        os.makedirs(d, exist_ok=True)
        groups = []
        base = "hull" if s.get("turret") else "body"
        groups.append((base, s["row"]))
        if s.get("turret"):
            groups.append(("turret", s["row"] + 3))
        if "wreckRow" in s:
            wt = s.get("turret") and s.get("wreckTurret", True)
            groups.append(("wreck_hull" if wt else "wreck", s["wreckRow"]))
            if wt:
                groups.append(("wreck_turret", s["wreckRow"] + 3))
        for label, row in s.get("extra", {}).items():
            groups.append((label, row))
        frames = []
        for group, row in groups:
            for k, layer in enumerate(LAYERS):
                y = (row + k) * F
                strip = sheet.crop((0, y, 16 * F, y + F))
                fn = f"{group}_{layer}.png"
                strip.save(os.path.join(d, fn))
                frames.append({"file": fn, "group": group, "layer": layer, "sheetRow": row + k,
                               "alphaPixels": int(sum(1 for a in strip.getchannel("A").tobytes() if a))})
        json.dump({"assetId": name, "origin": "original-game", "sheet": "dist/tiles/units-top.png", "sheetSha256": sha,
                   "frame": F, "facings": 16, "frames": frames}, open(os.path.join(d, "source.json"), "w"), indent=1)
        print(name, ", ".join(f"{g}@{r}" for g, r in groups))


if __name__ == "__main__":
    main()
