// Extract procedural crater settings from the owner's install. Output stays git-ignored.
// Usage: node export_craters.cjs <install> [project root]
const fs=require('fs'),path=require('path'),vm=require('vm');
const install=process.argv[2],root=path.resolve(process.argv[3]||path.join(__dirname,'../..'));
if(!install)throw Error('usage: node export_craters.cjs <install> [project root]');
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

function object(name){const m=new RegExp('(?:^|[^\\w$])'+escaped(name)+'=\\{').exec(main);if(!m)throw Error('missing source object '+name);return vm.runInNewContext('('+balanced(main,m.index+m[0].length-1)+')',{}, {timeout:1000});}
const start=main.lastIndexOf('class ',main.indexOf('wetAt(')),body=balanced(main,start);
if(!body.includes('dropOne()')||!body.includes('picture(')||!body.includes('clearBox('))throw Error('unrecognized crater model');
const alias=/const [\w$]+=([\w$]+)\.causes\[/.exec(body)?.[1];
const painter=/const [\w$]+=([\w$]+)\([\w$]+,[\w$]+\);return this\.baked\.set/.exec(body)?.[1];
if(!alias||!painter)throw Error('unrecognized crater bindings');
const at=main.indexOf('function '+painter+'('),paintSource=balanced(main,at);
const paintAlias=/const [\w$]+=([\w$]+),[\w$]+=[\w$]+\.texelsPerCell/.exec(paintSource)?.[1];
const pavedAlias=/,[\w$]+=([\w$]+),[\w$]+=[\w$]+\.paved\?/.exec(paintSource)?.[1];
const paletteAlias=/([\w$]+)=\{deep:"#[0-9a-fA-F]+",deepFleck:/.exec(main)?.[1];
const roadAlias=/>=[\w$]+\.highway\?([\w$]+)\.colours\.asphalt/.exec(main)?.[1];
if(!paintAlias||!pavedAlias||!paletteAlias||!roadAlias)throw Error('unrecognized crater palette/painter');
const model=object(alias),paint=object(paintAlias),paved=object(pavedAlias),palette=object(paletteAlias),road=object(roadAlias).colours;
if(!(model.max>0&&model.max<=512&&model.max%1===0&&model.maxCells>0&&model.maxCells<=8&&model.minCells>0&&model.merge>0&&model.grow>0&&model.fillSec>0)||!(paint.texelsPerCell>0&&paint.texelsPerCell<=8&&paint.texelsPerCell%1===0&&paint.steps<=8&&paint.steps>=1)||paint.bands.length!==6||paved.cracks>16||paved.slabs>16||!model.heal)throw Error('crater bounds changed; review port');
const data={model,paint,paved,palette,road:{road:road.road,asphalt:road.asphalt}};
function lua(v){if(v===null)return'nil';if(typeof v!=='object')return JSON.stringify(v);if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';return'{'+Object.entries(v).map(([k,x])=>'['+JSON.stringify(k)+']='+lua(x)).join(',')+'}';}
const target=path.join(root,'src/shared/GameData/CraterRules.luau');fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,'-- Generated locally from your install; git-ignored.\nreturn '+lua(data)+'\n');console.log('Generated private crater merge/water/heal rules and procedural painter settings.');
