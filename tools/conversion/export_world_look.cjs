// Read original world-lighting/territory look; output is local-only GameData.
const fs=require('fs'),path=require('path'),vm=require('vm');
const install=path.resolve(process.argv[2]||''),root=path.resolve(process.argv[3]||path.join(__dirname,'../..'));
if(!process.argv[2])throw Error('usage: export_world_look.cjs <install> [output root]');
const rel=path.relative(install,root);if(!rel||(!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel)))throw Error('output must stay outside install');
const b=fs.readFileSync(path.join(install,'resources/app.asar')),h=JSON.parse(b.subarray(16,16+b.readUInt32LE(12)));
const entries=h.files.dist.files.assets.files,name=Object.keys(entries).find(n=>/^main-.*\.js$/.test(n)),e=entries[name];
const at=8+b.readUInt32LE(4)+Number(e.offset),s=b.subarray(at,at+e.size).toString();
function object(start){let a=s.indexOf('{',start),depth=0;for(let i=a;i<s.length;i++){
 if(s[i]==='"'||s[i]==="'"){let q=s[i];while(++i<s.length&&s[i]!==q)if(s[i]==='\\')i++;}
 else if(s[i]==='{')depth++;else if(s[i]==='}'&&--depth===0)return vm.runInNewContext('('+s.slice(a,i+1)+')',{}, {timeout:1000});
}throw Error('unterminated source look');}
function number(name){const m=new RegExp('\\b'+name+'=([0-9.]+)').exec(s);if(!m)throw Error('look scalar missing: '+name);return Number(m[1]);}
const sky=object(s.indexOf('Nn={cloudShadow:'));
const groundWeather=object(s.indexOf('ground:{wetDark:'));
const front=object(s.indexOf('front:{forecastSec:'));
const data={wash:sky.wash,vignette:sky.vignette,vignetteFrom:sky.vignetteFrom,vignetteNight:sky.vignetteNight,
 cloud:{scale:sky.cloudScale,dx:sky.cloudDriftX,dy:sky.cloudDriftY,cover:sky.cloudCover,step:sky.cloudStep,shadow:sky.cloudShadow,hidePx:sky.cloudFar.hidePx,showPx:sky.cloudFar.showPx},
 weather:groundWeather,drying:{riseSec:front.crossSec*front.edgeShare,drySec:front.drySec},
 territory:{sigma:1.3,radius:3,line:1/3,rival:.2,none:.02,whole:.98,wash:number('Z4t'),border:number('W4t'),lift:number('U4t'),glow:number('uS'),band:number('jDt'),inner:number('KDt'),dashOn:2,dashPeriod:3}};
// Validate numerical literals against the source declarations rather than quietly accepting renamed settings.
if(!s.includes('am={sigma:1.3,radius:3,sides:4}')||!s.includes('A6={line:1/fn,rival:.2,none:.02,whole:.98}')||!s.includes('J$={on:2*fn,period:3*fn}'))throw Error('territory look schema changed');
const dp=s.indexOf('DP=[');if(dp<0)throw Error('source nation palettes missing');
let first=s.indexOf('[',dp),depth=0,last=-1;
for(let i=first;i<s.length;i++){
 if(s[i]==='"'||s[i]==="'"){const q=s[i];while(++i<s.length&&s[i]!==q)if(s[i]==='\\')i++;}
 else if(s[i]==='[')depth++;else if(s[i]===']'&&--depth===0){last=i+1;break;}
}
const palettes=vm.runInNewContext('('+s.slice(first,last)+')',{}, {timeout:1000});
data.palette=palettes.slice(0,4).map(p=>[1,3,5].map(at=>parseInt(p.fill.slice(at,at+2),16)/255));
function lua(v){if(typeof v!=='object')return JSON.stringify(v);if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';return'{'+Object.entries(v).map(([k,x])=>'['+JSON.stringify(k)+']='+lua(x)).join(',')+'}';}
const out=path.join(root,'src/shared/GameData/WorldLook.luau');fs.mkdirSync(path.dirname(out),{recursive:true});fs.writeFileSync(out,'--!strict\n-- GENERATED local-only source world look.\nreturn '+lua(data)+'\n');console.log('Generated source world look');
