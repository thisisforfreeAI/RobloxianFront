// Evaluate original fire-light grouping, burn-light animation and the ground-light raster.
// Output is original-derived local data: keep GameData ignored. No installed files are changed.
// node export_fire_lighting.cjs <install> [output root]
const fs=require('fs'),path=require('path'),vm=require('vm'),zlib=require('zlib');
const install=path.resolve(process.argv[2]||''),root=path.resolve(process.argv[3]||path.join(__dirname,'../..'));
if(!process.argv[2])throw Error('usage: export_fire_lighting.cjs <install> [output root]');
const rel=path.relative(install,root);if(!rel||(!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel)))throw Error('output must be outside original install');
const bytes=fs.readFileSync(path.join(install,'resources/app.asar')),header=JSON.parse(bytes.subarray(16,16+bytes.readUInt32LE(12))),entries=header.files.dist.files.assets.files;
function bundle(pattern){const e=entries[Object.keys(entries).find(n=>pattern.test(n))];if(!e)throw Error('missing original bundle');const at=8+bytes.readUInt32LE(4)+Number(e.offset);return bytes.subarray(at,at+e.size).toString();}
const main=bundle(/^main-.*\.js$/),effects=bundle(/^effects-.*\.js$/);
function block(s,start){if(start<0)throw Error('missing block');let depth=0;for(let i=start;i<s.length;i++){
 if(['"',"'",'`'].includes(s[i])){const q=s[i];while(++i<s.length&&s[i]!==q)if(s[i]==='\\')i++;}
 else if(s[i]==='{')depth++;else if(s[i]==='}'&&--depth===0)return s.slice(start,i+1);
}throw Error('unclosed original block');}
function object(name){const at=main.indexOf(name+'={');if(at<0)throw Error('missing original settings '+name);return block(main,main.indexOf('{',at));}
function method(s,head,start=0){const at=s.indexOf(head+'{',start);if(at<0)throw Error('missing original method '+head);return block(s,at+head.length);}
function fn(s,name){const at=s.indexOf('function '+name+'(');if(at<0)throw Error('missing original function '+name);const body=s.indexOf('{',at);return s.slice(at,body)+block(s,body);}
function klass(s,name){const at=s.indexOf('class '+name+'{');if(at<0)throw Error('missing original class '+name);const body=s.indexOf('{',at);return s.slice(at,body)+block(s,body);}
const sourceHash=/Yt=([\w$]+)=>/.exec(effects);if(!sourceHash)throw Error('missing original light hash');
const hashBody=block(effects,effects.indexOf('{',sourceHash.index)),hash='('+sourceHash[1]+')=>'+hashBody;
const hashValues=/Math\.sin\([^*]+\*([\d.]+)\+([\d.]+)\)\*([\d.]+)/.exec(hashBody);
const bayer=JSON.parse(/\bFqt=(\[[\d,]+\])\.map/.exec(main)?.[1]||'null');
const lookupSize=Number(/\bmu=(\d+)/.exec(main)?.[1]);
const imports=effects.slice(0,effects.indexOf('from"./main-')),exportNames=main.slice(main.lastIndexOf('export{'));
const fpsName=/([\w$]+) as It(?:,|})/.exec(imports)?.[1];const fpsSymbol=fpsName&&new RegExp('([\\w$]+) as '+fpsName.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+'(?:,|})').exec(exportNames)?.[1];
const fps=fpsSymbol&&Number(new RegExp('\\b'+fpsSymbol+'=(\\d+)').exec(main)?.[1]);
if(!hashValues||!bayer||!lookupSize||!fps)throw Error('changed original light constants');
const context={E:(o,k,v)=>{o[k]=v;},performance:{now:()=>0}};vm.createContext(context);
vm.runInContext('const zv='+object('zv')+',Yat='+object('Yat')+',h1='+object('h1')+',$s='+object('$s')+',Ws='+object('Ws')+',br='+object('br')+',U0='+object('U0')+';'+
 'globalThis.profile={forest:$s.light,houses:Ws.light,light:br,nv:U0};'+
 'globalThis.forestLights=function(t)'+method(main,'lights(t)',main.indexOf('class Ihe{'))+';'+
 'globalThis.houseLights=function(t)'+method(main,'lights(t)',main.indexOf('class Ohe{'))+';'+
 'globalThis.hotHouses=function(t,o)'+method(main,'hotSquares(t,o)',main.indexOf('class Ohe{'))+';',context);
const profile={...context.profile,hash:Array.from(hashValues.slice(1),Number),bayer,lookupSize,fps,tickSec:vm.runInContext('$s.tickSec',context)};
const actors=Array.from({length:66},(_,i)=>({x:1+(i%12)*4+.1*(i%3),y:1+Math.floor(i/12)*4,cell:i,age:1,life:40}));
const grouping=[];
for(const kind of ['forest','houses'])for(const count of [0,1,6,30,66]){
 const requests=[],model={burns:actors.slice(0,count),houses:actors.slice(0,count),lit:new Map,glowing:[],time:0,hotSquares:context.hotHouses,
  sees:(_game,cell)=>cell%5!==3,fx:{light:p=>requests.push(p)}};
 const states=[];for(const time of [0,.25,5,5.2,6,10.4]){
  model.time=time;requests.length=0;context[kind==='forest'?'forestLights':'houseLights'].call(model,{w:64});
  states.push({time,requests:structuredClone(requests),due:[...model.lit]});
 }
 grouping.push({kind,actors:actors.slice(0,count),states});
}
vm.runInContext('const T=profile.light,It=fps,Yt='+hash+';globalThis.step=function(t)'+method(effects,'stepLights(t)'),Object.assign(context,{fps}));
const animation=[];for(const seed of [0,73.171,999.8]){
 const light={x:1,y:1,h:.6,reach:5,power:1.25,age:0,life:7,seed,curve:'burn',follow:null};const model={lights:[light],lightPool:[],lightBox:{}};
 const states=[];for(const dt of [0,.1,.2,.2,1,3.7,1,1]){context.step.call(model,dt);states.push({dt,active:model.lights.length,age:light.age,now:light.now??null});}
 animation.push({seed,states});
}
const canvas={style:{},getContext:()=>({createImageData:(w,h)=>({data:new Uint8ClampedArray(w*h*4)}),clearRect(){},putImageData(){}})};
Object.assign(context,{canvas});
vm.runInContext('const no={mix:0},m1={night:false},Ss={night:{bands:br.bands,dither:br.dither}},Fqt='+JSON.stringify(bayer)+'.map(x=>(x+.5)/16),mu='+lookupSize+',$qt=2048,Bqt=32,nr=()=>{};'+
 fn(main,'vW')+fn(main,'yJ')+';const Nqt=vW(br.bands,br.dither),qqt=Nqt,Zqt=vW(U0.bands,U0.dither,U0.falloff);'+klass(main,'tde')+';globalThis.make=()=>new tde(canvas);globalThis.mix=v=>no.mix=v;',context);
const raster=[];for(const mix of [0,1])for(const scale of [4,8,16]){
 context.mix(mix);const layer=context.make();const lights=[{x:2.1,y:3.7,reach:5,power:.9,color:profile.light.fire},{x:7.3,y:5.2,reach:3.8,power:1.3,color:profile.light.fire}];
 layer.draw(lights,{scale,tx:0,ty:0,width:12*scale,height:10*scale},true);
 const w=12*Math.max(1,Math.min(profile.light.texelsPerCell,Math.floor(scale/profile.light.minTexelPx))),h=10*Math.max(1,Math.min(profile.light.texelsPerCell,Math.floor(scale/profile.light.minTexelPx)));
 const rgba=Buffer.alloc(w*h*4);for(let y=0;y<h;y++)for(let x=0;x<w;x++)rgba.set(layer.image.data.subarray(((y-layer.oy)*layer.stride+x-layer.ox)*4,((y-layer.oy)*layer.stride+x-layer.ox)*4+4),(y*w+x)*4);
 raster.push({mix,scale,lights,w,h,deflate:zlib.deflateRawSync(rgba).toString('base64')});
}
function lua(v){if(v===null)return'nil';if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';if(typeof v==='object')return'{'+Object.entries(v).map(([k,v])=>'['+JSON.stringify(k)+']='+lua(v)).join(',')+'}';return JSON.stringify(v);}
function write(name,value){const out=path.join(root,'src/shared/GameData',name+'.luau');fs.mkdirSync(path.dirname(out),{recursive:true});fs.writeFileSync(out,'-- GENERATED original fire-light data/references. Local only, git-ignored.\nreturn '+lua(value)+'\n');}
write('FireLightRules',profile);write('FireLightVectors',{grouping,animation,raster});
console.log('Exported original fire-light settings,',grouping.length,'group/refresh cases,',animation.length,'burn curves and',raster.length,'raster frames');
