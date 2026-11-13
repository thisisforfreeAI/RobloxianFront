// Extract AT/mortar muzzle settings from the owner's local install. Output stays git-ignored.
// Usage: node export_crew_muzzle.cjs <install> [project root]
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

// Resolve configuration via the methods' semantic properties, across minifier alias changes.
const tube=method('tubeFire'),back=method('backblast'),mortar=method('mortarMuzzle'),puff=method('puff');
const menAlias=/const [\w$]+=([\w$]+),[\w$]+=[\w$]+\.backblast/.exec(tube)?.[1];
const weaponAlias=/[\w$]+=([\w$]+)\[[\w$]+\.weapon\]/.exec(tube)?.[1];
const artAlias=/\*\(([\w$]+)\.muzzle\[/.exec(tube)?.[1];
const fireAlias=/([\w$]+)\.fire\.muzzleH/.exec(mortar)?.[1];
const motionAlias=/vh:[\w$]+\?([\w$]+)\.rise/.exec(puff)?.[1];
const colorAlias=/color:([\w$]+)\.fire/.exec(back)?.[1];
const groundAlias=/&&([\w$]+)\.ground\[/.exec(method('groundLook'))?.[1];
const overrides=/const [\w$]+=[\w$]+\?\([\w$]+=([\w$]+)\[/.exec(back)?.[1];
if(!menAlias||!weaponAlias||!artAlias||!fireAlias||!motionAlias||!colorAlias||!groundAlias)throw Error('unrecognized crew effect configuration paths');
const men=imported(menAlias,['muzzleH','aimSlack','backblast','tubeRear','tubeRearProne']);
const art=imported(artAlias,['muzzle']),weapons=imported(weaponAlias,['rocket']),mortarFire=imported(fireAlias,['fire']).fire;
const colors=imported(colorAlias,['fire','hot','smokeLight','dustLight','debris']),motion=imported(motionAlias,['rise','grow']);
const ground=properties(literal(groundAlias)).get('ground');if(!ground)throw Error('missing ground materials');
const earth=properties(ground).get('earth');if(!earth)throw Error('missing default ground material');
const material=vm.runInNewContext('('+earth+')',{}, {timeout:1000});
const sourceVariants=overrides?[...properties(literal(overrides)).keys()]:[];
const variants=overrides?imported(overrides):{};
const data={men:{muzzleH:men.muzzleH,aimSlack:men.aimSlack},proneBack:.57,tubeRear:men.tubeRear,tubeRearProne:men.tubeRearProne,backblast:men.backblast,backblastOverrides:{republic:variants.republic?.backblast||{}},rocketSmoke:weapons.rocket.muzzleSmoke,muzzle:{gunner:art.muzzle.gunner,loader:art.muzzle.loader,tube:art.muzzle.tube},mortar:mortarFire,colors,motion,ground:{dust:material.dust,dustPale:material.dustPale,dustHang:material.dustHang},sourceVariants};
if(!data.muzzle.gunner?.kneel||!data.muzzle.tube?.kick||data.rocketSmoke>8||men.backblast.puffs>32||men.backblast.grit>16||mortarFire.dust>32||mortarFire.smoke>16)throw Error('crew particle/geometry bounds changed; review port');
if(!main.includes('proneBack:.57'))throw Error('prone anchor changed; review crew and rifle geometry');
function lua(v){if(v===null)return'nil';if(typeof v!=='object')return JSON.stringify(v);if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';return'{'+Object.entries(v).map(([k,x])=>'['+JSON.stringify(k)+']='+lua(x)).join(',')+'}';}
const target=path.join(root,'src/shared/GameData/CrewMuzzleFx.luau');fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,'-- Generated locally from your install; git-ignored.\nreturn '+lua(data)+'\n');
console.log('Generated private AT/mortar muzzle settings. Source variant families:',sourceVariants.join(', '));
