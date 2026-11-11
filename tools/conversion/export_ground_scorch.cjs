// Evaluate the installed game's burn-scar raster and fade/heal models. Outputs stay git-ignored.
// node tools/conversion/export_ground_scorch.cjs <install> [output root]
const fs=require('fs'),path=require('path'),vm=require('vm');
const install=path.resolve(process.argv[2]||''),root=path.resolve(process.argv[3]||path.join(__dirname,'../..'));
if(!process.argv[2])throw Error('usage: export_ground_scorch.cjs <install> [output root]');
const rel=path.relative(install,root);if(!rel||(!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel)))throw Error('output must be outside original install');
const bytes=fs.readFileSync(path.join(install,'resources/app.asar')),header=JSON.parse(bytes.subarray(16,16+bytes.readUInt32LE(12))),es=header.files.dist.files.assets.files;
function bundle(re){const e=es[Object.keys(es).find(n=>re.test(n))];if(!e)throw Error('missing bundle '+re);const at=8+bytes.readUInt32LE(4)+Number(e.offset);return bytes.subarray(at,at+e.size).toString();}
const source=bundle(/^main-.*\.js$/),effects=bundle(/^effects-.*\.js$/);
function block(start){let depth=0;for(let i=start;i<source.length;i++){
 if(['"',"'",'`'].includes(source[i])){const q=source[i];while(++i<source.length&&source[i]!==q)if(source[i]==='\\')i++;}
 else if(source[i]==='{')depth++;else if(source[i]==='}'&&--depth===0)return source.slice(start,i+1);
}throw Error('unclosed original block');}
function object(name){const at=source.indexOf(name+'={');if(at<0)throw Error('missing source object '+name);return block(source.indexOf('{',at));}
function fn(name){const at=source.indexOf('function '+name+'(');if(at<0)throw Error('missing source function '+name);const b=source.indexOf('{',at);return source.slice(at,b)+block(b);}
function array(name){const match=new RegExp('\\b'+name+'=(\\[[^;]+?\\])[,;]').exec(source);if(!match)throw Error('missing source array '+name);return match[1];}
const cx={E:(o,k,v)=>o[k]=v};vm.createContext(cx);
const classAt=source.indexOf('class ZDt{'),classBody=source.indexOf('{',classAt);
vm.runInContext('const Pr='+object('Pr')+',YLt='+array('YLt')+',jLt='+array('jLt')+',KLt='+array('KLt')+',oK='+object('oK')+',m3='+object('m3')+',As='+object('As')+',Xat='+object('Xat')+',eK='+object('eK')+',YY='+object('YY')+';'+
 'const '+source.slice(source.indexOf('zL=['),source.indexOf(';function JLt'))+';'+fn('To')+fn('JLt')+';const qDt=4e6,NDt=Math.max(1,m3.crater.throwTo,m3.nuke.ashTo,m3.burn.stretch);class O4t{cell(){}box(){}all(){}};const FDt=(g,c)=>g.towns.has(c),N4t=(g,c)=>g.quiet;'+
 source.slice(classAt,classBody)+block(classBody)+';globalThis.make=(w,h)=>new ZDt(w,h);globalThis.profile={burn:m3.burn,shapes:{crater:m3.crater,rubble:m3.rubble},palette:jLt.map((color,i)=>({color,keep:YLt[i]})),tones:Pr,settle:oK,keep:YLt[Pr.burnt],color:jLt[Pr.burnt],tone:Pr.burnt,darken:Xat.darken,fadeSec:Xat.fadeSec,heal:eK,towns:YY,wind:[As.windX,As.windY]};globalThis.weapons='+object('Uu')+';globalThis.wind=(x,y)=>{As.windX=x;As.windY=y};',cx);
// Reject changed source hook signatures instead of silently guessing crater/collapse behavior.
if(!effects.includes('onScorch,t,e,o.scorchSize,o.scorch,"crater"'))throw Error('changed source crater hook');
const rubble=/onScorch,t\.x,t\.y,([\d.]+)\*e,([\d.]+),"rubble"/.exec(effects);
const demo=/smokeLife:o\.smokeLife,scorch:([\d.]+),scorchSize:o\.scorchSize/.exec(effects);
const imp=effects.slice(0,effects.indexOf('from"./main-')),exp=source.slice(source.lastIndexOf('export{'));
const alias=/([\w$]+) as _o(?:,|})/.exec(imp)?.[1],symbol=alias&&new RegExp('([\\w$]+) as '+alias+'(?:,|})').exec(exp)?.[1];
if(!rubble||!demo||!symbol)throw Error('changed source collapse/demo hooks');
const demoSettings=vm.runInNewContext('('+object(symbol)+')');
cx.profile.impacts={weapons:Object.fromEntries(Object.entries(cx.weapons).map(([key,v])=>[key,{kind:'crater',radius:v.scorchSize,power:v.scorch}])),
 demo:{kind:'crater',radius:demoSettings.scorchSize,power:Number(demo[1])},
 razed:{kind:'rubble',radius:Number(rubble[1]),power:Number(rubble[2]),fromBlastSize:true}};
if(!Number.isFinite(cx.profile.impacts.demo.radius))throw Error('missing demo scorch size');
const scenes=[];
for(const wind of [[.85,.25],[-.3,.9],[0,0]])for(const center of [[10.5,8.5],[.5,.5],[19.5,15.5]]){
 cx.wind(...wind);const model=cx.make(20,16),impulses=[[...center,1.2,.9],[center[0]+.2,center[1]+.6,2.3,.7],[...center,1.2,.9]];
 const states=[];function snapshot(label){const rows=[];for(let c=0;c<320;c++)if(model.scars.scorch[c]>0)rows.push([c,model.scars.scorch[c],model.scars.settle[c],model.scars.tone[c]]);states.push({label,rows});}
 for(const p of impulses)model.scar(...p,'burn');snapshot('initial');
 for(const dt of [1,20,100,300]){model.wearScars(dt);snapshot('fade:'+dt);}
 model.heal({towns:new Set(Array.from({length:320},(_,c)=>c)),quiet:false},60);snapshot('busy town');
 model.heal({towns:new Set(Array.from({length:320},(_,c)=>c)),quiet:true},60);snapshot('quiet town');
 model.heal({towns:new Set(Array.from({length:320},(_,c)=>c)),quiet:true},300);snapshot('restored town');
 scenes.push({wind,impulses,states});
}
cx.wind(...cx.profile.wind);const impacts=[];
for(const kind of ['crater','rubble'])for(const center of [[10.5,8.5],[.5,.5],[19.5,15.5]])for(const radius of [0,1.3,3.7]){
 const model=cx.make(20,16),impulses=[[...center,radius,.8,kind],[center[0]+.8,center[1]-.5,2.2,.6,'burn'],[...center,radius,.4,kind]],states=[];
 function snapshot(label){const rows=[];for(let c=0;c<320;c++)if(model.scars.scorch[c]>0)rows.push([c,model.scars.scorch[c],model.scars.settle[c],model.scars.tone[c]]);states.push({label,rows});}
 for(const p of impulses){model.scar(...p);snapshot('impulse');}
 for(const dt of [20,200]){model.wearScars(dt);snapshot('fade:'+dt);}
 impacts.push({impulses,states});
}
function lua(v){if(v===null)return'nil';if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';if(typeof v==='object')return'{'+Object.entries(v).map(([k,v])=>'['+JSON.stringify(k)+']='+lua(v)).join(',')+'}';return JSON.stringify(v);}
function write(name,value){const dst=path.join(root,'src/shared/GameData',name+'.luau');fs.mkdirSync(path.dirname(dst),{recursive:true});fs.writeFileSync(dst,'-- GENERATED original ground-scorch settings/references. Local only, git-ignored.\nreturn '+lua(value)+'\n');}
vm.runInContext('const XY=new WeakMap;'+fn('F4t')+';globalThis.townCells=g=>Array.from(F4t(g));',cx);
const towns=[{x:5.2,y:4.6,radius:1.8},{x:7.4,y:5.4,radius:2.2}];
write('GroundScorchRules',cx.profile);write('GroundScorchVectors',{width:20,height:16,scenes,impacts,towns,townCells:cx.townCells({w:20,h:16,settlements:towns})});
console.log('Exported original ground-scorch settings, '+scenes.length+' burn/fade/heal scenes and '+impacts.length+' mixed crater/rubble scenes');
