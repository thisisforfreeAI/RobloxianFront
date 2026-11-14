// Extract vehicle tracer settings from the owner's install. Output stays git-ignored.
// Usage: node export_vehicle_tracers.cjs <install> [project root]
const fs=require('fs'),path=require('path'),vm=require('vm');
const install=process.argv[2],root=path.resolve(process.argv[3]||path.join(__dirname,'../..'));
if(!install)throw Error('usage: node export_vehicle_tracers.cjs <install> [project root]');
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

const vehicle=method('vehicleFire'),automatic=method('autocannon'),round=method('round');
const tracerAlias=/const [\w$]+=([\w$]+),[\w$]+=\{speed:[\w$]+\.cannon\.speed/.exec(vehicle)?.[1];
const weaponAlias=/speed:([\w$]+)\.cannon\.speed/.exec(vehicle)?.[1];
const ifvAlias=/const [\w$]+=([\w$]+)\.ifv,/.exec(automatic)?.[1];
const armyAlias=/[\w$]+\.army&&\(\([\w$]+=([\w$]+)\[[\w$]+\.army\]\)/.exec(vehicle)?.[1];
const colorAlias=/headColor:([\w$]+)\.hot/.exec(vehicle)?.[1];
if(!tracerAlias||!weaponAlias||!ifvAlias||!armyAlias||!colorAlias)throw Error('unrecognized tracer bindings');
const common=imported(tracerAlias,['tip','cannonTail','cannonWidth','cannonColor']),weapons=imported(weaponAlias,['cannon']),ifv=imported(ifvAlias,['ifv']).ifv,armies=imported(armyAlias),colors=imported(colorAlias,['hot']);
if(!round.includes('tex:"streak"')||!/streak:[\w$]+\(1,3\)/.test(effects)||ifv.rounds!==4||ifv.gap!==.2)throw Error('changed tracer atlas/cadence; review port');
const tank={speed:weapons.cannon.speed,tail:common.cannonTail,width:common.cannonWidth,color:common.cannonColor,headColor:colors.hot};
const auto={speed:ifv.speed,tail:ifv.tail,width:ifv.width,color:ifv.color,headColor:colors.hot,walk:ifv.walk,spread:ifv.spread};
for(const p of [tank,auto])if(!(p.speed>0&&p.speed<=500&&p.width>0&&p.width<=4&&p.tail>=0&&p.tail<=32))throw Error('tracer bounds changed');
if(!(common.tip>0&&common.tip<=32)||auto.walk<0||auto.walk>4||auto.spread<0||auto.spread>8)throw Error('tracer profile changed');
const factions={};for(const army of ['coalition','republic']){const a=armies[army];if(a)factions[army]={tank:a.cannonColor??tank.color,ifv:a.autocannon??auto.color};}
const projection=/Math\.atan2\([^,]+\*([\w$]+),/.exec(round)?.[1];
const height=projection&&new RegExp(escaped(projection)+'=Math\\.cos\\(([\\w$]+)\\*([\\w$]+)\\)').exec(effects);
const im=effects.slice(0,effects.indexOf('from"./main-')),key=height&&new RegExp('([\\w$]+) as '+escaped(height[1])+'(?:,|})').exec(im)?.[1],symbol=key&&new RegExp('([\\w$]+) as '+escaped(key)+'(?:,|})').exec(main.slice(main.lastIndexOf('export{')))?.[1];
const camera=symbol&&new RegExp('(?:^|[^\\w$])'+escaped(symbol)+'=(\\d+)(?=[,;])').exec(main)?.[1];if(Number(camera)!==62)throw Error('projection tilt changed; review native height mapping');
const data={tip:common.tip,heightFactor:Math.cos(Number(camera)*Math.PI/180),tank,ifv:auto,factions};
function lua(v){if(v===null)return'nil';if(typeof v!=='object')return JSON.stringify(v);if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';return'{'+Object.entries(v).map(([k,x])=>'['+JSON.stringify(k)+']='+lua(x)).join(',')+'}';}
const target=path.join(root,'src/shared/GameData/VehicleTracerFx.luau');fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,'-- Generated locally from your install; git-ignored.\nreturn '+lua(data)+'\n');console.log('Generated private tank/IFV normal-view tracer settings; existing streak atlas crop.');
