"""Pack locally evaluated tree-damage art plus the exact tree list retained by pack_city.

All generated output belongs under ignored GameData. Original art/settings are supplied at runtime.
Source poses use the game's quantized root coordinates/key and source canopy width. Existing baked
placement remains in drawX/drawY to preserve the current port's static tree alignment.
"""
import base64
import json
import math
import os
import struct
import zlib

from PIL import Image


def lua(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        if not math.isfinite(value):
            raise ValueError("non-finite generated value")
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, list):
        return "{" + ",".join(map(lua, value)) + "}"
    return "{" + ",".join("[" + json.dumps(str(k)) + "]=" + lua(v) for k, v in value.items()) + "}"


def packed(data):
    c = zlib.compressobj(9, zlib.DEFLATED, -15)
    return base64.b64encode(c.compress(data) + c.flush()).decode()


def write(directory, name, data):
    os.makedirs(directory, exist_ok=True)
    with open(os.path.join(directory, name + ".luau"), "w", newline="\n") as f:
        f.write("-- GENERATED original tree data/art; local only, git-ignored.\nreturn " + lua(data) + "\n")


def export_forest(map_id, width, height, tile_px, td, kept, trees, damage_path, output):
    with open(damage_path, encoding="utf-8") as source:
        settings = json.load(source)
    with Image.open(os.path.join(os.path.dirname(damage_path), "tree-damage.png")) as source:
        atlas = source.convert("RGBA")
    cache, families, pixels, rows, keys, records = {}, [], bytearray(), bytearray(), set(), []
    root_scale = settings["scale"]
    for i in sorted(kept):  # original cell-query insertion order, rather than display sort order
        tile, scale = td["tile"][i], td["scale"][i]
        standing, _ = trees.sprite(tile, scale)
        family_key = (tile, scale)
        family_id = cache.get(family_key)
        if family_id is None:
            family_id = len(families) + 1
            source_width = td["tiles"][tile][2] * scale * root_scale * tile_px
            family = {"shadowX": round(source_width * settings["shadow"]["dx"]),
                      "shadowY": round(source_width * settings["shadow"]["dy"])}
            for kind in ("standing", "fallen", "stump", "burnt"):
                if kind == "standing":
                    image = standing
                else:
                    x, y, w, h = settings["frames"][kind][tile]
                    image = atlas.crop((x, y, x + w, y + h)).resize(
                        (max(1, round(w * scale * root_scale * tile_px)),
                         max(1, round(h * scale * root_scale * tile_px))), Image.Resampling.LANCZOS)
                family[kind] = {"offset": len(pixels), "w": image.width, "h": image.height}
                pixels.extend(image.tobytes())
            families.append(family)
            cache[family_key] = family_id
        if family_id > 65535:
            raise ValueError("too many forest sprite families")
        x, y = td["x"][i], td["y"][i]
        gx, gy = math.floor(x / root_scale + .5), math.floor(y / root_scale + .5)
        key = gy * settings["keyStride"] + gx
        if key in keys:
            raise ValueError("duplicate original tree key")
        keys.add(key)
        size = settings["tiles"][tile]["w"] * scale * root_scale
        cell = math.floor(y) * width + math.floor(x)
        if not (0 <= x < width and 0 <= y < height and 0 <= cell < width * height):
            raise ValueError("tree outside map")
        rows.extend(struct.pack("<ddddIH2xii", key, gx * root_scale, gy * root_scale, size,
                                cell, family_id, round(x * tile_px - standing.width / 2),
                                round(y * tile_px - standing.height / 2)))
        records.append({"key": key, "x": gx*root_scale, "y": gy*root_scale, "size": size, "cell": cell})
    name = "Forest_" + map_id
    pages = []
    for offset in range(0, len(pixels), 512 * 1024):
        part = bytes(pixels[offset:offset + 512 * 1024])
        page = name + "_Pixels" + str(len(pages) + 1)
        write(output, page, {"deflate": packed(part)})
        pages.append({"name": page, "offset": offset, "bytes": len(part)})
    meta = {"id": map_id, "width": width, "height": height, "tileSize": tile_px,
            "count": len(kept), "stride": 48, "trees": packed(rows), "families": families,
            "pixelBytes": len(pixels), "pixelParts": pages, "shadow": settings["shadow"],
            "fallenAnchor": settings["fallenAnchor"], "charColors": settings["charColors"]}
    write(output, name, meta)
    # Pose references are original-game outputs; raster adaptation tests use these local values.
    write(output, name + "Vectors", {"poses": settings["refs"], "settings": settings, "count": len(kept),
                                    "samples": [{"index": i+1, **records[i]} for i in
                                                [(n*7919+177) % len(records) for n in range(min(2000,len(records)))]]})
    print(f"dynamic forest: {len(kept)} trees, {len(families)} sprite families, {len(pixels)} raw sprite bytes", flush=True)
    return name
