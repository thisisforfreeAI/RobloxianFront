// Runs the game's own tree placement (its xVt, traced from the renderer's forest layer) for one map
// and writes every tree as JSON, so tools/asset_pipeline/pack_city.py can draw them. Nothing from the
// game is copied into this file: the code is loaded from the local install at run time.
//
//   node tools/conversion/export_trees.cjs <main-*.js> <map.json> [town trees x,y json] > trees.json
//
// map.json: the exported map (terrain.data in the game's terrain order, width, height).
// town trees: the .city file's trees part as [x0, y0, x1, y1, ...] (optional); they become the game's
// yard trees (CVt), placed after the wild ones.
// Output: { count, x, y, scale, tile, yard, tiles: { name: [x, y, w, h] } }
const fs = require("fs");

const [bundlePath, mapPath, townPath] = process.argv.slice(2);
const src = fs.readFileSync(bundlePath, "utf8");
const a = src.indexOf('const dVt="/tiles/trees-top.png"');
const b = src.indexOf("const MVt=");
if (a < 0 || b < a) throw new Error("tree placement code not found in this bundle (names changed?)");
const legend = ["deep", "shallow", "beach", "plains", "forest", "hills", "mountain", "snow", "desert", "marsh", "river", "fallout"];
const uo = (n) => legend.indexOf(n);
const api = new Function("uo", "H3", src.slice(a, b) + "\nreturn { xVt, CVt, Pc, h$ };")(uo, () => {});

const map = JSON.parse(fs.readFileSync(mapPath, "utf8"));
const terrain = Uint8Array.from(map.terrain.data);
const town = townPath ? JSON.parse(fs.readFileSync(townPath, "utf8")) : [];
const r = api.xVt(terrain, map.width, map.height, undefined, town.length ? api.CVt(town) : []);
const tiles = {};
for (const k of api.h$) tiles[k] = [api.Pc[k].x, api.Pc[k].y, api.Pc[k].w, api.Pc[k].h];
process.stdout.write(JSON.stringify({
  count: r.count,
  x: Array.from(r.x), y: Array.from(r.y), scale: Array.from(r.scale),
  tile: Array.from(r.tile, (t) => api.h$[t]), yard: Array.from(r.yard),
  tiles,
}));
