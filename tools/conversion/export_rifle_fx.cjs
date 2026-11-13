// Extract rifle presentation settings from the owner's local install. Output stays git-ignored.
// Usage: node export_rifle_fx.cjs <install> [project root]
const fs=require('fs'),path=require('path'),vm=require('vm');
const install=process.argv[2],root=path.resolve(process.argv[3]||path.join(__dirname,'../..'));
if(!install)throw Error('usage: node export_rifle_fx.cjs <install> [project root]');
const relative=path.relative(path.resolve(install),root);
if(!relative||(!relative.startsWith('..'+path.sep)&&relative!=='..'&&!path.isAbsolute(relative)))throw Error('output must stay outside the original install');
const bytes=fs.readFileSync(path.join(install,'resources/app.asar')),header=JSON.parse(bytes.subarray(16,16+bytes.readUInt32LE(12))),entries=header.files.dist.files.assets.files;
function bundle(pattern){const names=Object.keys(entries).filter(n=>pattern.test(n));if(names.length!==1)throw Error('expected one bundle: '+pattern);const e=entries[names[0]],at=8+bytes.readUInt32LE(4)+Number(e.offset);return bytes.subarray(at,at+e.size).toString();}
const main=bundle(/^main-.*\.js$/),effects=bundle(/^effects-.*\.js$/);
function balanced(src,at){const start=src.indexOf('{',at);let depth=0;for(let i=start;i<src.length;i++){const c=src[i];if('"\'`'.includes(c)){const q=c;while(++i<src.length&&src[i]!==q)if(src[i]==='\\')i++;}else if(c==='{')depth++;else if(c==='}'&&--depth===0)return src.slice(start,i+1);}throw Error('unbalanced expression');}
function imported(alias){const imp=effects.slice(0,effects.indexOf('from"./main-')),key=new RegExp('([\\w$]+) as '+alias+'(?:,|})').exec(imp)?.[1],sym=key&&new RegExp('([\\w$]+) as '+key+'(?:,|})').exec(main.slice(main.lastIndexOf('export{')))?.[1];if(!sym)throw Error('missing import '+alias);const at=main.indexOf(sym+'={');if(at<0)throw Error('missing literal '+sym);return vm.runInNewContext('('+balanced(main,at)+')',{}, {timeout:1000});}
const men=imported('jt'),bullet=imported('Qt'),weapons=imported('Me'),art=imported('Go'),colors=imported('w'),motion=imported('C');
// Verify the current source paths still use the assumptions ported by RifleFire; fail closed on repacks.
if(!effects.includes('rifleBurst(t,e,s,o)')||!effects.includes('manFlash(t,e,s,o=!1)')||!effects.includes('tex:"px",x:t.x-t.ux*be(1)*.5')||!main.includes('proneBack:.57'))throw Error('unrecognized rifle effects');
const data={men:{muzzleH:men.muzzleH,aimSlack:men.aimSlack,shooters:men.shooters,stagger:men.stagger,jitter:men.jitter,flash:men.flash,core:men.core,follow:men.follow,wisp:men.wisp,brass:men.brass},flash:bullet.flash,haze:bullet.haze,rhythm:bullet.rhythm,rifle:{gap:weapons.rifle.gap,spread:weapons.rifle.spread},muzzle:{rifle:art.muzzle.rifle,leader:art.muzzle.leader,para:art.muzzle.para},colors:{fire:colors.fire,hot:colors.hot},grow:motion.grow,proneBack:.57};
if(data.rhythm.burst[1]>8||data.men.shooters>3||!data.muzzle.rifle.prone||data.haze.max>120)throw Error('rifle bounds changed; review port');
function lua(v){if(v===null)return'nil';if(typeof v!=='object')return JSON.stringify(v);if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';return'{'+Object.entries(v).map(([k,x])=>'['+JSON.stringify(k)+']='+lua(x)).join(',')+'}';}
const target=path.join(root,'src/shared/GameData/RifleFx.luau');fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,'-- Generated locally from your install; git-ignored.\nreturn '+lua(data)+'\n');
console.log('Generated private rifle settings; reuses the existing particle atlas.');
