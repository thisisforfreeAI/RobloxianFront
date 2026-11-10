// Evaluate the original fortification layout against local match/map inputs. Outputs contain
// original-derived data and must remain in ignored directories. No original functions are copied.
// node export_forts.cjs <main bundle> <fort-input.json> <city> <private-output.json>
const fs=require('fs'),vm=require('vm'),zlib=require('zlib');
const [bundle,input,city,output]=process.argv.slice(2),s=fs.readFileSync(bundle,'utf8');
function object(name){const a=s.indexOf(name+'={');if(a<0)throw Error('missing '+name);const first=s.indexOf('{',a);let depth=0;
 for(let i=first;i<s.length;i++){if(s[i]==='"'||s[i]==="'"){const q=s[i];while(++i<s.length&&s[i]!==q)if(s[i]==='\\')i++;}
 else if(s[i]==='{')depth++;else if(s[i]==='}'&&--depth===0)return vm.runInNewContext('('+s.slice(first,i+1)+')',{}, {timeout:1000});}
 throw Error('unterminated table');}
const game=JSON.parse(fs.readFileSync(input,'utf8'));
const b=fs.readFileSync(city),len=b.readUInt32LE(4),header=JSON.parse(b.subarray(8,8+len));let at=8+len,cells;
for(const p of header.parts){const raw=zlib.inflateRawSync(b.subarray(at,at+p.packed));at+=p.packed;if(p.name==='cells')cells=raw;}
if(!cells||cells.length!==game.w*game.h)throw Error('city dimensions differ');
const context={Sv:object('Sv'),gtt:null,SS:new Map(),h$:new Map(),AS:new Map(),nl:{w:game.w,cells},pJt:new Set([0,1,10])};
vm.createContext(context);
const a=s.indexOf('function gJt('),end=s.indexOf('const h$=',a);if(a<0||end<a)throw Error('fort layout function not found');
vm.runInContext(s.slice(a,end),context,{timeout:1000});
const layouts=game.settlements.map(st=>context.gJt(game,st));
const sprites=Object.fromEntries(Object.entries(object('I1').buildings).filter(([key])=>key.startsWith('fort-')));
fs.writeFileSync(output,JSON.stringify({map:header.id,layouts,sprites,config:context.Sv}));
console.log('Exported original layouts:',layouts.length,'settlements,',layouts.reduce((n,a)=>n+a.length,0),'fort pieces');
