#!/usr/bin/env python3
"""Draw SYNTHETIC test frames (no original art) to validate the pipeline.

  python tools/asset_pipeline/synth_frames.py [--id syn_vehicle_arrow] [--rev 1]

Writes assets/sprites/source/synthetic/<id>/r<rev>/dir_00.png .. dir_15.png and source.json.
Each 120x120 frame shows:
  * an arrow from the pivot towards facing i (i * 22.5 deg clockwise from east), hue per index,
  * the index number near the opposite edge (to check rectangle offsets),
  * a 1 px magenta pivot cross at (60, 60),
  * a 50%-alpha shadow disc (to check partial transparency),
  * a 2 px fully transparent gutter on every edge (to check bleed between packed frames).
"""
import argparse, colorsys, math, os
from PIL import Image, ImageDraw, ImageFont
from common import DIRECTION_ORDER, ROOT, rel, save_json

FRAME = 120
GUTTER = 2
PIVOT = (60, 60)

def draw_frame(i):
    img = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = PIVOT
    d.ellipse([cx - 26, cy - 26, cx + 26, cy + 26], fill=(0, 0, 0, 128))  # shadow, alpha 128
    a = math.radians(i * DIRECTION_ORDER["stepDegrees"])
    ux, uy = math.cos(a), math.sin(a)          # pixel y down: clockwise on screen
    px, py = -uy, ux
    r, g, b = (int(c * 255) for c in colorsys.hsv_to_rgb(i / 16, 0.85, 1.0))
    tip = (cx + ux * 52, cy + uy * 52)
    base = (cx + ux * 34, cy + uy * 34)
    d.line([(cx, cy), base], fill=(r, g, b, 255), width=7)
    d.polygon([tip, (base[0] + px * 11, base[1] + py * 11), (base[0] - px * 11, base[1] - py * 11)],
              fill=(r, g, b, 255))
    label = str(i)
    font = ImageFont.load_default()
    tx, ty = cx - ux * 36, cy - uy * 36
    box = d.textbbox((0, 0), label, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    d.rectangle([tx - w / 2 - 3, ty - h / 2 - 3, tx + w / 2 + 3, ty + h / 2 + 3], fill=(255, 255, 255, 255))
    d.text((tx - w / 2 - box[0], ty - h / 2 - box[1]), label, fill=(0, 0, 0, 255), font=font)
    for k in range(-4, 5):
        img.putpixel((cx + k, cy), (255, 0, 255, 255))
        img.putpixel((cx, cy + k), (255, 0, 255, 255))
    for x in range(FRAME):                       # enforce the transparent gutter
        for y in list(range(GUTTER)) + list(range(FRAME - GUTTER, FRAME)):
            img.putpixel((x, y), (0, 0, 0, 0))
            img.putpixel((y, x), (0, 0, 0, 0))
    return img

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--id", default="syn_vehicle_arrow")
    ap.add_argument("--rev", type=int, default=1)
    args = ap.parse_args()
    out = os.path.join(ROOT, "assets", "sprites", "source", "synthetic", args.id, f"r{args.rev}")
    os.makedirs(out, exist_ok=True)
    files = []
    for i in range(DIRECTION_ORDER["count"]):
        name = f"dir_{i:02d}.png"
        draw_frame(i).save(os.path.join(out, name), optimize=True)
        files.append({"direction": i, "animation": "idle", "frame": 0, "file": name})
    save_json(os.path.join(out, "source.json"), {
        "assetId": args.id, "revision": args.rev, "synthetic": True,
        "frameWidth": FRAME, "frameHeight": FRAME,
        "pivot": {"x": PIVOT[0], "y": PIVOT[1], "convention": "pixels from the frame's top-left, y down"},
        "directions": DIRECTION_ORDER, "transparentGutterPx": GUTTER,
        "animations": [{"name": "idle", "frames": 1, "frameMs": None, "loop": True}],
        "frames": files,
    })
    print(f"wrote {len(files)} frames to {rel(out)}")

if __name__ == "__main__":
    main()
