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
chunks with nothing drawn are skipped. Town pixels keep their colour, made opaque, and get the ground
shader's close-up town light baked in (see shade(): sky occlusion and roof shadows from the aux part,
for one fixed sun, noon by default; --no-shade skips it). With --lighting 16, additional local-only
XOR patches sample roof shadows at 17 directions along the source sun/moon path. The client changes
only existing image pixels, not image allocation. APPROX: direction sampling replaces continuous
shader lighting; the far overview and tree shadows retain their bake.

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
from road_layer import points, road_layer, composite, canopy_on_road

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
        p = points(r)  # worker JSON wraps typed arrays in {data: ...}
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


# the ground shader's town lighting (traced): us.city, Bv (TOWN_SHADOW), the sun (Hb), th, or
CITY = {"shadow": 0.58, "shadowPx": 2.8, "shadowMaxPx": 4.6}
TOWN = {"soft": 0.6, "widen": 0.06, "sky": 0.3}
SUN = {"up": 0.62, "north": 0.75, "floor": 0.35}


def sun_shadow(phase):
    """The game's shadow vector for a time of day (0..1), as uCityShadow: tile px a roof level."""
    o = phase % 1
    i = o / SUN["up"] if o < SUN["up"] else (o - SUN["up"]) / (1 - SUN["up"])
    l, c = np.sin(np.pi * i), np.cos(np.pi * i)
    h = np.hypot(c, SUN["north"])
    u = (c / h, -0.75 / h)
    d = 1 / (SUN["floor"] + l)
    f = (-u[0] * d, -u[1] * d)
    n = np.hypot(*f) or 1
    k = min(CITY["shadowMaxPx"], n * CITY["shadowPx"])
    return f[0] / n * k, f[1] / n * k


def shade(img, aux, intile, phase, opacity=None):
    """Bake the shader's close-up town light into the town image: each tile pixel darkened by what the
    buildings round it shut out of the sky (1 - aux.g x 0.3), and every pixel shaded by the roofs toward
    the sun that stand high enough to reach it (the 'towns at real size' walk: a roof of height `high`
    shades a pixel of height `stands` d px away by smoothstep(-soft, soft, (high - stands) x perLevel - d),
    soft = 0.6 + 0.06 d), at strength 0.58. Ground pixels (transparent) get the darkness as black with alpha.
    The sun stands where the game puts it at `phase`; the game turns it through the day, this bake does not."""
    Hh, Ww = img.shape[:2]
    code = img[:, :, 3].astype(np.int32)
    roof = code >= 224
    stands = np.where(roof, aux[:, :, 0].astype(np.float32) * 31.875 / 255, 0).astype(np.float32)
    high = np.where(roof, stands, -1e9).astype(np.float32)
    sx, sy = sun_shadow(phase)
    per = float(np.hypot(sx, sy))
    dx, dy = -sx / per, -sy / per
    top = float(stands.max())
    farthest = int(np.ceil((top * per + TOWN["soft"]) / (1 - TOWN["widen"])))
    sh = np.zeros((Hh, Ww), np.float32)
    for d in range(1, farthest + 1):
        ox, oy = int(np.floor(0.5 + dx * d)), int(np.floor(0.5 + dy * d))
        src = np.full((Hh, Ww), -1e9, np.float32)
        ys, yd = (slice(oy, Hh), slice(0, Hh - oy)) if oy >= 0 else (slice(0, Hh + oy), slice(-oy, Hh))
        xs, xd = (slice(ox, Ww), slice(0, Ww - ox)) if ox >= 0 else (slice(0, Ww + ox), slice(-ox, Ww))
        src[yd, xd] = high[ys, xs]
        soft = TOWN["soft"] + TOWN["widen"] * d
        x = ((src - stands) * per - d + soft) / (2 * soft)
        x = np.clip(x, 0, 1)
        np.maximum(sh, x * x * (3 - 2 * x), out=sh)
    keep = (1 - CITY["shadow"] * sh) * np.where(intile, 1 - aux[:, :, 1].astype(np.float32) / 255 * TOWN["sky"], 1)
    out = np.zeros_like(img)
    opaque = code > 0
    if opacity is not None:
        # Preserve antialiased road coverage. Alpha in img still encodes the source surface type.
        coverage = opacity.astype(np.float32)/255
        alpha = coverage+(1-coverage)*(1-keep)
        for ch in range(3):
            value = img[:, :, ch]*keep*coverage
            np.divide(value,alpha,out=value,where=alpha>0)
            out[:, :, ch] = np.clip(np.round(value),0,255).astype(np.uint8)
        out[:, :, 3] = np.clip(np.round(alpha*255),0,255).astype(np.uint8)
        return out
    for ch in range(3):
        out[:, :, ch] = np.where(opaque, np.round(img[:, :, ch] * keep), 0).astype(np.uint8)
    out[:, :, 3] = np.where(opaque, 255, np.round((1 - keep) * 255)).astype(np.uint8)
    return out


def over(canvas, img, x, y):
    """alpha_composite img onto canvas at (x, y), clipped to the canvas (PIL wants a non-negative spot)."""
    sx, sy = max(0, -x), max(0, -y)
    w, h = min(img.width, canvas.width - x) - sx, min(img.height, canvas.height - y) - sy
    if w <= 0 or h <= 0:
        return
    canvas.alpha_composite(img, (x + sx, y + sy), (sx, sy, sx + w, sy + h))


def xor_patch(base, pixels):
    """Changed RGBA runs, reversible in-place; keep gaps <=8 pixels inside a run to save headers."""
    delta = np.bitwise_xor(np.ascontiguousarray(base).view('<u4').reshape(-1),
                           np.ascontiguousarray(pixels).view('<u4').reshape(-1))
    changed = np.flatnonzero(delta)
    if not len(changed):
        return b''
    cuts = np.flatnonzero(np.diff(changed) > 9) + 1
    out = bytearray()
    for group in np.split(changed, cuts):
        start, end = int(group[0]), int(group[-1]) + 1
        out.extend(struct.pack('<II', start, end - start))
        out.extend(delta[start:end].tobytes())
    return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("city")
    ap.add_argument("--chunk", type=int, default=64)
    ap.add_argument("--dump-town-trees")
    ap.add_argument("--no-shade", action="store_true")
    ap.add_argument("--phase", type=float, default=0.31, help="time of day for the baked shadows: 0.31 is noon (the game's match starts at 0.08, a low morning sun)")
    ap.add_argument("--trees")
    ap.add_argument("--sheet")
    ap.add_argument("--map")
    ap.add_argument("--roads", help="local road-look JSON from export_roads.cjs; joins roads in the town raster")
    ap.add_argument("--output", default=OUT)
    ap.add_argument("--lighting", type=int, default=0,
                    help="APPROX: sample roof shadows at N sun-path intervals; sparse patches reuse image memory (16 recommended)")
    a = ap.parse_args()
    if a.lighting and (a.lighting < 2 or a.lighting % 2 or a.no_shade or a.phase != 0.31):
        raise SystemExit("--lighting needs an even interval count >=2 and the default shaded noon base")
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
    auxAtlas = np.frombuffer(parts["aux"], np.uint8).reshape(head["atlasH"], head["atlasW"], 4) if "aux" in parts else None
    img = np.zeros((H * T, W * T, 4), np.uint8)
    aux = np.zeros((H * T, W * T, 4), np.uint8)
    intile = np.zeros((H * T, W * T), bool)
    for y, x in zip(*np.nonzero(tile)):
        t = tile[y, x] - 1
        ax, ay = (t % per) * T, (t // per) * T
        img[y * T:(y + 1) * T, x * T:(x + 1) * T] = atlas[ay:ay + T, ax:ax + T]
        if auxAtlas is not None:
            aux[y * T:(y + 1) * T, x * T:(x + 1) * T] = auxAtlas[ay:ay + T, ax:ax + T]
        intile[y * T:(y + 1) * T, x * T:(x + 1) * T] = True
    pavement, opacity = None, None
    if a.roads:
        if not a.map:
            raise SystemExit("--roads needs --map")
        m = json.load(open(a.map))
        config = json.load(open(a.roads))
        pavement = np.zeros(img.shape[:2],bool)
        opacity = np.where(img[:,:,3]>0,255,0).astype(np.uint8)
        for cy in range(0,H,a.chunk):
            for cx in range(0,W,a.chunk):
                cw,chh = min(a.chunk,W-cx),min(a.chunk,H-cy)
                layer, mask = road_layer(m,config,cx,cy,cw*T,chh*T,T)
                area = np.s_[cy*T:(cy+chh)*T,cx*T:(cx+cw)*T]
                img[area], opacity[area] = composite(img[area],layer)
                pavement[area] = mask
            print(f"connected roads row {cy}/{H}",flush=True)
    raw_img = img
    if auxAtlas is not None and not a.no_shade:
        img = shade(img, aux, intile, a.phase, opacity)
    else:
        opaque = img[:, :, 3] > 0
        img[:, :, 3] = np.where(opaque,255,0) if opacity is None else opacity
        img[~opaque] = 0

    os.makedirs(a.output, exist_ok=True)
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
            if pavement is not None:
                tree,_ = trees.sprite(td["tile"][i],td["scale"][i])
                if canopy_on_road(tree,round(x*T-tree.width/2),round(y*T-tree.height/2),pavement):
                    continue  # APPROX clearance policy: include yard trees and actual canopy pixels.
            kept += 1
            for bx in {int((x - 1.5) // C), int((x + 1.5) // C)}:
                for by in {int((y - 1.5) // C), int((y + 1.5) // C)}:
                    buckets.setdefault((bx, by), []).append(i)
    def draw_chunk(px, cx, cy):
        mine = buckets.get((cx // C, cy // C), [])
        if not mine:
            return np.ascontiguousarray(px)
        canvas = Image.fromarray(np.ascontiguousarray(px))
        ox, oy = cx * T, cy * T
        for layer in (1, 0):
            for i in mine:
                tree, shadow = trees.sprite(td["tile"][i], td["scale"][i])
                w0 = td["tiles"][td["tile"][i]][2] * td["scale"][i] * TREE_CELLS_PER_PX * T
                left = round(td["x"][i] * T - tree.width / 2) - ox
                top = round(td["y"][i] * T - tree.height / 2) - oy
                if layer == 1:
                    over(canvas, shadow, left + round(w0 * SHADOW["dx"]), top + round(w0 * SHADOW["dy"]))
                else:
                    over(canvas, tree, left, top)
        return np.array(canvas)

    chunks, total, bases = [], 0, {}
    for cy in range(0, H, C):
        for cx in range(0, W, C):
            cw, chh = min(C, W - cx), min(C, H - cy)
            px = img[cy * T:(cy + chh) * T, cx * T:(cx + cw) * T]
            px = draw_chunk(px, cx, cy)
            if not px[:, :, 3].any():
                continue
            data = base64.b64encode(deflate(np.ascontiguousarray(px).tobytes())).decode()
            mod = f"{name}_{cx}_{cy}"
            with open(os.path.join(a.output, mod + ".luau"), "w", newline="\n") as f:
                f.write("--!strict\n-- GENERATED by tools/asset_pipeline/pack_city.py from the game's baked towns. Local only (git-ignored).\n")
                f.write(f'return {{ width = {cw * T}, height = {chh * T}, deflate = "{data}" }}\n')
            chunks.append((cx, cy, cw, chh, mod))
            total += len(data)
            if a.lighting:
                bases[mod] = px.copy()
    if a.lighting:
        if auxAtlas is None:
            raise SystemExit("lighting requires the city's aux height/light data")
        for frame in range(a.lighting + 1):
            lit = shade(raw_img, aux, intile, min(SUN["up"] - 1e-10, SUN["up"] * frame / a.lighting), opacity)
            for cx, cy, cw, chh, mod in chunks:
                pixels = draw_chunk(lit[cy*T:(cy+chh)*T, cx*T:(cx+cw)*T], cx, cy)
                patch = xor_patch(bases[mod], pixels)
                data = base64.b64encode(deflate(patch)).decode()
                with open(os.path.join(a.output, f"{mod}_Light{frame+1}.luau"), "w", newline="\n") as f:
                    f.write('--!strict\n-- GENERATED local-only sparse roof-lighting patch.\n')
                    f.write(f'return {{ bytes = {len(patch)}, deflate = "{data}" }}\n')
            print(f"roof lighting {frame+1}/{a.lighting+1}", flush=True)
    town_trees = np.frombuffer(parts["trees"], np.float32)
    with open(os.path.join(a.output, name + ".luau"), "w", newline="\n") as f:
        f.write("--!strict\n-- GENERATED by tools/asset_pipeline/pack_city.py. Local only (git-ignored).\n")
        f.write("-- chunks: { cx, cy, w, h, module } in cells; trees: x, y pairs in cells (town trees).\n")
        f.write(f'return {{\n\tid = "{mid}", width = {W}, height = {H}, cellPx = {T}, chunkCells = {C},\n\tchunks = {{\n')
        for cx, cy, cw, chh, mod in chunks:
            f.write(f'\t\t{{ {cx}, {cy}, {cw}, {chh}, "{mod}" }},\n')
        f.write("\t},\n")
        if a.roads:
            f.write("\troads = true,\n")
        if a.lighting:
            f.write(f'\tlighting = {{ steps = {a.lighting}, sunUp = {SUN["up"]}, base = {a.lighting//2+1} }},\n')
        f.write("\ttrees = { " + ", ".join(f"{v:.3f}" for v in town_trees) + " },\n}\n")
    print(f"{name}: {W}x{H} cells, {len(chunks)} chunks, {total // 1024} KB, {kept} trees drawn")


if __name__ == "__main__":
    main()
