// Export original fog colours locally; no source tables are committed.
// node tools/conversion/export_fog.cjs <install> [output root]
const fs=require('fs'),path=require('path'),vm=require('vm');
const install=path.resolve(process.argv[2]||''),root=path.resolve(process.argv[3]||path.join(__dirname,'../..'));
if(!process.argv[2])throw Error('usage: export_fog.cjs <install> [output root]');
const rel=path.relative(install,root);
if(!rel||(!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel)))throw Error('output must be outside original install');
const b=fs.readFileSync(path.join(install,'resources/app.asar'));
const header=JSON.parse(b.subarray(16,16+b.readUInt32LE(12))),entries=header.files.dist.files.assets.files;
const name=Object.keys(entries).find(n=>/^main-.*\.js$/.test(n)),entry=entries[name];
const at=8+b.readUInt32LE(4)+Number(entry.offset),s=b.subarray(at,at+entry.size).toString();
const start=s.indexOf('N0={rgb:');if(start<0)throw Error('fog table not found');
const first=s.indexOf('{',start);let depth=0,end=-1;
for(let i=first;i<s.length;i++){
 if(s[i]==='"'||s[i]==="'"){const q=s[i];while(++i<s.length&&s[i]!==q)if(s[i]==='\\')i++;}
 else if(s[i]==='{')depth++;else if(s[i]==='}'&&--depth===0){end=i+1;break;}
}
const original=vm.runInNewContext('('+s.slice(first,end)+')',{}, {timeout:1000});
if(!original.chart.plains||!original.seen||original.featherCells!==2.4)throw Error('unrecognized fog schema');
const data={rgb:original.rgb,alpha:original.alpha,chart:original.chart,seen:original.seen,featherCells:original.featherCells};
function lua(v){if(typeof v!=='object')return JSON.stringify(v);if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';return'{'+Object.entries(v).map(([k,x])=>'['+JSON.stringify(k)+']='+lua(x)).join(',')+'}';}
const file=path.join(root,'src/shared/GameData/FogLook.luau');fs.mkdirSync(path.dirname(file),{recursive:true});
fs.writeFileSync(file,'--!strict\n-- GENERATED local-only original fog look.\nreturn '+lua(data)+'\n');
console.log('Generated original terrain/explored fog look');
