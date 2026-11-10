// Water data for one map, for the water layer (src/client/Rendering/WaterRenderer.luau).
//
// It runs the game's own code from the local install's bundle with acorn, so no game code or numbers
// are copied into this file:
//   - the ground baker (oUt): the fine ground colour and its mask codes, FINE texels a cell;
//   - the water map builder (wUt): per cell, which way a river flows, how fast, and how far from the shore;
//   - the water look settings the ground shader is fed (the surf, crests, glints, depth bands, river flow,
//     tide), and the palette colours it uses.
// The output is a git-ignored Luau module, src/client/DevAssets/Water_<mapId>.luau. It holds the game's
// numbers and art, so it must stay local.
//
//   node tools/conversion/export_water.cjs <main-*.js> <map.json> <out.luau> [path to acorn dir]
//
// <map.json> is a map exported by export_map.cjs. A map without water writes a module with water = false.
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const [bundlePath, mapPath, outPath, acornDir] = process.argv.slice(2);
if (!bundlePath || !mapPath || !outPath) {
  console.error("usage: node export_water.cjs <main-*.js> <map.json> <out.luau> [acorn dir]");
  process.exit(2);
}
const req = (name) => {
  for (const base of [acornDir, "/opt/cowork-node-tools/node_modules"].filter(Boolean)) {
    try { return require(path.join(base, name)); } catch (e) { /* next */ }
  }
  return require(name);
};
const acorn = req("acorn");
const walk = req("acorn-walk");

// the bundle's top-level declarations, and the closure of the ones we need (as export_ground.cjs)
const code = fs.readFileSync(bundlePath, "utf8");
const ast = acorn.parse(code, { ecmaVersion: "latest", sourceType: "module" });
const decl = new Map();
for (const n of ast.body) {
  if (n.type === "FunctionDeclaration" || n.type === "ClassDeclaration") {
    decl.set(n.id.name, { node: n, text: code.slice(n.start, n.end) });
  } else if (n.type === "VariableDeclaration") {
    for (const d of n.declarations) {
      const e = { node: d, text: n.kind + " " + code.slice(d.start, d.end) + ";" };
      walk.full(d.id, (x) => { if (x.type === "Identifier") decl.set(x.name, e); });
    }
  }
}
// The names are the minified ones of this build; check them against the bundle if a new build breaks this.
// oUt ground baker, Nn FINE, wUt water map, rs mask codes, us ground look, _6 foam/crest colours,
// ja river flow, ew tide, pl depth, V1 night reflections, bp/Fv palette colour, oa look-trial settings,
// er look-trial switches, v$ crest width in cells.
const targets = ["oUt", "Nn", "wUt", "rs", "us", "_6", "ja", "ew", "pl", "V1", "bp", "oa", "er", "v$"];
const need = new Set();
const queue = [...targets];
const grow = () => {
  while (queue.length) {
    const nm = queue.pop();
    if (need.has(nm) || !decl.has(nm)) continue;
    need.add(nm);
    walk.full(decl.get(nm).node, (x) => { if (x.type === "Identifier" && decl.has(x.name) && !need.has(x.name)) queue.push(x.name); });
  }
};
grow();
const rootOf = (x) => {
  while (x && x.type === "MemberExpression") x = x.object;
  return x && x.type === "Identifier" ? x.name : null;
};
const targetsOf = (stmt) => {
  const roots = new Set();
  walk.full(stmt, (x) => {
    if (x.type === "AssignmentExpression" && x.left.type === "MemberExpression") roots.add(rootOf(x.left));
    else if (x.type === "CallExpression" && x.callee.type === "MemberExpression") roots.add(rootOf(x.callee));
  });
  return [...roots];
};
const fills = [];
const LOOSE = new Set(["ExpressionStatement", "ForStatement", "ForOfStatement", "ForInStatement", "BlockStatement", "IfStatement"]);
for (const n of ast.body) if (LOOSE.has(n.type)) fills.push({ node: n, at: n.start, roots: targetsOf(n) });
const kept = new Set();
for (let grew = true; grew; ) {
  grew = false;
  for (const f of fills) {
    if (kept.has(f) || !f.roots.some((r) => r && need.has(r))) continue;
    kept.add(f);
    grew = true;
    walk.full(f.node, (x) => { if (x.type === "Identifier" && decl.has(x.name) && !need.has(x.name)) queue.push(x.name); });
    grow();
  }
}
for (const t of targets) if (!need.has(t)) throw new Error(`${t} not found in this bundle (names changed?)`);
const pieces = [...new Set([...need].map((n) => decl.get(n)))].map((e) => ({ at: e.node.start, text: e.text }));
for (const f of kept) pieces.push({ at: f.at, text: code.slice(f.node.start, f.node.end) });
const body = pieces.sort((a, b) => a.at - b.at).map((e) => e.text).join("\n");
const api = new Function(body + "\nreturn { oUt, Nn, wUt, rs, us, _6, ja, ew, pl, V1, bp, oa, er, crestCells: v$ };")();

const m = JSON.parse(fs.readFileSync(mapPath, "utf8"));
const arr = (v) => (v && v.data ? Uint8Array.from(v.data) : v);
const terrain = Uint8Array.from(m.terrain.data);
const W = m.width, H = m.height;
const real = { ...m, terrain, elev: arr(m.elev), urban: arr(m.urban) };
const g = api.oUt(terrain, W, H, real, { roofs: false, roads: false });
const F = api.Nn, rs = api.rs;
if (g.width !== W * F) throw new Error(`fine width ${g.width}, expected ${W * F}`);
const wetCode = (c) => c >= rs.shallowNear && c <= rs.crestTail;

// keep the water texels and the sand texels within two of the sea (the tide), the rest cleared
const TW = g.width, TH = g.height;
const keep = new Uint8Array(TW * TH);
let wetCount = 0;
for (let t = 0; t < TW * TH; t++) if (wetCode(g.mask[t])) { keep[t] = 1; wetCount++; }
for (let ty = 0; ty < TH; ty++) for (let tx = 0; tx < TW; tx++) {
  const t = ty * TW + tx;
  if (g.mask[t] !== rs.sand) continue;
  for (let d = -2; d <= 2 && !keep[t]; d++) {
    for (const [x, y] of [[tx + d, ty], [tx, ty + d], [tx + 1, ty + 1], [tx - 1, ty - 1], [tx + 1, ty - 1], [tx - 1, ty + 1]]) {
      if (x >= 0 && y >= 0 && x < TW && y < TH && wetCode(g.mask[y * TW + x])) { keep[t] = 1; break; }
    }
  }
}
const fine = Buffer.alloc(TW * TH * 4); // rgb + mask code, 0 where nothing is drawn
for (let t = 0; t < TW * TH; t++) {
  if (!keep[t]) continue;
  fine[t * 4] = g.rgba[t * 4]; fine[t * 4 + 1] = g.rgba[t * 4 + 1]; fine[t * 4 + 2] = g.rgba[t * 4 + 2];
  fine[t * 4 + 3] = g.mask[t];
}
const wmap = Buffer.from(api.wUt(terrain, W, H));

const b64 = (buf) => zlib.deflateRawSync(buf, { level: 9 }).toString("base64");
// chunks of CHUNK cells with any texel to draw: the fine rgb + mask, and the water map with a cell of
// border all round (the shader reads it smoothed between cells)
const CHUNK = 64;
const chunks = [];
for (let cy = 0; cy < H; cy += CHUNK) for (let cx = 0; cx < W; cx += CHUNK) {
  const cw = Math.min(CHUNK, W - cx), ch = Math.min(CHUNK, H - cy);
  const tw = cw * F, th = ch * F;
  const px = Buffer.alloc(tw * th * 4);
  let any = false;
  for (let y = 0; y < th; y++) {
    const src = ((cy * F + y) * TW + cx * F) * 4;
    fine.copy(px, y * tw * 4, src, src + tw * 4);
  }
  for (let i = 3; i < px.length; i += 4) if (px[i] !== 0) { any = true; break; }
  if (!any) continue;
  const mw = cw + 2, mh = ch + 2;
  const wm = Buffer.alloc(mw * mh * 4);
  for (let y = 0; y < mh; y++) for (let x = 0; x < mw; x++) {
    const sx = Math.min(W - 1, Math.max(0, cx + x - 1)), sy = Math.min(H - 1, Math.max(0, cy + y - 1));
    wmap.copy(wm, (y * mw + x) * 4, (sy * W + sx) * 4, (sy * W + sx) * 4 + 4);
  }
  chunks.push(`\t\t{ ${cx}, ${cy}, ${cw}, ${ch}, "${b64(px)}", "${b64(wm)}" },`);
}
const lua = (v) => {
  if (Array.isArray(v)) return "{ " + v.map(lua).join(", ") + " }";
  if (v && typeof v === "object") return "{ " + Object.entries(v).map(([k, x]) => `${/^[A-Za-z_]\w*$/.test(k) ? k : `["${k}"]`} = ${lua(x)}`).join(", ") + " }";
  if (typeof v === "string") return JSON.stringify(v);
  if (typeof v === "boolean") return v ? "true" : "false";
  return String(v);
};
const us = api.us, oa = api.oa, er = api.er;
const settings = {
  fine: F,
  codes: { sand: rs.sand, shallowNear: rs.shallowNear, shallow: rs.shallow, deep: rs.deep, river: rs.river, fleck: rs.fleck,
    foam: rs.foam, foamFar: rs.foamFar, crestHead: rs.crestHead, crestTail: rs.crestTail },
  sea: api.bp("deep"),
  surf: { mix: us.foam, period: us.foamPeriodSec, farPeriod: us.foamFarPeriodSec, segment: us.foamSegment, color: us.foamColor,
    off: api._6.foamOff, farOff: api._6.foamFarOff },
  crest: { texels: api.crestCells * F, period: us.crestPeriodSec, step: us.crestStep, color: api._6.crest },
  // the look trial's sea and river switches are on in this build (er.sea, er.river), so their values stand
  glints: { share: er.sea ? oa.sea.glintShare : us.glints.share, perSec: us.glints.perSec, sun: er.sea ? oa.sea.glintSun : us.glints.sun, moon: us.glints.moon },
  depth: api.pl,
  tide: api.ew,
  flow: { ...api.ja, swellAmpRiver: er.river ? oa.river.depth : 1 },
};
const out = [
  "--!strict",
  "-- GENERATED by tools/conversion/export_water.cjs from the local WarFront install. Local only (git-ignored):",
  "-- it holds the game's water settings and ground art.",
  `-- chunks: { cx, cy, cw, ch, fine, waterMap } in cells; fine: rgb + mask code a texel (FINE a cell), waterMap:`,
  "-- the game's water map, rgba a cell, with one cell of border; both raw DEFLATE, base64.",
  "return {",
  `\tid = ${JSON.stringify(m.id || path.basename(mapPath, ".json"))}, width = ${W}, height = ${H},`,
  `\twater = ${wetCount > 0 ? "true" : "false"},`,
  `\tsettings = ${lua(settings)},`,
  "\tchunks = {",
  ...chunks,
  "\t},",
  "}",
  "",
].join("\n");
fs.writeFileSync(outPath, out);
console.log(`${m.id || mapPath}: ${W}x${H} cells, ${wetCount} water texels, ${chunks.length} chunks, ${(out.length / 1024).toFixed(0)} KB`);
