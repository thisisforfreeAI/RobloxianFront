# RobloxianFront

Roblox port of WarFront (authorized). Luau, synced with [Rojo](https://rojo.space).

## Setup

1. Install the toolchain: `rokit install` (Rojo 7.4.4, Lune).
2. Generate the WarFront-derived data from your own install into `src/shared/GameData/` (git-ignored, never committed):
   `python tools/conversion/generate_all.py "A:\SteamLibrary\steamapps\common\WarFront Demo"`
3. Build a place: `rojo build default.project.json -o build/RobloxianFront.rbxlx`, or `rojo serve` and connect from Studio.
4. Tests: `lune run tests/run`

## Layout

- `src/shared`: pure modules used by server and client (rules, map codec, protocol, RNG, movement).
- `src/server`: authoritative match loop (20 Hz) and networking.
- `src/client`: camera, rendering, selection, HUD.
- `src/shared/GameData`: generated from your install (rules, unit catalog, locked constants, maps). Git-ignored.
- `tools/conversion`: extraction/conversion scripts (read-only on the game install).
- `tools/asset_pipeline`: sprite packing and validation (`docs/asset_requests/README.md`).
- `docs/`: status, renderer decision, Studio tests (`STUDIO_TESTS.md`), Git setup (`GIT_SETUP.md`), sprite conventions, asset requests.
- `docs/private/`: audit reports that quote the game's files. Git-ignored, kept locally.

## Rules for this repo

- **Public repo:** no original WarFront files (art, audio, extracted tables, audit excerpts) are committed until the rights scope says so. Generated data and `docs/private/` are git-ignored.
- All art is **placeholder** until approved assets are integrated.
