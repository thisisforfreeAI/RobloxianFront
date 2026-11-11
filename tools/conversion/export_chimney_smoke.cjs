// Evaluate local original placement, puff art and animation references; emit only ignored data.
// node export_chimney_smoke.cjs <install> <private input.json> [output root]
const fs=require('fs'),path=require('path'),vm=require('vm'),zlib=require('zlib');
const [installArg,input,rootArg]=process.argv.slice(2);
if(!installArg||!input)throw Error('usage: export_chimney_smoke.cjs <install> <input.json> [output root]');
const install=path.resolve(installArg),root=path.resolve(rootArg||path.join(__dirname,'../..'));
const rel=path.relative(install,root);
if(!rel||(!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel)))throw Error('output must stay outside original install');
const b=fs.readFileSync(path.join(install,'resources/app.asar')),header=JSON.parse(b.subarray(16,16+b.readUInt32LE(12)));
const entries=header.files.dist.files.assets.files,e=entries[Object.keys(entries).find(n=>/^main-.*\.js$/.test(n))],at=8+b.readUInt32LE(4)+Number(e.offset);
const source=b.subarray(at,at+e.size).toString();
function block(first){
 if(first<0)throw Error('missing original declaration');let depth=0;
 for(let i=first;i<source.length;i++){
  if(source[i]==='"'||source[i]==="'"||source[i]==='`'){const q=source[i];while(++i<source.length&&source[i]!==q)if(source[i]==='\\')i++;}
  else if(source[i]==='{')depth++;else if(source[i]==='}'&&--depth===0)return source.slice(first,i+1);
 }throw Error('unterminated original declaration');
}
function fn(name){const a=source.indexOf('function '+name+'(');if(a<0)throw Error('missing original function '+name);return source.slice(a,source.indexOf('{',a))+block(source.indexOf('{',a));}
function object(name){const a=source.indexOf(name+'={');if(a<0)throw Error('missing original table '+name);return block(source.indexOf('{',a));}
const game=JSON.parse(fs.readFileSync(input,'utf8'));
if(!game.urban||game.urban.length!==game.w*game.h||game.road.length!==game.urban.length)throw Error('incomplete smoke map inputs');
game.cellX=c=>c%game.w;game.cellY=c=>Math.floor(c/game.w);
const context={ImageData:class{constructor(width,height){this.width=width;this.height=height;this.data=new Uint8ClampedArray(width*height*4);}},E:(o,k,v)=>{o[k]=v},$r:()=>true,pc:()=>true};
vm.createContext(context);
const start=source.indexOf('const Kn='),end=source.indexOf('class Ftt',start),cls=source.indexOf('class fQt'),hash=source.indexOf('const Do=');
if(start<0||end<start||cls<0||hash<0)throw Error('missing original ambient declarations');
vm.runInContext('const sn='+object('sn')+',As='+object('As')+';'+source.slice(start,end)+fn('dQt')+fn('cQt')+fn('To')+
 source.slice(hash,source.indexOf(';',hash)+1)+fn('pQt')+source.slice(cls,source.indexOf('{',cls))+block(source.indexOf('{',cls))+
 ';globalThis.original={sn,As,zc,u$,cQt,pQt,fQt};',context,{timeout:10000});
const original=context.original;
const config={from:original.sn.from,full:original.sn.full,smoke:original.sn.smoke,towns:original.sn.towns,
 wind:{x:original.As.windX,y:original.As.windY},criticalBelow:game.criticalBelow,damagedBelow:game.damagedBelow};
const towns=game.settlements.map(t=>({id:t.id+1,x:t.x,y:t.y,radius:t.radius,kind:t.kind,chimneys:original.pQt(game,t,config.towns.chimneys[t.kind]||0)}));
const frame=Math.ceil(original.u$.puff.span*original.zc.px/2)*2,baked=original.cQt('puff',frame);
const data={width:baked.image.width,height:baked.image.height,frame,facings:original.zc.facings,px:original.zc.px,config,towns,
 deflate:zlib.deflateRawSync(Buffer.from(baked.image.data)).toString('base64')};
function lua(v){if(v===null)return'nil';if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';if(typeof v==='object')return'{'+Object.entries(v).map(([k,v])=>'['+JSON.stringify(k)+']='+lua(v)).join(',')+'}';return JSON.stringify(v);}
function write(rel,value,comment){const target=path.join(root,rel);fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,'-- GENERATED local-only original '+comment+'.\nreturn '+lua(value)+'\n');}
write('src/client/DevAssets/OrigChimneySmoke_saddle.luau',data,'chimney layout, puff art and settings');
// Reference the original class's draw/smoke, including density before its smoke method.
const cases=[];
for(const band of ['healthy','damaged','critical'])for(const garrison of [0,2])for(const night of [0,.3,.6,.625,1])for(const time of [0,.041,1.75,5.499,5.5,18.25,300]){
 const integrity=band==='healthy'?100:band==='damaged'?100*(game.criticalBelow+game.damagedBelow)/2:100*game.criticalBelow/2;
 const town={...towns[0],st:{integrity,garrison:Array(garrison).fill(1),lastHitAt:time},shockAt:-99};
 const sample=new original.fQt();sample.towns=[town];sample.cars=sample.parked=sample.people=()=>{};
 const poses=[],share=.83;
 sample.draw({time,night,share,k:20,tx:0,ty:0,tint:0,game:{integrityBand:()=>band},sprites:{draw(...a){if(a[7]>.02&&a[4]>0)poses.push({x:a[2]/20,y:a[3]/20,cells:a[4]/20,heading:a[5],alpha:a[7]});}},c:null});
 cases.push({time,night,share,integrity,garrison,poses});
}
write('src/shared/GameData/ChimneySmokeVectors.luau',{config,town:towns[0],cases},'smoke reference poses');
console.log('Original chimney smoke:',towns.length,'towns,',towns.reduce((n,t)=>n+t.chimneys.length,0),'chimneys;',data.width+'x'+data.height,'shared puff atlas;',cases.length,'reference cases');
