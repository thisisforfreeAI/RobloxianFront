"""Bake cropped soldier rims/shapes from local strips; all generated outputs are git-ignored.

Usage: python tools/asset_pipeline/pack_men_fx.py <install> <private sprite spec.json>
Requires Pillow, numpy and Node. Reads the game install only. Does not change existing sprite modules.
Optional --source-root and --output-root allow staging without touching the served project.
"""
import argparse
import base64
import json
import math
from pathlib import Path
import struct
import subprocess

import numpy as np
from PIL import Image


def lua(v):
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (str, int, float)):
        return json.dumps(v)
    if isinstance(v, list):
        return "{" + ",".join(map(lua, v)) + "}"
    return "{" + ",".join("[" + json.dumps(k) + "]=" + lua(x) for k, x in v.items()) + "}"


def config_from_install(install):
    with (install / "resources/app.asar").open("rb") as f:
        _, header_size, _, json_len = struct.unpack("<IIII", f.read(16))
        entries = json.loads(f.read(json_len))["files"]["dist"]["files"]["assets"]["files"]
        matches = [v for k, v in entries.items() if k.startswith("main-") and k.endswith(".js")]
        if len(matches) != 1:
            raise ValueError("expected one main bundle")
        entry = matches[0]
        f.seek(8 + header_size + int(entry["offset"]))
        bundle = f.read(entry["size"])
    # Evaluate only the literal objects located by their field structure, never the whole bundle.
    js = r"""
const fs=require('fs'),vm=require('vm'),s=fs.readFileSync(0,'utf8');
function obj(pattern){
 const m=pattern.exec(s);if(!m)throw Error('table not found: '+pattern);
 const at=m.index;let depth=0;
 for(let i=at;i<s.length;i++){
  const c=s[i];if(c==='"'||c==="'"||c==='`'){const q=c;while(++i<s.length&&s[i]!==q)if(s[i]==='\\')i++;}
  else if(c==='{')depth++;else if(c==='}'&&--depth===0)return vm.runInNewContext('('+s.slice(at,i+1)+')',{}, {timeout:1000});
 }throw Error('unbalanced table');
}
const men=obj(/\{frame:48,facings:16,sheet:/),style=obj(/\{shadow:\{alpha:[^,]+,up:/),sun=obj(/\{maxReach:[^,]+,nightFade:/);
console.log(JSON.stringify({...style,art:men.art,length:men.length,frame:men.frame,facings:men.facings,maxReach:sun.maxReach}));
"""
    return json.loads(subprocess.check_output(["node", "-e", js], input=bundle))


def rim(cell, radius, color):
    # The game's jht: sixteen source-over copies on a circle plus the original, tinted source-in.
    keep = np.ones(cell.size[::-1], dtype=np.float64)
    for k in range(16):
        angle = k / 16 * math.tau
        shifted = cell.transform(cell.size, Image.Transform.AFFINE,
                                 (1, 0, -math.cos(angle) * radius, 0, 1, -math.sin(angle) * radius),
                                 resample=Image.Resampling.BILINEAR)
        keep *= 1 - np.asarray(shifted.getchannel("A"), dtype=np.float64) / 255
    keep *= 1 - np.asarray(cell.getchannel("A"), dtype=np.float64) / 255
    out = Image.new("RGBA", cell.size, color + (0,))
    out.putalpha(Image.fromarray(np.round((1 - keep) * 255).astype(np.uint8)))
    return out


def rle(page):
    pixels = page.tobytes()
    result = bytearray()
    i = 0
    while i < len(pixels):
        px, count = pixels[i:i+4], 1
        i += 4
        while i < len(pixels) and count < 65535 and pixels[i:i+4] == px:
            count += 1
            i += 4
        result += struct.pack("<H", count) + px
    return base64.b64encode(result).decode("ascii")


def pack(name, spec, config, source_root):
    frame = config["frame"]
    color = tuple(bytes.fromhex(config["rim"]["colour"].lstrip("#")))
    items, poses = [], {}
    for label, path, *_ in spec["strips"]:
        if not label.endswith("_colour"):
            continue
        pose = label[:-len("_colour")]
        shape_path = source_root / path.replace("_colour.png", "_shape.png")
        with Image.open(shape_path) as im:
            strip = im.convert("RGBA")
        if strip.size != (config["facings"] * frame, frame):
            raise ValueError(f"unexpected shape strip dimensions: {shape_path}")
        poses[pose] = {key: [] for key in ("rim", "rimHalf", "shade", "shadeHalf")}
        for facing in range(config["facings"]):
            cell = strip.crop((facing * frame, 0, (facing + 1) * frame, frame))
            # APPROX: BOX half-size resampling follows the existing unit pipeline; Canvas uses its
            # high-quality drawImage filter, so edge alpha can differ slightly.
            layers = {
                "rim": rim(cell, config["rim"]["px"], color),
                "rimHalf": rim(cell, config["rim"]["halfPx"], color).resize((frame//2, frame//2), Image.Resampling.BOX),
                "shade": cell,
                "shadeHalf": cell.resize((frame//2, frame//2), Image.Resampling.BOX),
            }
            for key, image in layers.items():
                bounds = image.getbbox()
                rect = [0, 0, 0, 0, 0, 0, image.width]
                if bounds:
                    crop = image.crop(bounds)
                    rect[2:6] = [crop.width, crop.height, bounds[0], bounds[1]]
                    items.append((crop, rect))
                poses[pose][key].append(rect)
    # Sort tall rectangles first and shelf-pack, with a transparent texel gutter around every crop.
    width, x, y, row = 512, 1, 1, 0
    placements = []
    for image, rect in sorted(items, key=lambda item: item[0].height, reverse=True):
        if x + image.width + 1 > width:
            x, y, row = 1, y + row + 2, 0
        if y + image.height + 1 > 1024:
            raise ValueError(f"{name}: cropped masks exceed one EditableImage")
        rect[0:2] = [x, y]
        placements.append((image, x, y))
        row = max(row, image.height)
        x += image.width + 2
    height = y + row + 1
    page = Image.new("RGBA", (width, height))
    for image, x, y in placements:
        page.paste(image, (x, y))
    return {"width": width, "height": height, "poses": poses, "rle": rle(page)}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("install", type=Path)
    p.add_argument("spec", type=Path)
    p.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[2])
    p.add_argument("--output-root", type=Path)
    args = p.parse_args()
    source = args.source_root.resolve()
    output = (args.output_root or source).resolve()
    install = args.install.resolve()
    if output == install or install in output.parents:
        raise ValueError("output must stay outside the game install")
    config = config_from_install(install)
    targets = [(output / "src/shared/GameData/MenFx.luau", config)]
    total = 0
    for name, spec in json.loads(args.spec.read_text()).items():
        if not name.startswith("OrigMen"):
            continue
        meta = pack(name, spec, config, source)
        targets.append((output / f"src/client/DevAssets/{name}Fx.luau", meta))
        size = meta["width"] * meta["height"] * 4
        total += size
        print(f"{name}Fx: {meta['width']}x{meta['height']}, {len(meta['poses'])} poses, {size//1024} KiB raw")
    for target, data in targets:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("-- Generated from your local install/shape strips; git-ignored.\nreturn " + lua(data) + "\n", newline="\n")
    print(f"All figure masks: {total/1048576:.2f} MiB raw; loaded per figure when first drawn.")


if __name__ == "__main__":
    main()
