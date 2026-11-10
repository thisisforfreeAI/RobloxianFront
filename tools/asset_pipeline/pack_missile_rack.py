"""Generate local Republic artillery looks from your read-only game install.

python tools/asset_pipeline/pack_missile_rack.py <install>
Requires Node, Pillow and numpy; uses the existing unit rim/shadow packer. Generated strips, specs
and DevAssets remain git-ignored. --project-root/--output-root permit isolated staging.
"""
import argparse
from io import BytesIO
import importlib.util
import json
from pathlib import Path
import struct
import subprocess

from PIL import Image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("install", type=Path)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output-root", type=Path)
    args = parser.parse_args()
    project = args.project_root.resolve()
    output = (args.output_root or project).resolve()
    install = args.install.resolve()
    if output == install or install in output.parents:
        raise ValueError("output must stay outside the original install")
    with (install / "resources/app.asar").open("rb") as f:
        _, header_size, _, json_len = struct.unpack("<IIII", f.read(16))
        dist = json.loads(f.read(json_len))["files"]["dist"]["files"]
        assets = dist["assets"]["files"]
        bundles = [entry for name, entry in assets.items() if name.startswith("main-") and name.endswith(".js")]
        if len(bundles) != 1:
            raise ValueError("expected one main bundle")
        entry = bundles[0]
        f.seek(8 + header_size + int(entry["offset"]))
        bundle = f.read(entry["size"])
        script = r"""
const fs=require('fs'),vm=require('vm'),s=fs.readFileSync(0,'utf8');
function object(pattern){const m=pattern.exec(s);if(!m)throw Error('table not found');let depth=0;
for(let i=m.index;i<s.length;i++){const c=s[i];if(c==='"'||c==="'"||c==='`'){const q=c;while(++i<s.length&&s[i]!==q)if(s[i]==='\\')i++;}
else if(c==='{')depth++;else if(c==='}'&&--depth===0)return vm.runInNewContext('('+s.slice(m.index,i+1)+')',{}, {timeout:1000});}throw Error('unbalanced');}
const table=object(/\{frame:120,facings:16,units:/),style=object(/\{shadow:\{alpha:[^,]+,gun:/);
const keys=['rep_artillery','rep_artillery_set1','rep_artillery_set2','rep_artillery_empty'];
console.log(JSON.stringify({frame:table.frame,facings:table.facings,scale:style.scale,units:Object.fromEntries(keys.map(k=>[k,table.units[k]]))}));
"""
        meta = json.loads(subprocess.check_output(["node", "-e", script], input=bundle))
        entry = dist["tiles"]["files"]["units-top-republic.png"]
        f.seek(8 + header_size + int(entry["offset"]))
        sheet = Image.open(BytesIO(f.read(entry["size"]))).convert("RGBA")
    frame = meta["frame"]
    if sheet.width != meta["facings"] * frame:
        raise ValueError("unexpected source-sheet width")
    # Keep every extracted table/strip out of committed files.
    folder = output / "assets/sprites/source/original/unit_rep_artillery/r1"
    folder.mkdir(parents=True, exist_ok=True)
    private = output / "docs/private"
    private.mkdir(parents=True, exist_ok=True)
    module_spec = importlib.util.spec_from_file_location("pack_original", project / "tools/asset_pipeline/pack_original.py")
    packer = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(packer)
    packer.ROOT, packer.OUT = str(output), str(output / "src/client/DevAssets")
    spec = {}
    for state, source in [("rep_loaded", "rep_artillery"), ("rep_set1", "rep_artillery_set1"), ("rep_set2", "rep_artillery_set2"), ("rep_empty", "rep_artillery_empty")]:
        unit = meta["units"][source]
        if not unit or unit.get("sheet") != "republic":
            raise ValueError(f"missing Republic source look: {source}")
        row = unit["row"]
        if (row + 3) * frame > sheet.height:
            raise ValueError(f"look outside source sheet: {source}")
        paths = {}
        for offset, layer in enumerate(("colour", "paint", "shape")):
            target = folder / f"{state}_{layer}.png"
            sheet.crop((0, (row + offset) * frame, sheet.width, (row + offset + 1) * frame)).save(target)
            paths[layer] = target.relative_to(output).as_posix()
        name = "OrigArtillery_" + state
        spec[name] = {"frame": frame, "strips": [[state + "_colour", paths["colour"]], [state + "_paint", paths["paint"]]]}
        for suffix, op, scale in [("Rim", "rim", 1), ("RimHalf", "rim_half", 2), ("Shade", "shade", 3)]:
            spec[name + suffix] = {"frame": frame, "scale": scale, "strips": [[state, paths["shape"], op]]}
        for module in (name, name + "Rim", name + "RimHalf", name + "Shade"):
            data = spec[module]
            packer.pack(module, frame, data["strips"], scale=data.get("scale", 1))
        # State frames can have different art bounds; carry the source-derived geometry with the art.
        target = output / "src/client/DevAssets" / (name + ".luau")
        text = target.read_text()
        dimensions = (f'\tcells = {unit["cells"] * meta["scale"] / unit["art"]["w"]!r}, '
                      f'size = {unit["cells"] * meta["scale"]!r}, artH = {unit["art"]["h"] / unit["art"]["w"]!r},\n')
        target.write_text(text.replace("return {\n", "return {\n" + dimensions, 1), newline="\n")
        print(f"{source} -> {name}, {meta['facings']} facings with rim/half-rim/shadow")
    (private / "sprite_spec_missile.json").write_text(json.dumps(spec, indent=1) + "\n")
    (private / "missile_rack_source.json").write_text(json.dumps(meta, indent=1) + "\n")


if __name__ == "__main__":
    main()
