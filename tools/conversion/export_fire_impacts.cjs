// Trace source effect hooks and water/bridge selection. Generated settings/references stay ignored.
// node tools/conversion/export_fire_impacts.cjs <install> [output root]
const fs=require('fs'),path=require('path'),vm=require('vm');
const install=path.resolve(process.argv[2]||''),root=path.resolve(process.argv[3]||path.join(__dirname,'../..'));
if(!process.argv[2])throw Error('usage: export_fire_impacts.cjs <install> [output root]');
const rel=path.relative(install,root);if(!rel||(!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel)))throw Error('output must be outside original install');
const bytes=fs.readFileSync(path.join(install,'resources/app.asar')),head=JSON.parse(bytes.subarray(16,16+bytes.readUInt32LE(12))),entries=head.files.dist.files.assets.files;
function bundle(regex){const e=entries[Object.keys(entries).find(n=>regex.test(n))];if(!e)throw Error('missing source bundle');const at=8+bytes.readUInt32LE(4)+Number(e.offset);return bytes.subarray(at,at+e.size).toString();}
const main=bundle(/^main-.*\.js$/),effects=bundle(/^effects-.*\.js$/);
function block(s,start){if(start<0)throw Error('missing source block');let depth=0;for(let i=start;i<s.length;i++){
 if(['"',"'",'`'].includes(s[i])){const q=s[i];while(++i<s.length&&s[i]!==q)if(s[i]==='\\')i++;}
 else if(s[i]==='{')depth++;else if(s[i]==='}'&&--depth===0)return s.slice(start,i+1);
}throw Error('unclosed original block');}
function method(name){const at=effects.indexOf(name+'{');if(at<0)throw Error('missing effect '+name);return block(effects,at+name.length);}
function scalar(importName,key){
 const imports=effects.slice(0,effects.indexOf('from"./main-')),exports=main.slice(main.lastIndexOf('export{'));
 const alias=new RegExp('([\\w$]+) as '+importName+'(?:,|})').exec(imports)?.[1];
 const symbol=alias&&new RegExp('([\\w$]+) as '+alias+'(?:,|})').exec(exports)?.[1];
 const start=symbol?main.indexOf(symbol+'={'):-1;if(start<0)throw Error('missing original config '+importName);
 const obj=block(main,main.indexOf('{',start));const value=Number(new RegExp('\\b'+key+':([\\d.]+)').exec(obj)?.[1]);if(!Number.isFinite(value))throw Error('missing original scalar '+key);return value;
}
const razed=method('razed(t)'),demo=method('demolition(t,e)');
const razedSize=Number(/onBlast,t\.x,t\.y,([\d.]+)\*e,"razed"/.exec(razed)?.[1]);
const demoWeapon=/this\.impact\(t,e,\{[^}]*blast:s\.demoBlast[^}]*\},!0,"([^"]+)"\)/.exec(demo)?.[1];
const mineWeapon=/else if\([\w$]+\.mine\)[\w$]+\.play\(\{kind:"hit",weapon:"([^"]+)"/.exec(main)?.[1];
const waterStart=main.indexOf('function be('),waterBody=block(main,main.indexOf('{',waterStart));
const water=[...waterBody.matchAll(/==="([^"]+)"/g)].map(m=>m[1]);
const terrain=JSON.parse(/\bds=(\[[^\]]+\])/.exec(main)?.[1]||'null');
if(!razedSize||!demoWeapon||!mineWeapon||water.length!==3||!terrain||!waterBody.includes('!Pt.road['))throw Error('changed original fire hook schema');
const config={razedSize,hqScale:scalar('Bs','hqScale'),demoSize:scalar('at','demoBlast'),demoWeapon,mineWeapon,water,
 pops:{count:scalar('_o','pops'),reach:scalar('_o','popReach'),from:scalar('_o','popFrom'),to:scalar('_o','popTo')}};
const radius=/l=d\(([\d.]+),([\d.]+)\)\*o.popReach/.exec(demo);
config.pops.weapon=/o\.popTo\),\(\)=>this\.impact\([^}]+\},!1,"([^"]+)"\)\)/.exec(demo)?.[1];
if(!radius||!config.pops.weapon)throw Error('changed original demolition pop shape');
config.pops.radius=[Number(radius[1]),Number(radius[2])];
const zero=new Proxy({},{get:()=>0}),ctx={Math,d:(a,b)=>a,Bs:{hqScale:config.hqScale},w:zero,T:{burn:zero},at:{...zero,demoBlast:config.demoSize},_o:zero,
 it:{demolition:0,flash:{size:[0,0]}},ce:zero,G:{missile:{},shell:{}}};vm.createContext(ctx);
vm.runInContext('globalThis.raze=function(t)'+razed+';globalThis.demo=function(t,e)'+demo+';',ctx);
const references=[];
for(const building of ['hq','factory']){
 const requests=[],blast={};const host={hear(){},puff(){},spawn(){},burner(){},after(){},hook:(fn,x,y,size,weapon)=>{if(fn===blast)requests.push({x,y,size,weapon});},options:{onBlast:blast},kick(){}};
 ctx.raze.call(host,{building,x:7.5,y:9.5});references.push({kind:'razed',building,requests});
}
const requests=[];ctx.demo.call({still:true,wet:()=>false,spawn(){},light(){},nvPop(){},after(){},shock(){},kick(){},sparks(){},impact:(x,y,p,_big,weapon)=>requests.push({x,y,size:p.blast,weapon})},7.5,9.5);
references.push({kind:'demo',requests});
// Run the original delayed-pop loop, retaining a deterministic test stream only for those pops.
// Other effect details remain zero-cost stubs; only its actual impact callbacks are recorded.
let seed=713,draws=[];ctx.d=(a,b)=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;const r=seed/4294967296;draws.push(r);return a+(b-a)*r;};
let beforePops=0;const popConfig={pops:config.pops.count,popReach:config.pops.reach,popFrom:config.pops.from,popTo:config.pops.to};
ctx._o=new Proxy(popConfig,{get:(target,key)=>{if(key==='pops'&&beforePops===0)beforePops=draws.length;return target[key]??0;}});
const pending=[],pops=[];let after=0;
ctx.demo.call({still:true,wet:()=>false,spawn(){},light(){},nvPop(){},after:(at,fn)=>pending.push({at,fn}),shock(){},kick(){},sparks(){},impact:(x,y,_p,_big,weapon)=>{if(after>0)pops.push({at:after,x,y,weapon});}},7.5,9.5);
for(const task of pending){after=task.at;task.fn();}
const popReferences={draws:draws.slice(beforePops),requests:pops};
const m={w:2,h:2,road:new Uint8Array(4),terrain:new Uint8Array(4)};
Object.assign(ctx,{he:{value:m},ds:terrain});vm.runInContext('globalThis.wet=function(Q,ut)'+waterBody,ctx);
const surfaces=[];for(const name of [...water,'plains'])for(const road of [0,1]){m.terrain[0]=terrain.indexOf(name);m.road[0]=road;surfaces.push({name,road:!!road,wet:ctx.wet(.5,.5)});}
function lua(v){if(v===null)return'nil';if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';if(typeof v==='object')return'{'+Object.entries(v).map(([k,v])=>'['+JSON.stringify(k)+']='+lua(v)).join(',')+'}';return JSON.stringify(v);}
function write(name,value){const dst=path.join(root,'src/shared/GameData',name+'.luau');fs.mkdirSync(path.dirname(dst),{recursive:true});fs.writeFileSync(dst,'-- GENERATED original fire-impact settings/references. Local only, git-ignored.\nreturn '+lua(value)+'\n');}
write('FireImpactRules',config);write('FireImpactVectors',{references,surfaces,pops:popReferences});
console.log('Exported original fire-impact settings, '+references.length+' hook cases, '+surfaces.length+' water/bridge cases and '+pops.length+' delayed pops');
