// Export a WarFront designed map by running the game's own generator worker
// (dist/assets/genWorker-*.js, extracted from app.asar) inside a Node vm sandbox.
// The worker is pure computation (no I/O); the sandbox exposes only JS builtins.
// Usage: node export_map.cjs <genWorker.js> <mapId> <out.json>
const fs = require('fs');
const vm = require('vm');

const [, , workerPath, mapId, outPath] = process.argv;
if (!workerPath || !mapId || !outPath) {
  console.error('usage: node export_map.cjs <genWorker.js> <mapId> <out.json>');
  process.exit(2);
}
let result = null;
const self = { postMessage: (m) => { result = m; } };
const ctx = vm.createContext({
  self, Math, Object, Array, Map, Set, JSON, Number, String, Boolean, Error, Symbol,
  ArrayBuffer, DataView, Uint8Array, Int8Array, Uint16Array, Int16Array, Uint32Array,
  Int32Array, Float32Array, Float64Array, isFinite, isNaN, parseInt, parseFloat,
  Infinity, NaN, TextEncoder, TextDecoder, structuredClone, console,
});
vm.runInContext(fs.readFileSync(workerPath, 'utf8'), ctx, { filename: 'genWorker.js' });
self.onmessage({ data: { id: 1, map: mapId } });
if (!result || result.error) throw new Error('generation failed: ' + (result && result.error));
const typed = (k, v) => (ArrayBuffer.isView(v) ? { $typed: v.constructor.name, data: Array.from(v) } : v);
fs.writeFileSync(outPath, JSON.stringify(result.map, typed));
console.log(`exported ${mapId} -> ${outPath}`);
