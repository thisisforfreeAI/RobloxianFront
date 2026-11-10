// Generate private death-effect data and the game's procedural particle atlas from a local install.
// Usage: node tools/conversion/export_death_fx.cjs <install> [project root]
// Requires @napi-rs/canvas (or set NODE_PATH to a directory containing it).
// Reads app.asar in place. No source code or generated data belongs in the public repository.
const fs = require('fs'), path = require('path'), vm = require('vm');
const install = process.argv[2];
const root = path.resolve(process.argv[3] || path.join(__dirname, '../..'));
if (!install) throw new Error('usage: node export_death_fx.cjs <install> [project root]');
const relative = path.relative(path.resolve(install), root);
if (!relative || (!relative.startsWith('..' + path.sep) && relative !== '..' && !path.isAbsolute(relative))) throw new Error('output must stay outside the original install');
const bytes = fs.readFileSync(path.join(install, 'resources/app.asar'));
const header = JSON.parse(bytes.subarray(16, 16 + bytes.readUInt32LE(12)));
const entries = header.files.dist.files.assets.files;
function bundle(pattern) {
  const names = Object.keys(entries).filter(n => pattern.test(n));
  if (names.length !== 1) throw new Error('expected one bundle: ' + pattern);
  const e = entries[names[0]], at = 8 + bytes.readUInt32LE(4) + Number(e.offset);
  return bytes.subarray(at, at + e.size).toString();
}
const main = bundle(/^main-.*\.js$/), effects = bundle(/^effects-.*\.js$/);
function balanced(src, at) {
  const start = src.indexOf('{', at); let depth = 0;
  for (let i = start; i < src.length; i++) {
    const c = src[i];
    if ('"\'`'.includes(c)) { const q = c; while (++i < src.length && src[i] !== q) if (src[i] === '\\') i++; }
    else if (c === '{') depth++;
    else if (c === '}' && --depth === 0) return src.slice(start, i + 1);
  }
  throw new Error('unbalanced bundle expression');
}
// Follow the export/import names rather than relying on minified symbol names.
function imported(alias) {
  const imp = effects.slice(0, effects.indexOf('from"./main-'));
  const key = new RegExp('([\\w$]+) as ' + alias + '(?:,|})').exec(imp)?.[1];
  const sym = key && new RegExp('([\\w$]+) as ' + key + '(?:,|})').exec(main.slice(main.lastIndexOf('export{')))?.[1];
  if (!sym) throw new Error('missing import ' + alias);
  const at = main.indexOf(sym + '={');
  if (at < 0) throw new Error('missing literal ' + sym);
  return vm.runInNewContext('(' + balanced(main, at) + ')', {}, { timeout: 1000 });
}
const data = { death: imported('J'), colors: imported('w'), sparks: imported('N'), motion: imported('C'), blast: imported('Se'), look: imported('Mt') };
if (!data.death.variants?.weights.ifv || !data.look.flash) throw new Error('unrecognized death configuration');
function lua(v) {
  if (v === null) return 'nil';
  if (typeof v !== 'object') return JSON.stringify(v);
  if (Array.isArray(v)) return '{' + v.map(lua).join(',') + '}';
  return '{' + Object.entries(v).map(([k, x]) => '[' + JSON.stringify(k) + ']=' + lua(x)).join(',') + '}';
}
const { createCanvas } = require('@napi-rs/canvas');
const frame = Number(/\bft=(\d+)/.exec(effects)?.[1]);
const side = /\bso=ft\*4\b/.test(effects) ? frame * 4 : Number(/\bso=(\d+)/.exec(effects)?.[1]);
if (!frame || !side || side !== frame * 4) throw new Error('unrecognized particle atlas dimensions');
const at = effects.indexOf('function go(');
if (at < 0) throw new Error('particle painter not found');
const canvas = createCanvas(side, side);
vm.runInNewContext('const ft=' + frame + ';function go(p)' + balanced(effects, at) + ';go(canvas)', { canvas }, { timeout: 1000 });
const rgba = canvas.getContext('2d').getImageData(0, 0, side, side).data;
const runs = [];
for (let i = 0; i < rgba.length;) {
  const start = i; i += 4; let count = 1;
  while (i < rgba.length && count < 65535 && rgba[i] === rgba[start] && rgba[i+1] === rgba[start+1] && rgba[i+2] === rgba[start+2] && rgba[i+3] === rgba[start+3]) { i += 4; count++; }
  const run = Buffer.alloc(6); run.writeUInt16LE(count); Buffer.from(rgba.subarray(start, start+4)).copy(run, 2); runs.push(run);
}
const targets = [path.join(root, 'src/shared/GameData/DeathFx.luau'), path.join(root, 'src/client/DevAssets/OrigDeathFx.luau')];
const contents = ['return ' + lua(data) + '\n', 'return ' + lua({ width: side, height: side, frame, rle: Buffer.concat(runs).toString('base64') }) + '\n'];
targets.forEach((target, i) => { fs.mkdirSync(path.dirname(target), { recursive: true }); fs.writeFileSync(target, '-- Generated locally from your install; git-ignored.\n' + contents[i]); });
console.log('Generated private death configuration and ' + side + 'x' + side + ' particle atlas.');
