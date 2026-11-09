#!/usr/bin/env python3
"""Make the 16 direction frames from ONE top-down image that faces east (right).

  python tools/asset_pipeline/rotate_frames.py <east_facing.png> --id <assetId> --rev <n>
         [--origin chatgpt] [--frame 120] [--pivot 60 60]

This is how WarFront itself renders mod art: one picture, turned into each of the 16 facings.
The input can be larger than the frame (e.g. 480x480); it is scaled to fit the frame once, then each
direction is rotated at 4x resolution about the pivot and filtered down, so edges stay clean.
Direction i is rotated i * 22.5 deg CLOCKWISE on screen (WarFront order: 0 east, 4 south, 8 west, 12 north).
The input file is never modified; it is copied next to the frames as source_east.png.

Output: assets/sprites/source/<origin>/<assetId>/r<rev>/dir_00.png .. dir_15.png + source.json
"""
import argparse, os, shutil
from PIL import Image
from common import DIRECTION_ORDER, ROOT, rel, save_json

SS = 4  # supersampling factor

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--id", required=True)
    ap.add_argument("--rev", type=int, required=True)
    ap.add_argument("--origin", default="chatgpt")
    ap.add_argument("--frame", type=int, default=120)
    ap.add_argument("--pivot", type=float, nargs=2, default=None)
    ap.add_argument("--gutter", type=int, default=2)
    ap.add_argument("--snap-alpha", type=int, default=None,
                    help="treat alpha >= N as fully opaque (fixes art delivered at e.g. alpha 253); the delivered file is kept as is")
    a = ap.parse_args()
    f = a.frame
    px, py = a.pivot or (f / 2, f / 2)
    src = Image.open(a.image).convert("RGBA")
    if a.snap_alpha is not None:
        alpha = src.getchannel("A").point(lambda v: 255 if v >= a.snap_alpha else v)
        src.putalpha(alpha)
    if src.width != src.height:
        raise SystemExit(f"input must be square (got {src.size}) with the vehicle centred on its pivot")
    if src.size != (f, f) and src.width % f:
        print(f"note: {src.size} is not a whole multiple of {f}; it will be resampled")
    base = src.resize((f * SS, f * SS), Image.LANCZOS)
    out = os.path.join(ROOT, "assets", "sprites", "source", a.origin, a.id, f"r{a.rev}")
    if os.path.exists(out) and os.listdir(out):
        raise SystemExit(f"{rel(out)} already exists: approved revisions are never overwritten, use a new --rev")
    os.makedirs(out)
    shutil.copyfile(a.image, os.path.join(out, "source_east.png"))
    frames = []
    for i in range(DIRECTION_ORDER["count"]):
        # PIL rotates counter-clockwise for positive angles; WarFront facings go clockwise on screen.
        big = base.rotate(-i * DIRECTION_ORDER["stepDegrees"], resample=Image.BICUBIC, center=(px * SS, py * SS))
        img = big.resize((f, f), Image.LANCZOS)
        clipped = 0
        for x in range(f):
            for y in list(range(a.gutter)) + list(range(f - a.gutter, f)):
                for (cx, cy) in ((x, y), (y, x)):
                    if img.getpixel((cx, cy))[3]:
                        clipped += 1
                        img.putpixel((cx, cy), (0, 0, 0, 0))
        if clipped:
            print(f"warning: direction {i}: {clipped} pixels inside the {a.gutter} px border were cleared; the art is too big for the frame")
        name = f"dir_{i:02d}.png"
        img.save(os.path.join(out, name), optimize=True)
        frames.append({"direction": i, "animation": "idle", "frame": 0, "file": name})
    save_json(os.path.join(out, "source.json"), {
        "assetId": a.id, "revision": a.rev, "synthetic": False,
        "frameWidth": f, "frameHeight": f,
        "pivot": {"x": px, "y": py, "convention": "pixels from the frame's top-left, y down"},
        "directions": DIRECTION_ORDER, "transparentGutterPx": a.gutter,
        "generatedFrom": {"file": "source_east.png", "method": "rotate about pivot, 4x supersampled",
                          "snapAlpha": a.snap_alpha},
        "animations": [{"name": "idle", "frames": 1, "frameMs": None, "loop": True}],
        "frames": frames,
    })
    print(f"wrote 16 directions to {rel(out)}")

if __name__ == "__main__":
    main()
