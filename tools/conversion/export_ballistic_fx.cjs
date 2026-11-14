// Extract ballistic flight settings from the owner's install. Output stays git-ignored.
// Usage: node export_ballistic_fx.cjs <install> [project root]
const fs=require('fs'),path=require('path'),vm=require('vm');
const install=process.argv[2],root=path.resolve(process.argv[3]||path.join(__dirname,'../..'));
if(!install)throw Error('usage: node export_ballistic_fx.cjs <install> [project root]');
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

const flight=method('projectile'),threadMethod=method('shellThread');
function alias(re,text){const m=re.exec(text);if(!m)throw Error('unrecognized ballistic binding '+re);return m[1];}
const weaponAlias=/\{\.\.\.([\w$]+)\[[\w$]+\.weapon\]/.exec(flight)?.[1]??/\?\?([\w$]+)\[[\w$]+\.weapon\]/.exec(flight)?.[1];
if(!weaponAlias)throw Error('unrecognized projectile profiles');
const weapons=imported(weaponAlias,['rocket','mortar','shell','salvo']);
const sparkAlias=alias(/,[\w$]+=([\w$]+),[\w$]+=[\w$]+\.width\*[\w$]+\.flameWidth/,flight);
const sparks=imported(sparkAlias,['flameWidth','flameLength','flameFlicker','motorSec','impactLife','size']);
const look=imported(alias(/\?([\w$]+)\.rocketTrail:null/,flight),['rocketTrail']);
const motion=imported(alias(/vh:[\w$]+\?([\w$]+)\.rise/,method('puff')),['rise','grow']);
const colors=imported(alias(/color:[\w$]+\?[\w$]+\.color:([\w$]+)\.shell/,flight),['shell','fire','hot','ember','smokeLight']);
const artillery=imported(alias(/const [\w$]+=([\w$]+)\.artillery,/,threadMethod),['artillery']).artillery;
const salvo=imported(alias(/const [\w$]+=([\w$]+),[\w$]+=Math\.max/,method('rocketLaunch')));
function number(alias){const imp=effects.slice(0,effects.indexOf('from"./main-')),key=new RegExp('([\\w$]+) as '+escaped(alias)+'(?:,|})').exec(imp)?.[1],symbol=key&&new RegExp('([\\w$]+) as '+escaped(key)+'(?:,|})').exec(main.slice(main.lastIndexOf('export{')))?.[1];const match=symbol&&new RegExp('(?:^|[^\\w$])'+escaped(symbol)+'=(\\d+(?:\\.\\d+)?)(?=[,;])').exec(main);if(!match)throw Error('missing numeric import '+alias);return Number(match[1]);}
const tickAlias=alias(/Math\.floor\([\w$]+\.age\*([\w$]+)\*2\)/,flight),tickHz=number(tickAlias);
const proj=alias(/Math\.atan2\([^,]+\*([\w$]+),/,flight),tiltAlias=new RegExp(escaped(proj)+'=Math\\.cos\\(([\\w$]+)\\*').exec(effects)?.[1];
if(!tiltAlias||number(tiltAlias)!==62)throw Error('projection changed; review native camera mapping');
const profiles={};for(const [name,p]of Object.entries(weapons)){for(const key of ['length','width','arc','arcMax','trail','trailSize','trailLife','speed'])if(!Number.isFinite(p[key]))throw Error('invalid weapon '+name);if(!(p.speed>0&&p.speed<=100&&p.length>0&&p.length<=8&&p.width>0&&p.width<=4&&p.arc>=0&&p.arc<=4&&p.arcMax>=0&&p.arcMax<=64&&p.trail>=0&&p.trail<=100&&p.trailLife<=12))throw Error('ballistic bounds changed');profiles[name]=Object.fromEntries(['length','width','arc','arcMax','trail','trailSize','trailLife','speed'].map(k=>[k,p[k]]));}
if(!(sparks.motorSec>0&&sparks.motorSec<=2&&tickHz>0&&tickHz<=120&&artillery.thread<=100&&look.rocketTrail.wisps<=100&&salvo.rockets<=64))throw Error('trail bounds changed');
const data={profiles,flame:sparks,contrail:look.rocketTrail,motion,colors,thread:{rate:artillery.thread,size:artillery.threadSize,life:artillery.threadLife,color:artillery.threadColor},salvo:{count:salvo.rockets,spread:salvo.spread,stagger:salvo.stagger,jitter:salvo.staggerJitter},tickHz,heightFactor:Math.cos(62*Math.PI/180)};
function lua(v){if(v===null)return'nil';if(typeof v!=='object')return JSON.stringify(v);if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';return'{'+Object.entries(v).map(([k,x])=>'['+JSON.stringify(k)+']='+lua(x)).join(',')+'}';}
const target=path.join(root,'src/shared/GameData/BallisticFx.luau');fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,'-- Generated locally from your install; git-ignored.\nreturn '+lua(data)+'\n');console.log('Generated private AT/mortar/howitzer/salvo flight and trail settings.');
