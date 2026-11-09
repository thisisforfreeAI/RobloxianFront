#!/usr/bin/env python3
"""Regenerate all WarFront-derived data from your own WarFront install.
These outputs are git-ignored (see .gitignore); run this once after cloning.

Usage (from the repo root):
  python tools/conversion/generate_all.py "A:\\SteamLibrary\\steamapps\\common\\WarFront Demo"
Needs Python 3.9+ and Node.js 18+. Reads the install, never writes to it.
"""
import glob, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
GAMEDATA = os.path.join(ROOT, "src", "shared", "GameData")
MAPS = ["saddle"]  # designed maps to export; add more as milestones need them

def run(*args):
    print("+", " ".join(args))
    subprocess.run(args, check=True)

def main(install):
    asar = os.path.join(install, "resources", "app.asar")
    if not os.path.isfile(asar):
        sys.exit(f"app.asar not found under {install}")
    os.makedirs(os.path.join(GAMEDATA, "Maps"), exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        app = os.path.join(tmp, "app")
        run(sys.executable, "-I", os.path.join(HERE, "extract_asar.py"), asar, app)
        dist = os.path.join(app, "dist")
        tsv = os.path.join(tmp, "rules.tsv")
        run(sys.executable, "-I", os.path.join(HERE, "extract_rules.py"), os.path.join(dist, "modding-guide.html"), tsv)
        run(sys.executable, "-I", os.path.join(HERE, "rules_to_luau.py"), tsv,
            os.path.join(GAMEDATA, "RulesData.luau"))
        run(sys.executable, "-I", os.path.join(HERE, "extract_catalog.py"), dist, GAMEDATA)
        worker = glob.glob(os.path.join(dist, "assets", "genWorker-*.js"))
        if len(worker) != 1:
            sys.exit(f"expected one genWorker bundle, found {worker}")
        for map_id in MAPS:
            out_json = os.path.join(tmp, f"{map_id}.json")
            run("node", os.path.join(HERE, "export_map.cjs"), worker[0], map_id, out_json)
            module = map_id[0].upper() + map_id[1:] + ".luau"
            run(sys.executable, "-I", os.path.join(HERE, "convert_map.py"), out_json,
                os.path.join(GAMEDATA, "Maps", module))
    print("done: generated data is in src/shared/GameData (git-ignored)")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
