// Export WarFront's runtime match rules from the game's own code (read-only).
// The modding guide's table is NOT what a match uses: the game builds its config from a defaults
// function and then rescales distances/speeds by the match cell scale before building the world.
// This script runs those two functions in a sandbox and writes the values a real skirmish starts from.
//
// Usage: node export_rules.cjs <dist/assets/main-*.js> <out RulesMatch.luau>
// Output is git-ignored (GameData/). The functions are located by shape, not by fixed names where
// possible; if the bundle changes the script fails loudly instead of guessing.
const fs = require('fs'), vm = require('vm');
const [bundlePath, outPath] = process.argv.slice(2);
if (!bundlePath || !outPath) { console.error('usage: node export_rules.cjs <main.js> <out.luau>'); process.exit(2); }
const js = fs.readFileSync(bundlePath, 'utf8');

function balanced(start) {
  let d = 0, j = js.indexOf('{', start);
  for (let k = j; k < js.length; k++) {
    const c = js[k];
    if (c === '"' || c === "'" || c === '`') { const q = c; k++; while (js[k] !== q) { if (js[k] === '\\') k++; k++; } continue; }
    if (c === '{') d++; else if (c === '}') { d--; if (d === 0) return js.slice(start, k + 1); }
  }
  throw new Error('unbalanced at ' + start);
}
function fnByHead(re) { const m = re.exec(js); if (!m) throw new Error('not found: ' + re); return { name: m[1], src: balanced(m.index) }; }

// defaults: function X(){return{shots:{},match:{tickHz:...
const defaults = fnByHead(/function ([\w$]+)\(\)\{return\{shots:\{\},match:\{tickHz:/);
// scaler: function Y(t,e){t.match.cellScale=e;...
const scaler = fnByHead(/function ([\w$]+)\(t,e\)\{t\.match\.cellScale=e;/);
// match cell scale constant: wv(...){...;Y(o,K);  -> const K=<n>
const call = new RegExp('o=' + defaults.name.replace(/\$/g, '\\$') + '\\(\\)\\)\\{(?:var [\\w$,]+;)?' + scaler.name.replace(/\$/g, '\\$') + '\\(o,([\\w$]+)\\)').exec(js);
if (!call) throw new Error('match world builder not found');
const k = new RegExp('const ' + call[1].replace(/\$/g, '\\$') + '=(\\d+(?:\\.\\d+)?);').exec(js);
if (!k) throw new Error('cell scale constant not found');
const CELL_SCALE = Number(k[1]);

// helpers the scaler calls (and the helpers they call): function NAME(t,e){ ... }
const helperSrc = new Map();
const todo = [scaler.src];
while (todo.length) {
  const src = todo.pop();
  for (const m of src.matchAll(/([\w$]+)\(t,e\)/g)) {
    const n = m[1];
    if (n === scaler.name || helperSrc.has(n)) continue;
    const at = js.indexOf('function ' + n + '(t,e){');
    if (at < 0) throw new Error('helper not found: ' + n);
    const body = balanced(at);
    helperSrc.set(n, body);
    todo.push(body);
  }
}
const helpers = [...helperSrc.values()];
// simple object constants the defaults reference (e.g. a zeroed vs table)
const consts = [];
for (const m of defaults.src.matchAll(/vs:([\w$]+)[,}]/g)) {
  const def = new RegExp('[,; ]' + m[1].replace(/\$/g, '\\$') + '=(\\{[^{}]*\\})').exec(js);
  if (def && !consts.some(c => c.startsWith('var ' + m[1] + '='))) consts.push('var ' + m[1] + '=' + def[1] + ';');
}

const ctx = {};
const unresolved = new Set();
const proxy = new Proxy(ctx, {
  has: (t, key) => !(key in globalThis) || key in t,
  get: (t, key) => { if (key === Symbol.unscopables) return undefined; if (key in t) return t[key];
    unresolved.add(String(key)); return undefined; },
});
vm.createContext(ctx); ctx.__p = proxy;
vm.runInContext('with(__p){' + consts.join('') + defaults.src + scaler.src + helpers.join('\n') +
  ';this.__d=' + defaults.name + ';this.__s=' + scaler.name + ';}', ctx);
const cfg = ctx.__s(ctx.__d(), CELL_SCALE);

// Built-in bot personas (a constant next to the bot code, not part of the defaults function):
// exported as bots.personaDefaults.<id>.<field> so the port reads them from generated data.
{
  const m = /[,; ]([\w$]+)=\{balanced:\{id:"balanced"/.exec(js);
  if (!m) throw new Error('bot personas not found');
  const src = balanced(m.index + m[0].indexOf('{'));
  const personas = vm.runInNewContext('(' + src + ')');
  cfg.bots.personaDefaults = {};
  for (const [id, p] of Object.entries(personas)) {
    cfg.bots.personaDefaults[id] = {};
    for (const [k, v] of Object.entries(p)) if (typeof v === 'number' || (typeof v === 'string' && k === 'id')) cfg.bots.personaDefaults[id][k] = v;
  }
}

const flat = [];
(function walk(o, p) {
  for (const [key, v] of Object.entries(o)) {
    const name = p ? p + '.' + key : key;
    if (v === undefined || typeof v === 'function') continue;
    if (Array.isArray(v)) { if (v.every(x => typeof x === 'number' || typeof x === 'string' || typeof x === 'boolean')) flat.push([name, v]); }
    else if (v && typeof v === 'object') walk(v, name);
    else flat.push([name, v]);
  }
})(cfg, '');
const lit = v => typeof v === 'string' ? JSON.stringify(v) : typeof v === 'number' ? (Number.isFinite(v) ? String(v) : (v > 0 ? 'math.huge' : '-math.huge'))
  : typeof v === 'boolean' ? String(v) : Array.isArray(v) ? '{ ' + v.map(lit).join(', ') + ' }' : 'nil';
const lines = ['--!strict',
  '-- GENERATED by tools/conversion/export_rules.cjs from WarFront\'s runtime defaults. Do not edit by hand.',
  `-- ${flat.length} rules as a skirmish match starts them: defaults rescaled by match cell scale ${CELL_SCALE}.`,
  '-- Rates (per second), costs and hp are unscaled; distances and speeds are in map cells.',
  unresolved.size ? '-- Unresolved references (left out): ' + [...unresolved].sort().join(', ') : '-- No unresolved references.',
  'return {'];
for (const [n, v] of flat) lines.push(`\t[${JSON.stringify(n)}] = ${lit(v)},`);
lines.push('}', '');
fs.writeFileSync(outPath, lines.join('\n'));
console.log(`wrote ${flat.length} rules (cell scale ${CELL_SCALE}) to ${outPath}; unresolved: ${[...unresolved].join(', ') || 'none'}`);
