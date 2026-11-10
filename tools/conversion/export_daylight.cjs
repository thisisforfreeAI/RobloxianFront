// Read-only extraction of the game's active skirmish daylight settings and reference vectors.
// node tools/conversion/export_daylight.cjs <install> [output project root]
// Data/vectors go under git-ignored GameData. No original functions are written to the repository.
const fs=require('fs'),path=require('path'),vm=require('vm');
const install=path.resolve(process.argv[2]||''),root=path.resolve(process.argv[3]||path.join(__dirname,'../..'));
if(!process.argv[2])throw Error('usage: node export_daylight.cjs <install> [output project root]');
const rel=path.relative(install,root);
if(!rel||(!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel)))throw Error('output must stay outside original install');
const b=fs.readFileSync(path.join(install,'resources/app.asar'));
const header=JSON.parse(b.subarray(16,16+b.readUInt32LE(12))),entries=header.files.dist.files.assets.files;
const names=Object.keys(entries).filter(n=>/^main-.*\.js$/.test(n));if(names.length!==1)throw Error('expected one main bundle');
const entry=entries[names[0]],at=8+b.readUInt32LE(4)+Number(entry.offset),s=b.subarray(at,at+entry.size).toString();
function balanced(at){const start=s.indexOf('{',at);let depth=0;for(let i=start;i<s.length;i++){const c=s[i];
 if(c==='"'||c==="'"||c==='`'){const q=c;while(++i<s.length&&s[i]!==q)if(s[i]==='\\')i++;}
 else if(c==='{')depth++;else if(c==='}'&&--depth===0)return s.slice(start,i+1);
}throw Error('unbalanced expression');}
function literal(pattern){const m=pattern.exec(s);if(!m)throw Error('literal not found: '+pattern);return vm.runInNewContext('('+balanced(m.index)+')',{}, {timeout:1000});}
function fn(name){const at=s.indexOf('function '+name+'(');if(at<0)throw Error('daylight function not found: '+name);return s.slice(at,s.indexOf('{',at))+balanced(at);}
const clock=literal(/\{lengthSec:\d+,startPhase:[^,]+,sunUp:/);
const style=literal(/\{keys:\[\{at:0,mul:\[\.8,/);
const look=literal(/\{ground:\{clumpPasses:/);
const flags=literal(/\{ground:!0,scatter:/);
const beforeDawn=literal(/\{roadGlow:[^,]+,lampHalo:/).beforeDawn;
const transition=literal(/sK=\{/),shadow=literal(/\{maxReach:[^,]+,nightFade:/);
if(!style.goldenSpan||!look.dusk||!look.night||!beforeDawn)throw Error('unrecognized daylight tables');
const keys=style.keys.map((key,i)=>{
 let value=i===style.keys.length-1?{...key,...beforeDawn}:{...key};
 if(flags.dusk&&key.at===.56)value={...value,...look.dusk.golden};
 if(flags.dusk&&key.at===.62)value={...value,...look.dusk.sunset};
 if(flags.night&&(key.at===.74||key.at===.93))value={...value,...look.night.key};
 return value;
});
const config={clock,transition,style:{...style,keys},shadow,sunGolden:flags.dusk?look.dusk.sunGolden:style.sunGolden,nightGround:look.night};
// Evaluate the source functions themselves for independent numerical regression vectors.
const context={ii:clock,g3:style,Ss:look,m1:flags,sK:transition,U6:'clear',Mqt:[keys,keys,keys,keys],tg:{},kqt:{},wF:{}};
vm.createContext(context);
vm.runInContext(fn('PA')+';const pJ=PA;'+fn('Oh')+';'+fn('Sqt')+';'+fn('xH')+';this.sample=xH;',context,{timeout:1000});
const phases=[0,.03,.06,.08,.16,.25,.31,.46,.56,.62,.66,.67,.70,.74,.8,.93,.97,.999999,1,-.001,1.31];
const vectors=phases.map(phase=>({phase,...context.sample(phase)}));
function lua(v){if(v===null)return'nil';if(typeof v!=='object')return JSON.stringify(v);if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';return'{'+Object.entries(v).map(([k,x])=>'['+JSON.stringify(k)+']='+lua(x)).join(',')+'}';}
for(const [name,data] of [['Daylight',config],['DaylightVectors',vectors]]){const target=path.join(root,'src/shared/GameData/'+name+'.luau');fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,'-- Generated from your local install; git-ignored.\nreturn '+lua(data)+'\n');}
console.log('Generated private active daylight configuration and '+vectors.length+' reference phases from the game.');
