#!/usr/bin/env python3
"""Pack source frames into runtime atlas pages. Never modifies or resizes the source frames.

  python tools/asset_pipeline/pack_atlas.py <source_dir> [--cols 8] [--padding 0] [--extrude]
         [--max-page 1024] [--luau-name SynVehicleArrow] [--dev-pixels]

Layout: frames in source order (animation, frame, direction); direction i of a row-group goes to
column i % cols, row i // cols. A 16-direction single-frame asset with cols=8 is 8x2.
With padding p, every cell is (frame + 2p) and the frame sits at (p, p) inside it, so the page is
cols*(w+2p) x rows*(h+2p): 960x240 for p=0. --extrude copies the frame's edge pixels into the padding.
Rows that do not fit under --max-page continue on a new page.

Outputs (git-tracked only for synthetic or approved assets):
  assets/sprites/runtime/<id>/r<rev>/p<padding>/atlas_p<N>.png + atlas.json
  src/shared/Assets/Atlases/<LuauName>.luau           frame rectangles + pivot (metadata only)
  src/client/DevAssets/<LuauName>_p<N>.luau           (--dev-pixels) RLE pixels so Studio can show the
                                                      exact packed page through EditableImage without upload
"""
import argparse, base64, os, struct
from PIL import Image
from common import ROOT, load_json, rel, save_json

def rle_rgba(img):
    data = img.tobytes()
    out, n, i = bytearray(), len(data) // 4, 0
    while i < n:
        px = data[i * 4:i * 4 + 4]
        if px[3] == 0:
            px = b"\0\0\0\0"
        j = i + 1
        while j < n and j - i < 65535:
            q = data[j * 4:j * 4 + 4]
            if q[3] == 0:
                q = b"\0\0\0\0"
            if q != px:
                break
            j += 1
        out += struct.pack("<H", j - i) + px
        i = j
    return base64.b64encode(bytes(out)).decode()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source_dir")
    ap.add_argument("--cols", type=int, default=8)
    ap.add_argument("--padding", type=int, default=0)
    ap.add_argument("--extrude", action="store_true")
    ap.add_argument("--max-page", type=int, default=1024)
    ap.add_argument("--luau-name")
    ap.add_argument("--dev-pixels", action="store_true")
    a = ap.parse_args()

    src = load_json(os.path.join(a.source_dir, "source.json"))
    fw, fh, p = src["frameWidth"], src["frameHeight"], a.padding
    cw, ch = fw + 2 * p, fh + 2 * p
    ndir = src["directions"]["count"]
    if ndir % a.cols:
        raise SystemExit(f"{ndir} directions do not divide into {a.cols} columns")
    rows_per_group = ndir // a.cols
    order = sorted(src["frames"], key=lambda f: ([x["name"] for x in src["animations"]].index(f["animation"]),
                                                  f["frame"], f["direction"]))
    groups = len(order) // ndir
    page_w = a.cols * cw
    if page_w > a.max_page:
        raise SystemExit(f"page width {page_w} exceeds {a.max_page}")
    rows_per_page = (a.max_page // ch) // rows_per_group * rows_per_group
    out_dir = os.path.join(ROOT, "assets", "sprites", "runtime", src["assetId"], f"r{src['revision']}", f"p{p}")
    pages, frames = [], []
    total_rows = groups * rows_per_group
    for page in range((total_rows + rows_per_page - 1) // rows_per_page):
        rows = min(rows_per_page, total_rows - page * rows_per_page)
        pages.append({"page": page, "file": f"atlas_p{page}.png", "width": page_w, "height": rows * ch,
                      "image": Image.new("RGBA", (page_w, rows * ch), (0, 0, 0, 0))})
    for k, f in enumerate(order):
        img = Image.open(os.path.join(a.source_dir, f["file"])).convert("RGBA")
        if img.size != (fw, fh):
            raise SystemExit(f"{f['file']} is {img.size}, expected {(fw, fh)}: source frames are never resized")
        group, d = divmod(k, ndir)
        row = group * rows_per_group + d // a.cols
        page, row_in_page = divmod(row, rows_per_page)
        x = (d % a.cols) * cw + p
        y = row_in_page * ch + p
        canvas = pages[page]["image"]
        if a.extrude and p:
            for dx, dy in ((-p, 0), (p, 0), (0, -p), (0, p), (-p, -p), (p, p), (-p, p), (p, -p)):
                canvas.paste(img, (x + dx, y + dy))
        canvas.paste(img, (x, y))
        frames.append({"animation": f["animation"], "frame": f["frame"], "direction": d, "page": page,
                       "x": x, "y": y, "w": fw, "h": fh, "source": f["file"]})
    os.makedirs(out_dir, exist_ok=True)
    for pg in pages:
        pg["image"].save(os.path.join(out_dir, pg["file"]), optimize=True)
    meta = {"assetId": src["assetId"], "revision": src["revision"], "synthetic": src.get("synthetic", False),
            "frameWidth": fw, "frameHeight": fh, "padding": p, "extruded": bool(a.extrude and p),
            "columns": a.cols, "pivot": src["pivot"], "directions": src["directions"],
            "animations": src["animations"],
            "pages": [{k: v for k, v in pg.items() if k != "image"} for pg in pages],
            "frames": frames, "sourceDir": rel(a.source_dir)}
    save_json(os.path.join(out_dir, "atlas.json"), meta)
    print(f"{len(frames)} frames -> {len(pages)} page(s) {[(pg['width'], pg['height']) for pg in pages]} in {rel(out_dir)}")

    if a.luau_name:
        L = ["--!strict", f"-- GENERATED by tools/asset_pipeline/pack_atlas.py from {rel(out_dir)}/atlas.json. Do not edit.",
             "return {", f'\tassetId = "{src["assetId"]}",', f"\trevision = {src['revision']},",
             f"\tframeWidth = {fw},", f"\tframeHeight = {fh},", f"\tpadding = {p},", f"\tcolumns = {a.cols},",
             f"\tdirections = {ndir},", "\tdirectionZero = \"east\", -- index 0 faces +x, indices go clockwise on screen",
             f"\tpivot = {{ x = {src['pivot']['x']}, y = {src['pivot']['y']} }}, -- pixels from the frame top-left",
             "\tpages = {"]
        for pg in pages:
            L.append(f"\t\t{{ width = {pg['width']}, height = {pg['height']}, robloxAssetId = nil :: number?, "
                     f"devPixels = \"{a.luau_name}_p{pg['page']}\" }},")
        L.append("\t},")
        L.append("\t-- frames[animation][frame + 1][direction + 1] = { page + 1, x, y }")
        L.append("\tframes = {")
        anims = {}
        for f in frames:
            anims.setdefault(f["animation"], {}).setdefault(f["frame"], {})[f["direction"]] = f
        for name, fr in anims.items():
            L.append(f"\t\t{name} = {{")
            for fi in sorted(fr):
                cells = ", ".join(f"{{ {fr[fi][d]['page'] + 1}, {fr[fi][d]['x']}, {fr[fi][d]['y']} }}" for d in sorted(fr[fi]))
                L.append(f"\t\t\t{{ {cells} }},")
            L.append("\t\t},")
        L += ["\t},", "}"]
        mod = os.path.join(ROOT, "src", "shared", "Assets", "Atlases", f"{a.luau_name}.luau")
        os.makedirs(os.path.dirname(mod), exist_ok=True)
        open(mod, "w", encoding="utf-8", newline="\n").write("\n".join(L) + "\n")
        print("wrote", rel(mod))
        if a.dev_pixels:
            for pg in pages:
                path = os.path.join(ROOT, "src", "client", "DevAssets", f"{a.luau_name}_p{pg['page']}.luau")
                os.makedirs(os.path.dirname(path), exist_ok=True)
                open(path, "w", encoding="utf-8", newline="\n").write(
                    "--!strict\n-- GENERATED by tools/asset_pipeline/pack_atlas.py --dev-pixels. Synthetic art only.\n"
                    "-- RLE RGBA: repeated (u16 LE count, r, g, b, a), base64. Decoded by Shared.Utilities.PixelCodec.\n"
                    f"return {{ width = {pg['width']}, height = {pg['height']}, rle = \"{rle_rgba(pg['image'])}\" }}\n")
                print("wrote", rel(path), os.path.getsize(path), "bytes")

if __name__ == "__main__":
    main()
