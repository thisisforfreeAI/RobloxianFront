// Capture original puff/ember primitive requests without requiring a canvas or copying source art.
// node export_fire_particles.cjs <install> [output root]
const fs=require('fs'),path=require('path'),vm=require('vm');
const install=path.resolve(process.argv[2]||''),root=path.resolve(process.argv[3]||path.join(__dirname,'../..'));if(!process.argv[2])throw Error('usage: export_fire_particles.cjs <install> [output root]');
const rel=path.relative(install,root);if(!rel||(!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel)))throw Error('output must stay outside original install');
const b=fs.readFileSync(path.join(install,'resources/app.asar')),h=JSON.parse(b.subarray(16,16+b.readUInt32LE(12))),entries=h.files.dist.files.assets.files;
function asset(pattern){const e=entries[Object.keys(entries).find(n=>pattern.test(n))];if(!e)throw Error('missing original bundle');const at=8+b.readUInt32LE(4)+Number(e.offset);return b.subarray(at,at+e.size).toString();}
const main=asset(/^main-.*\.js$/),effects=asset(/^effects-.*\.js$/);
function block(src,start){start=src.indexOf('{',start);let depth=0;for(let i=start;i<src.length;i++){
 if(['"',"'",'`'].includes(src[i])){const q=src[i];while(++i<src.length&&src[i]!==q)if(src[i]==='\\')i++;}
 else if(src[i]==='{')depth++;else if(src[i]==='}'&&--depth===0)return src.slice(start,i+1);
}throw Error('unterminated original block');}
function imported(alias){const imp=effects.slice(0,effects.indexOf('from"./main-')),key=new RegExp('([\\w$]+) as '+alias+'(?:,|})').exec(imp)?.[1];
 const symbol=key&&new RegExp('([\\w$]+) as '+key+'(?:,|})').exec(main.slice(main.lastIndexOf('export{')))?.[1];if(!symbol)throw Error('missing original import');const at=main.indexOf(symbol+'={');if(at<0)throw Error('missing original settings');return vm.runInNewContext('('+block(main,at)+')');}
function method(name){const match=new RegExp('\\b'+name+'\\([^)]*\\)\\{').exec(effects);if(!match)throw Error('missing original method');return effects.slice(match.index,effects.indexOf('{',match.index))+block(effects,match.index);}
const data={colors:imported('w'),sparks:imported('N'),motion:imported('C')};
const puffAt=effects.indexOf('$=['),puffNames=JSON.parse(effects.slice(puffAt+2,effects.indexOf(']',puffAt)+1));
const context={data,out:[]};vm.createContext(context);
vm.runInContext('const N=data.sparks,w=data.colors,C=data.motion,$='+JSON.stringify(puffNames)+',d=(a,b)=>a+Math.random()*(b-a),_=r=>d(r[0],r[1]),H=a=>a[Math.floor(Math.random()*a.length)];globalThis.original={spawn:p=>out.push(p),'+method('puff')+','+method('embers')+'};',context);
const cases=[];
for(const seed0 of [1,71,919])for(const kind of ['puff','embers']){
 let seed=seed0;const math=Object.create(Math);math.random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};context.Math=math;context.out=[];
 const p={x:4,y:7,h:.6,size:1.3,life:3.2,color:data.colors.smoke,rise:1.9,vx:.1,vy:-.1,ground:false,small:true,count:4,spread:.3};
 if(kind==='puff')context.original.puff(p.x,p.y,p.h,p.size,p.life,p.vx,p.vy,p.color,p.small,p.ground,p.rise);else context.original.embers(p.x,p.y,p.h,p.count,p.spread);
 cases.push({seed:seed0,kind,p,particles:context.out});
}
function lua(v){if(v===null)return'nil';if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';if(typeof v==='object')return'{'+Object.entries(v).map(([k,v])=>'['+JSON.stringify(k)+']='+lua(v)).join(',')+'}';return JSON.stringify(v);}
const dst=path.join(root,'src/shared/GameData/FireParticleVectors.luau');fs.mkdirSync(path.dirname(dst),{recursive:true});fs.writeFileSync(dst,'-- GENERATED local-only original fire particle primitive references.\nreturn '+lua(cases)+'\n');
console.log('Exported',cases.length,'original puff/ember primitive cases.');
