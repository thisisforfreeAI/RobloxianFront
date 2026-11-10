// Read the original road look tables locally; extracted data is never tracked.
// node tools/conversion/export_roads.cjs <install> [output project root]
const fs=require('fs'),path=require('path'),vm=require('vm');
const install=path.resolve(process.argv[2]||''),root=path.resolve(process.argv[3]||path.join(__dirname,'../..'));
if(!process.argv[2])throw Error('usage: export_roads.cjs <install> [output project root]');
const relative=path.relative(install,root);
if(!relative||(!relative.startsWith('..'+path.sep)&&relative!=='..'&&!path.isAbsolute(relative)))throw Error('output must be outside the install');
const b=fs.readFileSync(path.join(install,'resources/app.asar'));
const h=JSON.parse(b.subarray(16,16+b.readUInt32LE(12))),entries=h.files.dist.files.assets.files;
const name=Object.keys(entries).find(n=>/^main-.*\.js$/.test(n));
const e=entries[name],at=8+b.readUInt32LE(4)+Number(e.offset),s=b.subarray(at,at+e.size).toString();
function table(name){
 const start=s.indexOf(name+'={');if(start<0)throw Error('road table not found: '+name);
 const first=s.indexOf('{',start);let depth=0;
 for(let i=first;i<s.length;i++){
  if(s[i]==='"'||s[i]==="'"){const quote=s[i];while(++i<s.length&&s[i]!==quote)if(s[i]==='\\')i++;}
  else if(s[i]==='{')depth++;else if(s[i]==='}'&&--depth===0)return vm.runInNewContext('('+s.slice(first,i+1)+')',{}, {timeout:1000});
 }
 throw Error('unterminated road table');
}
const data={widths:table('ET'),look:table('Qr'),roads:table('me')};
if(data.widths.major.half!==.7||!data.look.major.dash||!data.roads.far)throw Error('unexpected road schema');
function lua(v){if(typeof v!=='object')return JSON.stringify(v);if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';return'{'+Object.entries(v).map(([k,x])=>'['+JSON.stringify(k)+']='+lua(x)).join(',')+'}';}
const out=path.join(root,'src/shared/GameData/RoadLook.luau');fs.mkdirSync(path.dirname(out),{recursive:true});
fs.writeFileSync(out,'--!strict\n-- GENERATED local-only road look data.\nreturn '+lua(data)+'\n');console.log('Generated local road look');
const json=path.join(root,'docs/private/road-look.json');fs.mkdirSync(path.dirname(json),{recursive:true});
fs.writeFileSync(json,JSON.stringify(data));
