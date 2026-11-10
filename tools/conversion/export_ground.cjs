// Runs the game's own ground baker (its oUt, the "fine" ground texture the ground shader samples:
// 3 px a cell, grass tones, dirt, trails, canopy, rock, sand and water edges, hill light and shade)
// for one map and writes the raw RGBA. Nothing from the game is copied into this file: the baker and
// everything it uses are pulled out of the local install's bundle at run time with acorn.
//
//   node tools/conversion/export_ground.cjs <main-*.js> <map.json> <out.rgba> [path to acorn dir]
//
// Writes <out.rgba> (width x height x 4 bytes) and prints "width height".
//
// It also lays on the ground shader's forest floor, which is the one part of that shader a fixed
// close-up view keeps: forest texels darken toward the heart of a wood, in the game's own steps.
// The game feeds the shader each cell's depth into its wood (ZLe, then jLe) as a linear-filtered
// per-cell texture. Pass --no-woods to skip it. The canopy look the game blends in from far away
// is left out, because trees are always drawn here.
const fs = require("fs");
const path = require("path");

const args = process.argv.slice(2);
const noWoods = args.includes("--no-woods");
const [bundlePath, mapPath, outPath, acornDir] = args.filter((a) => a !== "--no-woods");
const req = (name) => {
  for (const base of [acornDir, "/opt/cowork-node-tools/node_modules"].filter(Boolean)) {
    try { return require(path.join(base, name)); } catch (e) { /* next */ }
  }
  return require(name);
};
const acorn = req("acorn");
const walk = req("acorn-walk");

// top-level declarations of the bundle, and the closure of the ones we need
const code = fs.readFileSync(bundlePath, "utf8");
const ast = acorn.parse(code, { ecmaVersion: "latest", sourceType: "module" });
const decl = new Map();
let order = 0;
for (const n of ast.body) {
  if (n.type === "FunctionDeclaration" || n.type === "ClassDeclaration") {
    decl.set(n.id.name, { node: n, text: code.slice(n.start, n.end), order: order++ });
  } else if (n.type === "VariableDeclaration") {
    for (const d of n.declarations) {
      const e = { node: d, text: n.kind + " " + code.slice(d.start, d.end) + ";", order: order++ };
      walk.full(d.id, (x) => { if (x.type === "Identifier") decl.set(x.name, e); });
    }
  }
}
const targets = ["oUt", "Nn", "ZLe", "jLe", "s7"];
const need = new Set();
const queue = [...targets];
while (queue.length) {
  const nm = queue.pop();
  if (need.has(nm) || !decl.has(nm)) continue;
  need.add(nm);
  walk.full(decl.get(nm).node, (x) => { if (x.type === "Identifier" && decl.has(x.name) && !need.has(x.name)) queue.push(x.name); });
}
// Some tables are filled by top-level statements after their declaration (A2[...] = ..., XF.forEach(...)):
// keep every such statement whose target is a table we need, and what it uses, until nothing changes.
const rootOf = (x) => {
  while (x && x.type === "MemberExpression") x = x.object;
  return x && x.type === "Identifier" ? x.name : null;
};
// what a statement fills: the tables it assigns into or calls a method on (A2[i] = .., XF.forEach(..))
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
    while (queue.length) {
      const nm = queue.pop();
      if (need.has(nm) || !decl.has(nm)) continue;
      need.add(nm);
      walk.full(decl.get(nm).node, (x) => { if (x.type === "Identifier" && decl.has(x.name) && !need.has(x.name)) queue.push(x.name); });
    }
  }
}
for (const t of targets) if (!need.has(t)) throw new Error(`${t} not found in this bundle (names changed?)`);
const pieces = [...new Set([...need].map((n) => decl.get(n)))].map((e) => ({ at: e.node.start, text: e.text }));
for (const f of kept) pieces.push({ at: f.at, text: code.slice(f.node.start, f.node.end) });
const body = pieces.sort((a, b) => a.at - b.at).map((e) => e.text).join("\n");
const api = new Function(body + "\nreturn { oUt, Nn, ZLe, jLe, s7 };")();

const m = JSON.parse(fs.readFileSync(mapPath, "utf8"));
const arr = (v) => (v && v.data ? Uint8Array.from(v.data) : v);
const terrain = Uint8Array.from(m.terrain.data);
const real = { ...m, terrain, elev: arr(m.elev), urban: arr(m.urban) };
// the game bakes a designed map with roofs and roads off (they come from the city layer)
const r = api.oUt(terrain, m.width, m.height, real, { roofs: false, roads: false });
if (!noWoods) forestFloor(r, terrain, m.width, m.height);
fs.writeFileSync(outPath, Buffer.from(r.rgba.buffer, r.rgba.byteOffset, r.rgba.byteLength));
console.log(r.width, r.height);

// The shader's close-up forest floor: base *= 1 - floorDark * heart on forest texels (fine mask 11),
// heart being the per-cell wood depth sampled bilinearly at the texel and cut to s7.steps levels.
function forestFloor(r, terrain, w, h) {
  const { depth } = api.ZLe(terrain, w, h);
  const heart = new Float32Array(w * h);
  for (let i = 0; i < heart.length; i++) heart[i] = Math.round(api.jLe(depth[i]) * 255) / 255;
  const fine = r.width / w;
  const at = (x, y) => heart[Math.min(h - 1, Math.max(0, y)) * w + Math.min(w - 1, Math.max(0, x))];
  const { floorDark, steps } = api.s7;
  let n = 0;
  for (let ty = 0; ty < r.height; ty++) {
    const fy = (ty + 0.5) / fine - 0.5, y0 = Math.floor(fy), ay = fy - y0;
    for (let tx = 0; tx < r.width; tx++) {
      const t = ty * r.width + tx;
      if (r.mask[t] !== 11) continue;
      const fx = (tx + 0.5) / fine - 0.5, x0 = Math.floor(fx), ax = fx - x0;
      const b = (at(x0, y0) * (1 - ax) + at(x0 + 1, y0) * ax) * (1 - ay) + (at(x0, y0 + 1) * (1 - ax) + at(x0 + 1, y0 + 1) * ax) * ay;
      // the texture is 8 bit, as the GPU sees it
      const q = Math.floor(Math.round(b * 255) / 255 * steps + 0.5) / steps;
      const k = 1 - floorDark * q;
      for (let c = 0; c < 3; c++) r.rgba[t * 4 + c] = Math.round(r.rgba[t * 4 + c] * k);
      n++;
    }
  }
  console.error(`forest floor: ${n} texels shaded`);
}
