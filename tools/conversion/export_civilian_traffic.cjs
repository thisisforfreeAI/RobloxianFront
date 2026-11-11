// Runs local original procedural sprite baking and ambient layout. No source code is emitted.
// node export_civilian_traffic.cjs <install> <private input.json> <city> [output root]
const fs=require('fs'),path=require('path'),vm=require('vm'),zlib=require('zlib');
const [installArg,input,city,rootArg]=process.argv.slice(2);
if(!installArg||!input||!city)throw Error('usage: export_civilian_traffic.cjs <install> <input.json> <city> [output root]');
const install=path.resolve(installArg),root=path.resolve(rootArg||path.join(__dirname,'../..'));
const rel=path.relative(install,root);if(!rel||(!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel)))throw Error('output must stay outside original install');
const b=fs.readFileSync(path.join(install,'resources/app.asar')),header=JSON.parse(b.subarray(16,16+b.readUInt32LE(12)));
const entries=header.files.dist.files.assets.files,e=entries[Object.keys(entries).find(n=>/^main-.*\.js$/.test(n))],at=8+b.readUInt32LE(4)+Number(e.offset);
const s=b.subarray(at,at+e.size).toString();
function block(first){
 if(first<0)throw Error('missing original declaration');let depth=0;
 for(let i=first;i<s.length;i++){
  if(s[i]==='"'||s[i]==="'"||s[i]==='`'){const q=s[i];while(++i<s.length&&s[i]!==q)if(s[i]==='\\')i++;}
  else if(s[i]==='{')depth++;else if(s[i]==='}'&&--depth===0)return s.slice(first,i+1);
 }throw Error('unterminated declaration');
}
function fn(name){const a=s.indexOf('function '+name+'(');if(a<0)throw Error('missing original function '+name);return s.slice(a,s.indexOf('{',a))+block(s.indexOf('{',a));}
function object(name){const a=s.indexOf(name+'={');if(a<0)throw Error('missing original table '+name);return block(s.indexOf('{',a));}
const game=JSON.parse(fs.readFileSync(input,'utf8'));
const cb=fs.readFileSync(city);if(cb.subarray(0,4).toString()!=='WFCT')throw Error('invalid city');
const len=cb.readUInt32LE(4),head=JSON.parse(cb.subarray(8,8+len));let pos=8+len;const parts={};
for(const p of head.parts){parts[p.name]=zlib.inflateRawSync(cb.subarray(pos,pos+p.packed));pos+=p.packed;}
if(head.key.split(':')[1]!==game.w+'x'+game.h)throw Error('map/city dimensions differ');
const context={ImageData:class{constructor(width,height){this.width=width;this.height=height;this.data=new Uint8ClampedArray(width*height*4);}},E:(o,k,v)=>{o[k]=v},city:{...head,...parts},game};
vm.createContext(context);
const start=s.indexOf('const Kn='),end=s.indexOf('class Ftt',start);
if(start<0||end<start)throw Error('ambient sprite declarations missing');
const cls=s.indexOf('class fQt');if(cls<0)throw Error('ambient towns missing');
const fleeClass=s.indexOf('class oQt'),fleeLooks=s.indexOf('const eQt=');
if(fleeClass<0||fleeLooks<0)throw Error('fleeing civilian declarations missing');
const hashDecl=s.indexOf('const Do='),modelDecl=s.indexOf('const Bx=[');
if(hashDecl<0||modelDecl<0)throw Error('ambient seed/model declarations missing');
const source='const sn='+object('sn')+';'+s.slice(start,end)+fn('dQt')+fn('cQt')+fn('To')+
 s.slice(hashDecl,s.indexOf(';',hashDecl)+1)+
 'const eo={alpha:'+block(s.indexOf('{',s.indexOf('alpha:',s.indexOf('eo={'))))+'};'+
 fn('up')+fn('O8t')+fn('ZJt')+fn('mQt')+'const Bx='+s.slice(s.indexOf('[',modelDecl),s.indexOf(']',modelDecl)+1)+',X1={x:0,y:0,dx:1,dy:0};'+
 'const pQt=()=>[];'+fn('su')+
 s.slice(cls,s.indexOf('{',cls))+block(s.indexOf('{',cls))+
	 s.slice(fleeLooks,s.indexOf(';',fleeLooks)+1)+s.slice(fleeClass,s.indexOf('{',fleeClass))+block(s.indexOf('{',fleeClass))+
	 ';globalThis.original={sn,zc,u$,cQt,fQt,oQt,ZJt,To,Do};';
vm.runInContext(source,context,{timeout:10000});
const original=context.original;
const layout=new original.fQt();layout.build(game,{lines:original.ZJt(game)},context.city);
const fleeing=new original.oQt();fleeing.build(game,{lines:original.ZJt(game)});
const names=[...new Set(layout.towns.flatMap(t=>[...t.cars,...t.parked].map(c=>c.model)))];
const frame=Math.ceil(original.u$.carWhite.span*original.zc.px/2)*2,width=frame*original.zc.facings,height=frame*names.length;
if(width>1024||height>1024)throw Error('ambient sheet exceeds native image size');
const body=Buffer.alloc(width*height*4),shade=Buffer.alloc(body.length),rects={};
for(let n=0;n<names.length;n++){
 const baked=original.cQt(names[n],frame);if(baked.image.width!==width||baked.image.height!==frame)throw Error('sprite layout differs');
 Buffer.from(baked.image.data).copy(body,n*frame*width*4);Buffer.from(baked.shade.data).copy(shade,n*frame*width*4);rects[names[n]]=n*frame;
}
const data={width,height,frame,facings:original.zc.facings,px:original.zc.px,rects,
 config:{from:original.sn.from,full:original.sn.full,jumpSec:original.sn.jumpSec,peopleFrom:original.sn.peopleFrom,people:original.sn.people,fleeing:original.sn.fleeing,shadow:original.sn.shadow,towns:original.sn.towns,cars:original.sn.cars,criticalBelow:game.criticalBelow,damagedBelow:game.damagedBelow},
 lines:layout.lines.map(l=>({pts:Array.from(l.pts),cum:Array.from(l.cum),len:l.len})),
 towns:layout.towns.map((t,i)=>({id:i+1,seedId:i,kind:t.st.kind,x:t.x,y:t.y,radius:t.radius,cars:t.cars.map(c=>({...c,line:c.line+1})),parked:t.parked,
 walkers:t.walkers.map(w=>({...w,line:w.line<0?-1:w.line+1})),exits:(fleeing.places.find(p=>p.st.id===i)?.exits||[]).map(e=>({...e,line:e.line+1}))})),
 deflate:zlib.deflateRawSync(body).toString('base64'),shade:zlib.deflateRawSync(shade).toString('base64')};
function lua(v){if(v===null)return'nil';if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';if(typeof v==='object')return'{'+Object.entries(v).map(([k,v])=>'['+JSON.stringify(k)+']='+lua(v)).join(',')+'}';return JSON.stringify(v);}
const target=path.join(root,'src/client/DevAssets/OrigCivilianTraffic_saddle.luau');fs.mkdirSync(path.dirname(target),{recursive:true});
fs.writeFileSync(target,'--!strict\n-- GENERATED local-only original ambient car sprites and layout.\nreturn '+lua(data)+'\n');
// Original pedestrian poses, with an offline alpha-weighted half-size budget fallback.
function half(rgba,w,h){const out=Buffer.alloc(w/2*h/2*4);for(let y=0;y<h;y+=2)for(let x=0;x<w;x+=2){let a=0,r=0,g=0,b=0;for(let dy=0;dy<2;dy++)for(let dx=0;dx<2;dx++){const at=((y+dy)*w+x+dx)*4,v=rgba[at+3];a+=v;r+=rgba[at]*v;g+=rgba[at+1]*v;b+=rgba[at+2]*v;}const at=(y/2*w/2+x/2)*4;if(a){out[at]=Math.round(r/a);out[at+1]=Math.round(g/a);out[at+2]=Math.round(b/a);out[at+3]=Math.round(a/4);}}return out;}
const peopleNames=Object.keys(original.u$).filter(n=>/^person[A-C][0-2]$/.test(n));
const pf=Math.ceil(original.u$[peopleNames[0]].span*original.zc.px/2)*2,pw=pf*original.zc.facings,ph=pf*peopleNames.length;
const pb=Buffer.alloc(pw*ph*4),ps=Buffer.alloc(pb.length),pr={};
for(let i=0;i<peopleNames.length;i++){const baked=original.cQt(peopleNames[i],pf);Buffer.from(baked.image.data).copy(pb,i*pw*pf*4);Buffer.from(baked.shade.data).copy(ps,i*pw*pf*4);pr[peopleNames[i]]=i*pf;}
const peopleData={width:pw,height:ph,frame:pf,facings:original.zc.facings,px:original.zc.px,rects:pr,deflate:zlib.deflateRawSync(pb).toString('base64'),shade:zlib.deflateRawSync(ps).toString('base64')};
peopleData.half={width:pw/2,height:ph/2,frame:pf/2,facings:peopleData.facings,px:peopleData.px/2,rects:Object.fromEntries(Object.entries(pr).map(([k,v])=>[k,v/2])),deflate:zlib.deflateRawSync(half(pb,pw,ph)).toString('base64'),shade:zlib.deflateRawSync(half(ps,pw,ph)).toString('base64')};
fs.writeFileSync(path.join(root,'src/client/DevAssets/OrigCivilianPeople_saddle.luau'),'-- GENERATED local-only original ambient pedestrian poses.\nreturn '+lua(peopleData)+'\n');
// Independent motion reference from the original class, on an unobstructed synthetic road.
const road={pts:new Float32Array([0,0,40,0,40,20]),cum:new Float32Array([0,40,60]),len:60};
context.wc=()=>[0,0];context.$r=()=>true;context.pc=()=>true;
const references=[];
for(const scenario of ['normal','night','shock','blocked']){
 const actor=layout.carOn(0,4,[0,4,40,60],731),town={cars:[actor],st:null};const sample=new original.fQt();sample.lines=[road];
 const vectors=[];
 for(let step=0;step<=1800;step++){
  const draws=[],time=step/10,t={time,dt:step===0?0:.1,snap:step===0,share:1,k:20,tx:0,ty:0,tint:0,game:{w:100,h:100,road:new Uint8Array(10000).fill(1)},movers:scenario==='blocked'?[{x:actor.s+.9,y:0}]:[],sprites:{shadow(){},draw(...a){draws.push(a)}},c:null};
  sample.cars(t,town,scenario==='night'?.2:scenario==='shock'?0:1,scenario==='shock'&&step>0);
  if(step%15===0)vectors.push({time,s:actor.s,dir:actor.dir,alpha:actor.alpha,off:actor.off});
 }
 references.push({scenario,car:{...layout.carOn(0,4,[0,4,40,60],731),line:1},vectors});
}
const reference={hash:Array.from({length:12},(_,i)=>({id:i*37,channel:i,value:original.Do(i*37,i)})),road:{pts:Array.from(road.pts),cum:Array.from(road.cum),len:road.len},cases:references};
reference.people=[];
for(const mode of ['walk','stand','fade']){
 const initial={line:mode==='stand'?-1:0,s0:5,reach:3,side:.5,x:4,y:2,seed:.3,look:'B',alpha:0};
 const walker={...initial},sample=new original.fQt();sample.lines=[road];const vectors=[];
 for(let step=0;step<=600;step++){
  const time=step/10,draws=[];
  sample.people({time,dt:step===0?0:.1,snap:step===0,k:20,tx:0,ty:0,tint:0,sprites:{shadow(){},draw(...args){draws.push(args)}},c:null},{walkers:[walker]},mode==='fade'&&time>=5?0:1);
  if(step%5===0)vectors.push({time,alpha:walker.alpha,poses:draws.map(d=>({model:d[1],x:d[2]/20,y:d[3]/20,heading:d[5],alpha:d[7]??1}))});
 }
 reference.people.push({mode,walker:{...initial,line:initial.line<0?-1:initial.line+1},vectors});
}
reference.flee=[];
for(const mode of ['hit','fight','ruined']){
 const town={id:5,x:15,y:0,radius:3,kind:'town',lastHitAt:mode==='fight'?-99:10,integrity:100,destroyed:false};
 const sample=new original.oQt();sample.build({settlements:[town]},{lines:[road]});
 const units=new Map(mode==='fight'?[[1,{alive:true,x:15,y:0,firedAt:10,hitAt:-Infinity}]]:[]);
 const vectors=[];
 for(let step=0;step<=200;step++){
  const time=10+step/10,draws=[];if(mode==='ruined'&&step===50){town.integrity=0;town.destroyed=true;}
  sample.draw({time,snap:step===0,k:20,tx:0,ty:0,tint:0,fog:false,game:{units},sprites:{shadow(){},draw(...args){draws.push(args)}},c:null});
  if(step%5===0)vectors.push({time,poses:draws.map(d=>({model:d[1],x:d[2]/20,y:d[3]/20,heading:d[5],alpha:d[7]??1}))});
 }
 reference.flee.push({mode,seedId:5,x:15,y:0,radius:3,kind:'town',exits:sample.places[0].exits.map(e=>({...e,line:e.line+1})),vectors});
}
const refPath=path.join(root,'src/shared/GameData/CivilianVectors.luau');fs.mkdirSync(path.dirname(refPath),{recursive:true});fs.writeFileSync(refPath,'-- GENERATED private original reference vectors.\nreturn '+lua(reference)+'\n');
console.log('Original civilian traffic:',data.towns.length,'towns,',data.towns.reduce((n,t)=>n+t.cars.length,0),'moving cars,',data.towns.reduce((n,t)=>n+t.parked.length,0),'parked cars;',width+'x'+height,'shared sheets');
console.log('Original pedestrians:',data.towns.reduce((n,t)=>n+t.walkers.length,0),'town walkers;',pf+' px,',peopleNames.length,'poses,',fleeing.places.length,'evacuation sites');
