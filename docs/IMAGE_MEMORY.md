# EditableImage residency and static-image migration

This batch reduces native editable storage used by unit masks, makes resident sprite quality follow camera visibility and memory pressure, and prepares an optional regular Roblox Image backend. The initial package was prepared without IDs; on 2026-11-13 all 368 PNGs were uploaded through Studio and the complete 473-binding ID module was installed. Start a fresh Play session after sync to load it. PNGs, IDs and source-derived metadata remain private and ignored by Git.

## Runtime behavior

- Soldier rim/shadow atlases now have real half/quarter native images with repacked crop rectangles and transparent gutters. Logical size and pivots retain the source geometry. All 11 figure-effect families total about 8.52 MiB RGBA at full resolution, 2.64 MiB at half, or 0.97 MiB at quarter. These are allocation estimates if every family is resident, not measured Player memory or guaranteed match savings.
- Pages visible within a padded camera area retain zoom-selected quality. Pages unseen for 0.75 seconds target quarter resolution. Shared pages stay sharp if any current owner is visible. A 0.3-second tier hold limits thrashing; camera margins prewarm nearby art.
- Pressure raises the minimum sprite stride: optional masks degrade before core bodies. Native refusal holds the strongest level for at least 8 seconds; sustained calm is required before recovering one level. Night lights, windows, civilians, smoke and weather presentation use optional detail admission. Fog and terrain coverage retain their existing protections/reserve.
- Bodies and cropped masks share one cooperative preparation job and at most one pending replacement upload. Existing content is rebound only after a complete replacement is ready; the old native image is then destroyed. If a smaller optional mask cannot coexist with its old image, its labels are detached and temporarily hidden before the old image is released. Core unit bodies keep their existing content on refusal.
- After a native allocation refusal, another native attempt requires a real tracked release. Timers and requests from other owners cannot repeatedly probe the native API. A core recovery attempt is allowed only after actual reclamation. LOD work also remembers the release epoch, so it does not repeatedly decode a refused tier. Published API permission failures retain the existing separate session latch.

The default 48 MiB total/16 MiB detail policies and reserved headroom are application choices, **not Roblox device limits**. The engine can refuse earlier. This work does not establish that a specific device no longer produces warnings; compare actual Player behavior using B306–B308.

## Private PNG package and importing IDs

The prepared package is `build/static-images/`: 473 atlas bindings share 368 unique PNGs (about 11.7 MiB on disk). `manifest.json` describes each binding, its source signature, dimensions, PNG hash and canonical alias; `image_ids.json` contains one blank slot per unique image. Unchanged unit/figure/mask/wreck/structure/death atlases are supported. Dynamic ground damage, fog and lighting canvases remain editable.

Run the following from the project root with Python 3 and Pillow/NumPy available. Set `python` to your installed interpreter if the Windows alias is unavailable.

Regenerate after repacking local source art:

```powershell
python tools/asset_pipeline/pack_men_fx_lods.py src/client/DevAssets
python tools/asset_pipeline/static_image_package.py export --source src/client/DevAssets --output build/static-images
```

Upload the canonical PNGs as **Image assets** under the experience's creator account/group, using Studio Asset Manager or the optional owner-run Open Cloud helper. Enter the returned **Image IDs**, as quoted decimal strings, in `build/static-images/image_ids.json`. Decal/container IDs do not substitute for the underlying image. Partial imports are supported: unmapped art keeps its local editable path.

The helper defaults to a dry-run and makes no network requests:

```powershell
python tools/asset_pipeline/static_image_upload.py build/static-images
```

For an actual upload, set `ROBLOX_ASSET_API_KEY` locally, supply the owning creator ID, and add `--execute`. Use `--group-id` instead of `--user-id` for a group-owned experience. Never put credentials in a package or source file. The helper uses the official Assets API, requests Image assets with expected price zero, serializes uploads, saves operation paths before polling and resumes pending operations after a processing timeout. It saves each successful ID before proceeding. It does not publish the place.

```powershell
python tools/asset_pipeline/static_image_upload.py build/static-images --user-id YOUR_CREATOR_ID --execute
python tools/asset_pipeline/static_image_package.py import --package build/static-images --ids build/static-images/image_ids.json --output src/shared/GameData/StaticImageIds.luau
```

Restart Play/rejoin after syncing the generated ID module; publish the updated place when ready for Player testing. Uploading PNGs alone does not activate the backend. The initial implementation did not upload assets. The later owner-authorized Studio upload/import completed on 2026-11-13: all 368 unique PNGs now have Image IDs, and all 473 bindings are in the private ID module. No API key was used and the place was not published.

The importer validates package hashes, path containment, IDs and conflicting assignments. Aliases inherit their canonical image ID. A re-export preserves entered IDs only for unchanged PNG hashes; changed art needs a new/revalidated upload. Runtime checks dimensions and source signatures, preloads one requested image at a time, and uses `Content.fromUri` only after success. Refused/unavailable/stale assets keep the local fallback and failed requests cool down. A resident regular image is never replaced by an EditableImage simply because another uploaded quality tier is absent. Initial structure pages wait for a configured preload; native structure fallbacks already installed in that session are not hot-migrated, so restart after import/recovery for a clean comparison.

Regular images avoid this native **EditableImage** allocation pool. They still consume ordinary Roblox texture/cache memory and can be affected by upload permissions, moderation, asset filtering and streaming. The source pixel package is lossless; complete native visual parity is unverified.

## Diagnostics

From an actual client LocalScript diagnostic context, inspect (Studio's command bar can require a separate module cache and report different residency):

```luau
local rendering = game.Players.LocalPlayer.PlayerScripts.Client.Rendering
print(require(rendering.ImageMemory).pressureStats())
print(require(rendering.SpriteBank).stats())
```

`pressureStats()` reports estimated editable bytes, detail/terrain use, learned ceiling, quality level (0/1/2), native refusals, suppressed attempts, actual release epoch and owner byte/count totals. `SpriteBank.stats()` reports native bytes, full/half/quarter pages, offscreen pages, pending work and regular-image cache ready/loading/failure counts. Estimates exclude normal image textures, Lua data, instances and other engine memory. There is no per-frame diagnostic print loop.

## Validation and remaining native checks

The focused runtime suite covers pressure hysteresis, cropped UV swaps, suspension/recovery, core refusal retention, release-gated retries, one pending image, publication rollback, regular-image migration/fallback and cold loading without native allocation. Synthetic Python cases cover literal-only parsing, crop gutters, PNG round-trips/deduplication, stale PNG/ID rejection, path guards, exact string IDs, Image upload responses, persisted operation recovery and timeout behavior. Source art was not modified. All 10,112 derivative crop mappings were validated and an 11-family mask comparison was visually inspected as a CPU preview.

Verification on the installed project: 887 Lune tests passed, 24 Python packer/package tests passed, all 44 staged runtime/shared/derivative modules compiled (syntax only), and Rojo build succeeded.

Native Studio/Player checks B306–B308 remain required, including real permissions, actual upload/preload behavior, camera motion, UV/filtering and pressure recovery under a large mixed battle. Headless tests and Rojo build do not measure live CPU/GPU memory or frame times.

Roblox references: [EditableImage memory limits](https://create.roblox.com/docs/reference/engine/classes/EditableImage#memory-limits), [Content](https://create.roblox.com/docs/reference/engine/datatypes/Content), [Assets API usage](https://create.roblox.com/docs/cloud/guides/usage-assets).


## Completed owner-authorized upload (2026-11-13)

Uploaded the 368 canonical PNGs through Studio Asset Manager under jonathan343435. A pilot image was uploaded first, then the remaining 367. Exported Studio Image metadata, reconciled the recent-upload backup with the full inventory, and retrieved the final unindexed ID directly from its completed import row. Strict validation found 368 exact atlas-name mappings, no missing or unknown images, no conflicting IDs, valid PNG hashes and 473 resolved bindings including aliases. The private JSON and Luau ID module are installed, the module compiles, and its exact source is included once in a successful Rojo build. No API key, commit, push or place publishing was used.

This establishes actual upload and local import/build success. The subsequent native verification below establishes sampled Studio preload and consumer adoption. Complete filtering/visual parity, published-player permissions and pressure/performance behavior remain unverified. Start a fresh Play session after Rojo sync; publish the updated place before testing the new configuration in Roblox Player.

## Native preload and consumer verification (2026-11-13)

Studio's existing Rojo connection had missed the new ID module/source updates. Disconnecting and reconnecting the plugin restored the current source; the next check found all 473 bindings. Restarting Play alone had not repaired that stale connection.

Native checks then found bare URI-string preload requests returning Failure for both an uploaded Image and a public Roblox control image. The same requests succeeded through typed ImageLabel content. StaticImages now preloads one temporary, unparented ImageLabel with ImageContent set to the URI, destroys it after success/failure, and only publishes the cached content on success. It creates no EditableImage. Failure cooldown, serialization and local fallbacks remain intact. StructureTokens and BuildPreview also now prefer the sheet's hosted Content instead of passing its metadata proxy to Content.fromObject; this removes the repeated building-token nil-content error once hosted art becomes available.

In fresh Studio Play, a temporary real client LocalScript loaded 10/10 samples covering tank tiers, rifle/mask/death art and both structure armies/weapon pages. A later live consumer check passed distant/detailed/distant barracks preview transitions (2/44/2 visible hosted layers), verified 3 visible hosted structure-token labels, and reported 35 ready static assets with zero failures/rejections. All 19 resident SpriteBank pages were external (4 half, 15 quarter), with zero native EditableImage bytes in that bank. Map/fog/dynamic canvases still use editable storage; this is not a zero-total-memory claim. Temporary probes were removed with the test session.

Verification: 38 focused checks pass, the full Lune suite reports 894 passed / 0 failed, all three changed runtime modules compile (syntax only), and the installed Rojo build succeeds. Seven new regressions cover the actual typed preload adapter's cleanup/error/serialization paths and hosted/native token/preview transitions. This does not test all 368 images, published Player access, exhaustive UV/filtering parity or large-battle CPU/total-memory savings. B306-B308 retain those pending checks. Unrelated legacy place bootstrap waits and installed-plugin warnings were observed; this batch does not change those place/plugin objects. No publish, commit or push was performed.
