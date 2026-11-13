// Extract tank/IFV muzzle settings from the owner's local install. Output stays git-ignored.
// Usage: node export_vehicle_muzzle.cjs <install> [project root]
const fs=require('fs'),path=require('path'),vm=require('vm');
const install=process.argv[2],root=path.resolve(process.argv[3]||path.join(__dirname,'../..'));
if(!install)throw Error('usage: node export_vehicle_muzzle.cjs <install> [project root]');
const relative=path.relative(path.resolve(install),root);
if(!relative||(!relative.startsWith('..'+path.sep)&&relative!=='..'&&!path.isAbsolute(relative)))throw Error('output must stay outside the original install');
const bytes=fs.readFileSync(path.join(install,'resources/app.asar')),header=JSON.parse(bytes.subarray(16,16+bytes.readUInt32LE(12))),entries=header.files.dist.files.assets.files;
function bundle(pattern){const names=Object.keys(entries).filter(n=>pattern.test(n));if(names.length!==1)throw Error('expected one bundle: '+pattern);const e=entries[names[0]],at=8+bytes.readUInt32LE(4)+Number(e.offset);return bytes.subarray(at,at+e.size).toString();}
const main=bundle(/^main-.*\.js$/),effects=bundle(/^effects-.*\.js$/);
function balanced(src,at){const start=src.indexOf('{',at);let depth=0;for(let i=start;i<src.length;i++){const c=src[i];if('"\'`'.includes(c)){const q=c;while(++i<src.length&&src[i]!==q)if(src[i]==='\\')i++;}else if(c==='{')depth++;else if(c==='}'&&--depth===0)return src.slice(start,i+1);}throw Error('unbalanced expression');}
function escaped(s){return s.split('$').join('\\$');}
function literal(alias){const imp=effects.slice(0,effects.indexOf('from"./main-')),key=new RegExp('([\\w$]+) as '+escaped(alias)+'(?:,|})').exec(imp)?.[1],sym=key&&new RegExp('([\\w$]+) as '+escaped(key)+'(?:,|})').exec(main.slice(main.lastIndexOf('export{')))?.[1];if(!sym)throw Error('missing import '+alias);const match=new RegExp('(?:^|[^\\w$])'+escaped(sym)+'=\\{').exec(main);if(!match)throw Error('missing literal '+sym);return balanced(main,match.index+match[0].length-1);}
function properties(text){const inner=text.slice(1,-1),parts=[];let start=0,depth=0;for(let i=0;i<inner.length;i++){const c=inner[i];if('"\'`'.includes(c)){const q=c;while(++i<inner.length&&inner[i]!==q)if(inner[i]==='\\')i++;}else if('{[('.includes(c))depth++;else if('}])'.includes(c))depth--;else if(c===','&&depth===0){parts.push(inner.slice(start,i));start=i+1;}}parts.push(inner.slice(start));const result=new Map();for(const part of parts){const m=/^\s*([\w$]+)\s*:([\s\S]*)$/.exec(part);if(!m)throw Error('unsupported source property');result.set(m[1],m[2]);}return result;}
function imported(alias,keys){const text=literal(alias);if(!keys)return vm.runInNewContext('('+text+')',{}, {timeout:1000});const props=properties(text);const subset=keys.map(k=>{if(!props.has(k))throw Error('missing source property '+k);return JSON.stringify(k)+':'+props.get(k);}).join(',');return vm.runInNewContext('({'+subset+'})',{}, {timeout:1000});}
function method(name){const found=new RegExp('(?:^|})'+name+'\\([^)]*\\)\\{').exec(effects);if(!found)throw Error('missing method '+name);return balanced(effects,found.index+found[0].length-1);}
// Follow semantic properties in the actual methods, then the import/export bindings. Minifier aliases
// and parameter names can change between Steam builds without changing these source primitives.
const tankMethod=method('tankBlast'),puffMethod=method('puff'),sparkMethod=method('sparks');
const profile=/const [\w$]+=([\w$]+)\.tank,[\w$]+=[\w$]+&&\(\([\w$]+=([\w$]+)\[/.exec(tankMethod);
const colorAlias=/color:([\w$]+)\.fire/.exec(tankMethod)?.[1],motionAlias=/vh:[\w$]+\?([\w$]+)\.rise/.exec(puffMethod)?.[1],sparkAlias=/\{const [\w$]+=([\w$]+);for/.exec(sparkMethod)?.[1];
if(!profile||!colorAlias||!motionAlias||!sparkAlias)throw Error('unrecognized vehicle muzzle configuration paths');
method('autocannon');method('barrelBreath');method('gunFlash');method('spentCase');
const vehicle=imported(profile[1],['gun','gunHeight','tank','ifv']),factions=imported(profile[2]),colors=imported(colorAlias,['fire','hot','ember','smoke','smokeLight','dustLight']),motion=imported(motionAlias,['rise','grow']),sparks=imported(sparkAlias,['muzzle','size','impactSpeed','impactLife']);
const variantAlias=/const [\w$]+=[\w$]+\.army\?([\w$]+)\[[\w$]+\.army\]:void 0;/.exec(method('vehicleFire'))?.[1];
const sourceIfvVariants=variantAlias?[...properties(literal(variantAlias)).keys()]:[];
if(vehicle.ifv.rounds!==4||vehicle.ifv.gap!==.2)throw Error('IFV cadence changed; review VehicleRecoil and muzzle timing together');
if(vehicle.tank.evacuator.puffs>8||vehicle.ifv.breath.puffs>8||vehicle.ifv.cases.n>4||vehicle.tank.smoke>8||sparks.muzzle>8)throw Error('vehicle muzzle bounds changed; review port');
const data={sourceIfvVariants,gun:{tank:vehicle.gun.tank,ifv:vehicle.gun.ifv},gunHeight:vehicle.gunHeight,tank:vehicle.tank,ifv:vehicle.ifv,factions:{coalition:{flash:1,ball:1},republic:factions.republic.tank},colors:{fire:colors.fire,hot:colors.hot,ember:colors.ember,smoke:colors.smoke,smokeLight:colors.smokeLight,dustLight:colors.dustLight},motion:{rise:motion.rise,grow:motion.grow},sparks:{muzzle:sparks.muzzle,size:sparks.size,speed:sparks.impactSpeed,life:sparks.impactLife}};
function lua(v){if(v===null)return'nil';if(typeof v!=='object')return JSON.stringify(v);if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';return'{'+Object.entries(v).map(([k,x])=>'['+JSON.stringify(k)+']='+lua(x)).join(',')+'}';}
const target=path.join(root,'src/shared/GameData/VehicleMuzzleFx.luau');fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,'-- Generated locally from your install; git-ignored.\nreturn '+lua(data)+'\n');
console.log('Generated private base tank/IFV muzzle settings; reuses the existing particle atlas.');
if(sourceIfvVariants.length)console.log('Source also has faction-specific IFV dispatch for '+sourceIfvVariants.join(', ')+'. Those newer variant routines require a separate parity audit.');
