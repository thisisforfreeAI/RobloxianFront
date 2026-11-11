// Read source collapse/burner requests from the local install. Generated data/references stay ignored.
// node tools/conversion/export_collapse_fx.cjs <install> [output root]
const fs=require('fs'),path=require('path'),vm=require('vm');
const install=path.resolve(process.argv[2]||''),root=path.resolve(process.argv[3]||path.join(__dirname,'../..'));
if(!process.argv[2])throw Error('usage: export_collapse_fx.cjs <install> [output root]');
const rel=path.relative(install,root);if(!rel||(!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel)))throw Error('output must be outside original install');
const bytes=fs.readFileSync(path.join(install,'resources/app.asar')),head=JSON.parse(bytes.subarray(16,16+bytes.readUInt32LE(12))),es=head.files.dist.files.assets.files;
function bundle(re){const names=Object.keys(es).filter(n=>re.test(n));if(names.length!==1)throw Error('missing unique bundle');const e=es[names[0]],a=8+bytes.readUInt32LE(4)+Number(e.offset);return bytes.subarray(a,a+e.size).toString();}
const main=bundle(/^main-.*\.js$/),fx=bundle(/^effects-.*\.js$/);
function block(s,a){if(a<0)throw Error('missing source block');let depth=0;for(let i=a;i<s.length;i++){
 if(['"',"'",'`'].includes(s[i])){const q=s[i];while(++i<s.length&&s[i]!==q)if(s[i]==='\\')i++;}
 else if(s[i]==='{')depth++;else if(s[i]==='}'&&--depth===0)return s.slice(a,i+1);
}throw Error('unclosed source block');}
function imported(name){const imports=fx.slice(0,fx.indexOf('from"./main-')),list=main.slice(main.lastIndexOf('export{'));
 const key=new RegExp('([\\w$]+) as '+name+'(?:,|})').exec(imports)?.[1],sym=key&&new RegExp('([\\w$]+) as '+key+'(?:,|})').exec(list)?.[1];
 const a=sym?main.indexOf(sym+'={'):-1;if(a<0)throw Error('missing original config '+name);return vm.runInNewContext('('+block(main,main.indexOf('{',a))+')');}
function method(name){const a=fx.indexOf(name+'{');if(a<0)throw Error('missing original '+name);return block(fx,a+name.length);}
function array(name){const m=new RegExp('\\b'+name+'=(\\[[^\\]]+\\])').exec(fx);if(!m)throw Error('missing source array '+name);return m[1];}
const colors=imported('w'),sparks=imported('N'),collapse=imported('Bs');
const cx={Math,w:colors,N:sparks,Bs:collapse,O:.5,Ke:0,Te:()=>0,T:{burn:{}},H:null,d:null};vm.createContext(cx);
vm.runInContext('const At='+array('At')+',Ge='+array('Ge')+';globalThis.profile={collapse:Bs,colors:w,embersPerSec:N.embersPerSec,textures:At,fireColors:Ge};globalThis.raze=function(t)'+method('razed(t)')+';globalThis.burner=function(t,e,s,o)'+method('burner(t,e,s,o)')+';',cx);
const cases=[];
for(const building of ['factory','hq'])for(const seed0 of [27,811]){
 let seed=seed0,time=0,commands=[],later=[],actor=null;
 const random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
 cx.d=(a,b)=>a+(b-a)*random();cx.H=a=>a[Math.min(a.length-1,Math.floor(random()*a.length))];
 const emit=(kind,p)=>commands.push({kind,p});
 const host={time:0,options:{},away:()=>false,hear(){},light(){},kick(){},hook(){},
  puff:(x,y,h,size,life,vx=0,vy=0,color=colors.smoke,small=false,ground=false,rise=1)=>emit('puff',{x,y,h,size,life,vx,vy,color,small,ground,rise}),
  spawn:p=>{if(p.tick){actor={...p};return p;}emit('spawn',p);return p;},
  embers:(x,y,h,count,spread)=>emit('embers',{x,y,h,count,spread}),
  after:(sec,fn)=>later.push({at:time+sec,fn}),burner:(...args)=>cx.burner(...args)};
 cx.raze.call(host,{building,x:7.5,y:9.5});
 const frames=[{time:0,commands}];commands=[];
 for(let tick=1;tick<=Math.ceil(actor.life/.05);tick++){
  time=tick*.05;host.time=time;const due=later;later=[];for(const task of due)if(task.at<=time+1e-9)task.fn();else later.push(task);
  const age=Math.min(time,actor.life),dt=Math.min(.05,Math.max(0,actor.life-(time-.05)));
  actor.tick(actor,dt,host);
  frames.push({time,age,dt,commands});commands=[];
 }
 cases.push({building,seed:seed0,life:actor.life,frames});
}
function lua(v){if(v===null)return'nil';if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';if(typeof v==='object')return'{'+Object.entries(v).map(([k,x])=>'['+JSON.stringify(k)+']='+lua(x)).join(',')+'}';return JSON.stringify(v);}
function write(name,value){const dest=path.join(root,'src/shared/GameData',name+'.luau');fs.mkdirSync(path.dirname(dest),{recursive:true});fs.writeFileSync(dest,'-- GENERATED original collapse data/references. Local only, git-ignored.\nreturn '+lua(value)+'\n');}
write('CollapseFx',cx.profile);write('CollapseVectors',cases);
console.log('Exported collapse profile and '+cases.length+' original particle-request sequences');
