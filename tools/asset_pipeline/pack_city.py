"""Pack a designed map's baked towns (the game's dist/cities/<id>.city) into local Luau modules.

The .city file (traced from the game's loader): "WFCT", u32 LE header length, a JSON header
{v, id, key, size, perRow, atlasW, atlasH, count, parts: [{name, raw, packed}]}, then each part as raw
DEFLATE. Parts: atlas (RGBA tiles, size x size px each, perRow a row; alpha holds the game's surface
code: 150 green, 200 street, 201 lamp, 224+ roofs), index (RGBA per map cell: tile number + 1 in the
low 24 bits, 0 = none), cells (1 per town cell), aux (height and light data for the roof shading),
townCells, trees (float32 x, y pairs in cells).

This writes, git-ignored (it embeds the art):
  src/client/DevAssets/City_<id>.luau            layout: cell px, chunk cells, the chunk list, trees
  src/client/DevAssets/City_<id>_<cx>_<cy>.luau  one chunk of the map as RGBA, raw DEFLATE, base64
Chunks are chunkCells x chunkCells cells (64 x 14 px = 896 px, under the 1024 px EditableImage limit);
chunks with nothing drawn are skipped. Town pixels are copied unchanged except alpha: any surface code
> 0 becomes 255 (opaque). Roof shading from aux is not applied yet.

Trees (optional, --trees/--sheet/--map): every tree from tools/conversion/export_trees.cjs (the game's
own placement) is drawn on top, from trees-top.png, as the game's forest layer does: a tree's sprite
is w x scale px at 0.013 cells a px (its root scale), centred on the tree; under all trees, each
tree's silhouette in black at alpha 0.3 shifted by (0.12, 0.16) x its drawn width (tU); trees in
y-then-x order. Wild trees are cleared from town cells, urban cells and road cells (rank 1+), as the
game's clearing pass does at load; yard trees stay. Not baked: the sun-angle shadow shift, the day
and night tint, trees cleared later round buildings.

Usage:
  python tools/asset_pipeline/pack_city.py <file.city> --dump-town-trees town_trees.json
  node tools/conversion/export_trees.cjs <main-*.js> <map.json> town_trees.json > trees.json
  python tools/asset_pipeline/pack_city.py <file.city> --trees trees.json --sheet <trees-top.png> --map <map.json>
"""
import argparse
import base64
import json
import os
import struct
import zlib

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "src", "client", "DevAssets")


def read_city(path):
    b = open(path, "rb").read()
    if b[:4] != b"WFCT":
        raise SystemExit(f"{path}: not a .city file")
    n = struct.unpack("<I", b[4:8])[0]
    head = json.loads(b[8:8 + n])
    r = 8 + n
    parts = {}
    for p in head["parts"]:
        raw = zlib.decompress(b[r:r + p["packed"]], -15)
        if len(raw) != p["raw"]:
            raise SystemExit(f"{path}: part {p['name']} is {len(raw)} bytes, header says {p['raw']}")
        parts[p["name"]] = raw
        r += p["packed"]
    return head, parts


def map_size(key):
    # key looks like "saddle:384x240:real:..."
    w, h = key.split(":")[1].split("x")
    return int(w), int(h)


def deflate(data):
    c = zlib.compressobj(9, zlib.DEFLATED, -15)
    return c.compress(data) + c.flush()


TREE_CELLS_PER_PX = 0.013  # the forest layer's root scale ($0)
SHADOW = {"alpha": 0.3, "dx": 0.12, "dy": 0.16}  # tU


def road_cells(m):
    """The game's U3(real, 1): road cells of rank 1 and up, sampled 4 times a cell along each segment."""
    w, h = m["width"], m["height"]
    out = np.zeros((h, w), bool)
    for r in m["roads"]:
        if r.get("rank", 0) < 1:
            continue
        p = r["pts"]
        for i in range(2, len(p) - 1, 2):
            x0, y0, x1, y1 = p[i - 2], p[i - 1], p[i], p[i + 1]
            n = max(1, int(np.ceil(np.hypot(x1 - x0, y1 - y0) * 4)))
            for u in range(n + 1):
                x, y = int(np.floor(x0 + (x1 - x0) * u / n)), int(np.floor(y0 + (y1 - y0) * u / n))
                if 0 <= x < w and 0 <= y < h:
                    out[y, x] = True
    return out


class Trees:
    def __init__(self, data, sheet, T):
        self.d, self.sheet, self.T, self.cache = data, Image.open(sheet).convert("RGBA"), T, {}

    def sprite(self, name, scale):
        x, y, w, h = self.d["tiles"][name]
        pw = max(1, round(w * scale * TREE_CELLS_PER_PX * self.T))
        ph = max(1, round(h * scale * TREE_CELLS_PER_PX * self.T))
        key = (name, pw, ph)
        if key not in self.cache:
            img = self.sheet.crop((x, y, x + w, y + h)).resize((pw, ph), Image.LANCZOS)
            shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
            shadow.putalpha(img.getchannel("A").point(lambda a: round(a * SHADOW["alpha"])))
            self.cache[key] = (img, shadow)
        return self.cache[key]


def over(canvas, img, x, y):
    """alpha_composite img onto canvas at (x, y), clipped to the canvas (PIL wants a non-negative spot)."""
    sx, sy = max(0, -x), max(0, -y)
    w, h = min(img.width, canvas.width - x) - sx, min(img.height, canvas.height - y) - sy
    if w <= 0 or h <= 0:
        return
    canvas.alpha_composite(img, (x + sx, y + sy), (sx, sy, sx + w, sy + h))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("city")
    ap.add_argument("--chunk", type=int, default=64)
    ap.add_argument("--dump-town-trees")
    ap.add_argument("--trees")
    ap.add_argument("--sheet")
    ap.add_argument("--map")
    a = ap.parse_args()
    head, parts = read_city(a.city)
    if a.dump_town_trees:
        json.dump([float(v) for v in np.frombuffer(parts["trees"], np.float32)], open(a.dump_town_trees, "w"))
        print("town trees written to", a.dump_town_trees)
        return
    mid, T, per = head["id"], head["size"], head["perRow"]
    W, H = map_size(head["key"])
    atlas = np.frombuffer(parts["atlas"], np.uint8).reshape(head["atlasH"], head["atlasW"], 4)
    idx = np.frombuffer(parts["index"], np.uint8).reshape(H, W, 4).astype(np.int64)
    tile = idx[:, :, 0] + (idx[:, :, 1] << 8) + (idx[:, :, 2] << 16)
    img = np.zeros((H * T, W * T, 4), np.uint8)
    for y, x in zip(*np.nonzero(tile)):
        t = tile[y, x] - 1
        ax, ay = (t % per) * T, (t // per) * T
        img[y * T:(y + 1) * T, x * T:(x + 1) * T] = atlas[ay:ay + T, ax:ax + T]
    opaque = img[:, :, 3] > 0
    img[:, :, 3] = np.where(opaque, 255, 0)
    img[~opaque] = 0

    os.makedirs(OUT, exist_ok=True)
    name = "City_" + mid
    C = a.chunk
    # trees: keep the ones the game keeps, bucket them by chunk (a tree may reach into the next chunk)
    trees, buckets, kept = None, {}, 0
    if a.trees:
        if not (a.sheet and a.map):
            raise SystemExit("--trees needs --sheet and --map")
        td = json.load(open(a.trees))
        m = json.load(open(a.map))
        cells = np.frombuffer(parts["cells"], np.uint8).reshape(H, W) > 0
        urban = np.array(m["urban"]["data"] if isinstance(m["urban"], dict) else m["urban"]).reshape(H, W) > 0
        clear = cells | urban | road_cells(m)
        trees = Trees(td, a.sheet, T)
        order = sorted(range(td["count"]), key=lambda i: (round(td["y"][i] / TREE_CELLS_PER_PX), round(td["x"][i] / TREE_CELLS_PER_PX)))
        for i in order:
            x, y = td["x"][i], td["y"][i]
            if not td["yard"][i] and clear[min(H - 1, int(y)), min(W - 1, int(x))]:
                continue
            kept += 1
            for bx in {int((x - 1.5) // C), int((x + 1.5) // C)}:
                for by in {int((y - 1.5) // C), int((y + 1.5) // C)}:
                    buckets.setdefault((bx, by), []).append(i)
    chunks, total = [], 0
    for cy in range(0, H, C):
        for cx in range(0, W, C):
            cw, chh = min(C, W - cx), min(C, H - cy)
            px = img[cy * T:(cy + chh) * T, cx * T:(cx + cw) * T]
            mine = buckets.get((cx // C, cy // C), [])
            if mine:
                canvas = Image.fromarray(np.ascontiguousarray(px))
                ox, oy = cx * T, cy * T
                for layer in (1, 0):  # all shadows, then all trees
                    for i in mine:
                        tree, shadow = trees.sprite(td["tile"][i], td["scale"][i])
                        w0 = td["tiles"][td["tile"][i]][2] * td["scale"][i] * TREE_CELLS_PER_PX * T
                        left = round(td["x"][i] * T - tree.width / 2) - ox
                        top = round(td["y"][i] * T - tree.height / 2) - oy
                        if layer == 1:
                            over(canvas, shadow, left + round(w0 * SHADOW["dx"]), top + round(w0 * SHADOW["dy"]))
                        else:
                            over(canvas, tree, left, top)
                px = np.array(canvas)
            if not px[:, :, 3].any():
                continue
            data = base64.b64encode(deflate(np.ascontiguousarray(px).tobytes())).decode()
            mod = f"{name}_{cx}_{cy}"
            with open(os.path.join(OUT, mod + ".luau"), "w", newline="\n") as f:
                f.write("--!strict\n-- GENERATED by tools/asset_pipeline/pack_city.py from the game's baked towns. Local only (git-ignored).\n")
                f.write(f'return {{ width = {cw * T}, height = {chh * T}, deflate = "{data}" }}\n')
            chunks.append((cx, cy, cw, chh, mod))
            total += len(data)
    town_trees = np.frombuffer(parts["trees"], np.float32)
    with open(os.path.join(OUT, name + ".luau"), "w", newline="\n") as f:
        f.write("--!strict\n-- GENERATED by tools/asset_pipeline/pack_city.py. Local only (git-ignored).\n")
        f.write("-- chunks: { cx, cy, w, h, module } in cells; trees: x, y pairs in cells (town trees).\n")
        f.write(f'return {{\n\tid = "{mid}", width = {W}, height = {H}, cellPx = {T}, chunkCells = {C},\n\tchunks = {{\n')
        for cx, cy, cw, chh, mod in chunks:
            f.write(f'\t\t{{ {cx}, {cy}, {cw}, {chh}, "{mod}" }},\n')
        f.write("\t},\n\ttrees = { " + ", ".join(f"{v:.3f}" for v in town_trees) + " },\n}\n")
    print(f"{name}: {W}x{H} cells, {len(chunks)} chunks, {total // 1024} KB, {kept} trees drawn")


if __name__ == "__main__":
    main()
