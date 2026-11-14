// Extract ground impact settings from the owner's install. Output stays git-ignored.
// Usage: node export_impact_fx.cjs <install> [project root]
const fs=require('fs'),path=require('path'),vm=require('vm');
const install=process.argv[2],root=path.resolve(process.argv[3]||path.join(__dirname,'../..'));
if(!install)throw Error('usage: node export_impact_fx.cjs <install> [project root]');
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

const b=method('blast'),gp=method('groundPuff'),sp=method('sparks'),pu=method('puff');
function alias(pattern,text){const match=pattern.exec(text);if(!match)throw Error('unrecognized impact configuration: '+pattern);return match[1];}
const blast=imported(alias(/const [\w$]+=([\w$]+),[\w$]+=[\w$]+\.blast/,b));
const look=imported(alias(/const [\w$]+=([\w$]+)\.flash/,b),['flash','smoke']);
const colors=imported(alias(/[\w$]+===([\w$]+)\.smoke/,pu),['fire','hot','ember','coal','smoke','smokeLight','dust','dustLight']);
const motion=imported(alias(/vh:[\w$]+\?([\w$]+)\.rise/,gp),['rise','grow','debrisSpeed']);
const sparks=imported(alias(/const [\w$]+=([\w$]+);for/,sp),['size','blast','blastSpeed','blastRise','blastLife']);
const groundText=properties(literal(alias(/&&([\w$]+)\.ground\[/,method('groundLook')))).get('ground');
if(!groundText)throw Error('missing surface palette');
const earthText=properties(groundText).get('earth');if(!earthText)throw Error('missing earth palette');
const earth=vm.runInNewContext('('+earthText+')',{}, {timeout:1000});
const raw=imported(alias(/const [\w$]+=([\w$]+)\[[\w$]+\.weapon\]/,method('shotLanded')));
const names=['cannon','rocket','missile','shell','salvo','bomb','mortar','barrage','tbm'],weapons={};
for(const name of names){const w=raw[name];if(!w||!(w.blast>0&&w.blast<=64)||!(w.debris>=0&&w.debris<=32&&w.debris%1===0)||!(w.smoke>=0&&w.smoke<=16&&w.smoke%1===0)||!(w.smokeLife>0&&w.smokeLife<=12)||!(w.smokeSize>0&&w.smokeSize<=16))throw Error('weapon impact bounds changed: '+name);weapons[name]=Object.fromEntries(['blast','debris','smoke','smokeSize','smokeLife'].map(k=>[k,w[k]]));}
if(!look.flash||blast.bands.length>8||blast.dust>16||look.flash.maxPuffs>32||sparks.blast>32||earth.dustAmount>8||earth.smoke>4)throw Error('impact particle bounds changed; review port');
const data={blast,flash:look.flash,lean:look.smoke.lean,colors,motion,sparks,earth,weapons};
function lua(v){if(v===null)return'nil';if(typeof v!=='object')return JSON.stringify(v);if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';return'{'+Object.entries(v).map(([k,x])=>'['+JSON.stringify(k)+']='+lua(x)).join(',')+'}';}
const target=path.join(root,'src/shared/GameData/ImpactFx.luau');fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,'-- Generated locally from your install; git-ignored.\nreturn '+lua(data)+'\n');
console.log('Generated private ground-impact settings for '+names.length+' weapon profiles; existing atlas only.');
