// Read the installed map worker and original .city; generate ignored fire-map data only.
// node export_fire_map.cjs <install> <map id> <file.city> [output root]
const fs=require('fs'),path=require('path'),vm=require('vm'),zlib=require('zlib');
const [installArg,mapId,cityPath,rootArg]=process.argv.slice(2);if(!installArg||!mapId||!cityPath)throw Error('usage: export_fire_map.cjs <install> <map id> <file.city> [output root]');
const install=path.resolve(installArg),root=path.resolve(rootArg||path.join(__dirname,'../..')),rel=path.relative(install,root);
if(!rel||(!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel)))throw Error('output must stay outside original install');
const bytes=fs.readFileSync(path.join(install,'resources/app.asar')),header=JSON.parse(bytes.subarray(16,16+bytes.readUInt32LE(12))),entries=header.files.dist.files.assets.files;
function bundle(pattern){const e=entries[Object.keys(entries).find(n=>pattern.test(n))];if(!e)throw Error('missing original bundle');const at=8+bytes.readUInt32LE(4)+Number(e.offset);return bytes.subarray(at,at+e.size).toString();}
const s=bundle(/^main-.*\.js$/);
function block(start){if(start<0)throw Error('missing declaration');let depth=0;for(let i=start;i<s.length;i++){
 if(['"',"'",'`'].includes(s[i])){const q=s[i];while(++i<s.length&&s[i]!==q)if(s[i]==='\\')i++;}
 else if(s[i]==='{')depth++;else if(s[i]==='}'&&--depth===0)return s.slice(start,i+1);
}throw Error('unterminated declaration');}
function object(name){const at=s.indexOf(name+'={');if(at<0)throw Error('missing settings '+name);return block(s.indexOf('{',at));}
function fn(name){const at=s.indexOf('function '+name+'(');if(at<0)throw Error('missing function '+name);const body=s.indexOf('{',at);return s.slice(at,body)+block(body);}
function klass(name){const at=s.indexOf('class '+name+'{');if(at<0)throw Error('missing class '+name);const body=s.indexOf('{',at);return s.slice(at,body)+block(body);}
let response;const self={postMessage:v=>{response=v;}};
vm.runInNewContext(bundle(/^genWorker-.*\.js$/),{self,console,TextEncoder,TextDecoder,structuredClone});self.onmessage({data:{id:1,map:mapId}});
const map=response?.map;if(!map||response.error)throw Error('original map generation failed');
const city=fs.readFileSync(cityPath);if(city.subarray(0,4).toString()!=='WFCT')throw Error('invalid city file');
const hlen=city.readUInt32LE(4),head=JSON.parse(city.subarray(8,8+hlen));
if(head.id!==mapId||head.key.split(':')[1]!==map.width+'x'+map.height)throw Error('city/map identity differs');
const raw={},packed={};let pos=8+hlen;
for(const p of head.parts){if(['atlas','index','cells'].includes(p.name)){packed[p.name]=city.subarray(pos,pos+p.packed);raw[p.name]=zlib.inflateRawSync(packed[p.name]);if(raw[p.name].length!==p.raw)throw Error('bad city part size');}pos+=p.packed;}
if(!raw.atlas||!raw.index||!raw.cells)throw Error('missing city parts');
const pad=Number(/pad:([\d.]+)/.exec(object('n9'))?.[1]),roofFrom=Number(/alpha:\{[^}]*roofFrom:(\d+)/.exec(object('eo'))?.[1]);
if(!Number.isFinite(pad)||!roofFrom)throw Error('missing source roof/reservation settings');
const reserved=Buffer.alloc(map.width*map.height),reach=Math.ceil(pad/2/head.size)+1;
for(const rig of map.rigs){const x=Math.floor(rig.x),y=Math.floor(rig.y);for(let cy=Math.max(0,y-reach);cy<=Math.min(map.height-1,y+reach);cy++)for(let cx=Math.max(0,x-reach);cx<=Math.min(map.width-1,x+reach);cx++)reserved[cy*map.width+cx]=1;}
// The generated map has no runtime radii. Use the separately exported, scaled match rules.
const matchRules=fs.readFileSync(path.join(root,'src/shared/GameData/RulesMatch.luau'),'utf8');
const settlements=map.settlements.map(t=>{const value=new RegExp('\\["settlements\\.'+t.kind+'Radius"\\] = ([\\d.]+)').exec(matchRules);if(!value)throw Error('missing exported town radius: '+t.kind);return{...t,x:Math.max(0,Math.min(map.width-1,Math.floor(t.x)))+.5,y:Math.max(0,Math.min(map.height-1,Math.floor(t.y)))+.5,radius:Number(value[1])};});
const towns=vm.runInNewContext('const YY='+object('YY')+',XY=new WeakMap;'+fn('F4t')+';F4t(map)',{map:{w:map.width,h:map.height,settlements}});
if(towns.length!==map.width*map.height||!towns.some(x=>x>0))throw Error('empty source town membership');
const townBytes=Buffer.from(towns.buffer,towns.byteOffset,towns.byteLength);
const data={id:mapId,width:map.width,height:map.height,tileSize:head.size,atlasWidth:head.atlasW,atlasHeight:head.atlasH,perRow:head.perRow,count:head.count,roofFrom,
 atlasParts:[],index:packed.index.toString('base64'),cells:packed.cells.toString('base64'),reserved:zlib.deflateRawSync(reserved).toString('base64'),towns:zlib.deflateRawSync(townBytes).toString('base64')};
const context={E:(o,k,v)=>{o[k]=v;}};vm.createContext(context);
const claimMark=Number(/\bQE=(\d+)/.exec(s)?.[1]);if(!claimMark)throw Error('missing original claim mark');
vm.runInContext('const QE='+claimMark+',eo={alpha:{roofFrom:'+roofFrom+'}},Ws='+object('Ws')+',As='+object('As')+';'+fn('m2')+klass('Ohe')+';globalThis.make=()=>new Ohe({},()=>{},()=>{});',context,{timeout:10000});
const original=context.make();original.w=map.width;original.h=map.height;original.setCity({size:head.size,atlasW:head.atlasW,atlasH:head.atlasH,perRow:head.perRow,count:head.count,index:raw.index,atlas:raw.atlas});
const refs=[];let seed=771;
for(let i=0;i<1200;i++){
 seed=(Math.imul(seed,1664525)+1013904223)>>>0;const x=i<4?[-1,0,map.width*head.size-1,map.width*head.size][i]:seed%(map.width*head.size+2)-1;
 seed=(Math.imul(seed,1664525)+1013904223)>>>0;const y=i<4?[-1,0,map.height*head.size-1,map.height*head.size][i]:seed%(map.height*head.size+2)-1;
 const id=original.pixelAt(x,y);refs.push({x,y,id,rgba:id<0?null:Array.from(raw.atlas.subarray(id*4,id*4+4))});
}
const rigRefs=map.rigs.map(r=>({x:r.x,y:r.y,cell:Math.floor(r.y)*map.width+Math.floor(r.x)}));
const claims=[];original.noFire=reserved;
for(const r of refs){if(r.id<0||r.rgba[3]<roofFrom)continue;original.mark.fill(0);const found=original.claim(r.x,r.y);if(found)claims.push({x:r.x,y:r.y,ids:Array.from(found)});if(claims.length>=16)break;}
function lua(v){if(v===null)return'nil';if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';if(typeof v==='object')return'{'+Object.entries(v).map(([k,v])=>'['+JSON.stringify(k)+']='+lua(v)).join(',')+'}';return JSON.stringify(v);}
function write(rel,value){const dst=path.join(root,rel);fs.mkdirSync(path.dirname(dst),{recursive:true});fs.writeFileSync(dst,'-- GENERATED local-only original fire roof map/reference output.\nreturn '+lua(value)+'\n');}
// Port storage policy: smaller source modules, instead of one multi-megabyte script literal.
for(let offset=0;offset<raw.atlas.length;offset+=512*1024){
 const bytes=Math.min(512*1024,raw.atlas.length-offset),name='FireMap_'+mapId+'_Atlas'+(data.atlasParts.length+1);
 data.atlasParts.push({name,offset,bytes});write('src/shared/GameData/'+name+'.luau',{deflate:zlib.deflateRawSync(raw.atlas.subarray(offset,offset+bytes)).toString('base64')});
}
const townSamples=Array.from({length:2000},(_,i)=>{const cell=(i*7919+177)%towns.length;return{cell,town:towns[cell]};});
write('src/shared/GameData/FireMap_'+mapId+'.luau',data);write('src/shared/GameData/FireMapVectors_'+mapId+'.luau',{refs,rigs:rigRefs,claims,townSamples,reservedCells:reserved.reduce((a,b)=>a+b,0)});
console.log('Fire map:',mapId,map.width+'x'+map.height,head.count,'source tiles;',refs.length,'original coordinate references;',reserved.reduce((a,b)=>a+b,0),'reserved cells.');
