// Runs the game's own ground baker (its oUt, the "fine" ground texture the ground shader samples:
// 3 px a cell, grass tones, dirt, trails, canopy, rock, sand and water edges, hill light and shade)
// for one map and writes the raw RGBA. Nothing from the game is copied into this file: the baker and
// everything it uses are pulled out of the local install's bundle at run time with acorn.
//
//   node tools/conversion/export_ground.cjs <main-*.js> <map.json> <out.rgba> [path to acorn dir]
//
// Writes <out.rgba> (width x height x 4 bytes) and prints "width height".
const fs = require("fs");
const path = require("path");

const [bundlePath, mapPath, outPath, acornDir] = process.argv.slice(2);
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
const targets = ["oUt", "Nn"];
const need = new Set();
const queue = [...targets];
while (queue.length) {
  const nm = queue.pop();
  if (need.has(nm) || !decl.has(nm)) continue;
  need.add(nm);
  walk.full(decl.get(nm).node, (x) => { if (x.type === "Identifier" && decl.has(x.name) && !need.has(x.name)) queue.push(x.name); });
}
for (const t of targets) if (!need.has(t)) throw new Error(`${t} not found in this bundle (names changed?)`);
const body = [...new Set([...need].map((n) => decl.get(n)))].sort((a, b) => a.order - b.order).map((e) => e.text).join("\n");
const api = new Function(body + "\nreturn { oUt, Nn };")();

const m = JSON.parse(fs.readFileSync(mapPath, "utf8"));
const arr = (v) => (v && v.data ? Uint8Array.from(v.data) : v);
const terrain = Uint8Array.from(m.terrain.data);
const real = { ...m, terrain, elev: arr(m.elev), urban: arr(m.urban) };
// the game bakes a designed map with roofs and roads off (they come from the city layer)
const r = api.oUt(terrain, m.width, m.height, real, { roofs: false, roads: false });
fs.writeFileSync(outPath, Buffer.from(r.rgba.buffer, r.rgba.byteOffset, r.rgba.byteLength));
console.log(r.width, r.height);
