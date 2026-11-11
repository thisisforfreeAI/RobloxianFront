// Evaluate the installed game's fire models; generated coefficients/reference states stay ignored.
// node tools/conversion/export_fire_rules.cjs <install> [output root]
const fs=require('fs'),path=require('path'),vm=require('vm');
const install=path.resolve(process.argv[2]||''),root=path.resolve(process.argv[3]||path.join(__dirname,'../..'));
if(!process.argv[2])throw Error('usage: export_fire_rules.cjs <install> [output root]');
const rel=path.relative(install,root);if(!rel||(!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel)))throw Error('output must stay outside original install');
const bytes=fs.readFileSync(path.join(install,'resources/app.asar')),head=JSON.parse(bytes.subarray(16,16+bytes.readUInt32LE(12))),entries=head.files.dist.files.assets.files;
const e=entries[Object.keys(entries).find(n=>/^main-.*\.js$/.test(n))];if(!e)throw Error('missing main bundle');
const at=8+bytes.readUInt32LE(4)+Number(e.offset),s=bytes.subarray(at,at+e.size).toString();
function block(start){if(start<0)throw Error('missing declaration');let depth=0;for(let i=start;i<s.length;i++){
 if(['"',"'",'`'].includes(s[i])){const q=s[i];while(++i<s.length&&s[i]!==q)if(s[i]==='\\')i++;}
 else if(s[i]==='{')depth++;else if(s[i]==='}'&&--depth===0)return s.slice(start,i+1);
}throw Error('unterminated source');}
function fn(name){const i=s.indexOf('function '+name+'(');if(i<0)throw Error('missing function '+name);const j=s.indexOf('{',i);return s.slice(i,j)+block(j);}
function object(name){const i=s.indexOf(name+'={');if(i<0)throw Error('missing settings '+name);return block(s.indexOf('{',i));}
function klass(name){const i=s.indexOf('class '+name+'{');if(i<0)throw Error('missing class '+name);const j=s.indexOf('{',i);return s.slice(i,j)+block(j);}
const context={E:(o,k,v)=>{o[k]=v}};vm.createContext(context);
const terrainNames=JSON.parse(/\bds=(\[[^\]]+\])/.exec(s)?.[1]||'null');if(!terrainNames)throw Error('missing terrain names');
const roofFrom=Number(/alpha:\{[^}]*roofFrom:(\d+)/.exec(object('eo'))?.[1]),tileSize=Number(/tile:(\d+)/.exec(object('eo'))?.[1]);
if(!Number.isFinite(roofFrom)||!tileSize)throw Error('missing roof geometry settings');
const charColors=JSON.parse(/Q\$=(\[[\d,]+\])/.exec(s)?.[1]||'null');
const drynessSalt=Number(/Phe=(\d+)/.exec(s)?.[1]);if(!charColors||!Number.isFinite(drynessSalt))throw Error('missing tree char/dryness declarations');
vm.runInContext('const zv='+object('zv')+',Yat='+object('Yat')+',As='+object('As')+',$s='+object('$s')+',Ws='+object('Ws')+',Uu='+object('Uu')+';'+
 'const ds='+JSON.stringify(terrainNames)+',Phe='+drynessSalt+',Q$='+JSON.stringify(charColors)+',Oc=(a,b,t)=>a+(b-a)*t,C1=(a,b)=>a+Math.random()*(b-a);'+fn('Ui')+fn('Jc')+klass('Ihe')+
 ';globalThis.original={forest:$s,houses:Ws,motion:As,Ui,Ihe,Uu};',context,{timeout:10000});
const marks=/\bQE=(\d+),kh=(\d+)/.exec(s);if(!marks)throw Error('missing house mark constants');
const charSalts=/\bEhe=(\d+),Dhe=(\d+)/.exec(s),topLevel=Number(/topLevel:(\d+)/.exec(object('eo'))?.[1]);if(!charSalts||!Number.isFinite(topLevel))throw Error('missing char declarations');
vm.runInContext('const Ehe='+charSalts[1]+',Dhe='+charSalts[2]+',QE='+marks[1]+',kh='+marks[2]+',eo={tile:'+tileSize+',topLevel:'+topLevel+',alpha:{roofFrom:'+roofFrom+'}},ec=(a,b)=>a+Math.random()*(b-a);'+fn('To')+fn('w2')+fn('m2')+klass('Ohe')+';original.Ohe=Ohe;',context,{timeout:10000});
const o=context.original;
const len=Math.hypot(o.motion.windX,o.motion.windY)||1;
const settings={forest:o.forest,houses:o.houses,wind:{x:o.motion.windX/len,y:o.motion.windY/len},drynessSalt,charStages:charColors.length,treeChar:charColors,tileSize,roofFrom,charSalts:{char:Number(charSalts[1]),tone:Number(charSalts[2])},weaponBlast:Object.fromEntries(Object.entries(o.Uu).map(([k,v])=>[k,v.blast]))};
const trees=[];for(let y=0;y<8;y++)for(let x=0;x<12;x++)trees.push({key:trees.length,x:5.2+x*.55,y:5.2+y*.55,size:.2+((x+y)%5)*.12,cell:Math.floor(5.2+y*.55)*32+Math.floor(5.2+x*.55),standing:true});
const cases=[];
for(const mode of ['dry','rain','firebreak','gap']){
 let seed=811;const math=Object.create(Math);let draws=0;
 math.random=()=>{draws++;seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};context.Math=math;
 const localTrees=structuredClone(trees),byKey=new Map(localTrees.map(t=>[t.key,t])),fated=new Map;
 const decor={fated,get fateCount(){return fated.size;},tree:k=>byKey.get(k),
  setFate(t,f){t.fate=f;fated.set(t.key,f);},clearFate(t){delete t.fate;fated.delete(t.key);},
  forNear(x,y,r,fn){for(const t of localTrees)if(Math.hypot(t.x-x,t.y-y)<=r)fn(t);},
  fuelAt(cell){return mode!=='gap'&&localTrees.some(t=>t.cell===cell&&t.standing&&(!t.fate||t.fate.kind==='burning'));}};
 const scars=[];const fire=new o.Ihe(decor,{},(...a)=>scars.push(a),null),barrier=new Uint8Array(32*24);
 if(mode==='firebreak')for(let y=0;y<24;y++)barrier[y*32+7]=1;
 fire.firebreaks=()=>barrier;fire.rain=()=>mode==='rain'?.8:0;
 fire.ignite(localTrees[38]);fire.ignite(localTrees[44]);
 const states=[];for(let tick=1;tick<=6400;tick++){
  fire.time+=o.forest.tickSec;fire.smoulder(o.forest.tickSec);fire.burnDown(o.forest.tickSec);fire.spread({w:32,h:24,terrain:new Uint8Array(32*24).fill(3)});fire.heal();
  if([1,16,40,80,160,320,1600,3600,6400].includes(tick))states.push({time:fire.time,draws,burns:fire.burns.map(b=>({key:b.key,age:b.age,life:b.life,char:b.char,looked:b.looked})),fates:[...fated].map(([key,fate])=>({key,...fate})),scarred:[...fire.scarred]});
 }
 cases.push({mode,seed:811,states});
}
// Original terrain-name lookup is consulted by the spread/firebreak test.
function lua(v){if(v===null)return'nil';if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';if(typeof v==='object')return'{'+Object.entries(v).map(([k,v])=>'['+JSON.stringify(k)+']='+lua(v)).join(',')+'}';return JSON.stringify(v);}
function write(rel,value){const dst=path.join(root,rel);fs.mkdirSync(path.dirname(dst),{recursive:true});fs.writeFileSync(dst,'-- GENERATED local-only original fire configuration/reference states.\nreturn '+lua(value)+'\n');}
const hashes=Array.from({length:64},(_,i)=>({x:i*177-511,y:o.Ui(i*177-511,drynessSalt)}));
write('src/shared/GameData/FireRules.luau',settings);write('src/shared/GameData/ForestFireVectors.luau',{settings,trees,cases,hashes});
console.log('Exported forest/house fire settings and',cases.length,'original forest trajectories;',cases.reduce((n,c)=>n+c.states.length,0),'state checkpoints.');
const width=6,height=4,pw=width*tileSize,ph=height*tileSize,roof=new Uint8Array(pw*ph);
for(let y=0;y<3;y++)for(let x=0;x<5;x++)for(let dy=0;dy<8;dy++)for(let dx=0;dx<8;dx++)roof[(5+y*13+dy)*pw+5+x*13+dx]=1;
const houseCases=[];
for(const mode of ['dry','rain']){
 let seed=191,draws=0;const math=Object.create(Math);math.random=()=>{draws++;seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};context.Math=math;
 const index=new Uint8Array(width*height*4),atlas=new Uint8Array(pw*ph*4);
 for(let i=0;i<width*height;i++)index[i*4]=i+1;
 for(let i=0;i<roof.length;i++)atlas[i*4+3]=roof[i]?roofFrom:0;
 const city={size:tileSize,atlasW:pw,atlasH:ph,perRow:width,count:width*height,index,atlas,cells:new Uint8Array(width*height).fill(1)};
 const fire=new o.Ohe({},()=>{},()=>{});fire.w=width;fire.h=height;fire.noFire=new Uint8Array(width*height);fire.setCity(city);
 fire.charTo=(h,stage)=>{h.stage=stage;};fire.rain=()=>mode==='rain'?.8:0;
 fire.ignite(7,7,0);fire.ignite(33,20,0);
 const states=[];
 for(let tick=1;tick<=400;tick++){
  fire.time+=o.houses.tickSec;fire.burnDown(o.houses.tickSec);fire.spread();
  if([1,20,40,80,160,320,400].includes(tick))states.push({time:fire.time,draws,burnt:fire.burntPx,
   houses:fire.houses.map(h=>({px:Array.from(h.px),x:h.x,y:h.y,r:h.r,cell:h.cell,age:h.age,life:h.life,gen:h.gen,stage:h.stage,looked:h.looked})),
   shells:fire.shells.map(h=>({px:Array.from(h.px),x:h.x,y:h.y,cell:h.cell,at:h.at})),scarred:[...fire.scarred]});
 }
 houseCases.push({mode,seed:191,states});
}
write('src/shared/GameData/HouseFireVectors.luau',{settings,width,height,roof:Array.from(roof),cases:houseCases});
console.log('Exported',houseCases.length,'original house-fire trajectories. Roof marks/char geometry remain separate from rendering.');
const forestBlasts=[],houseBlasts=[];
for(const weapon of [...Object.keys(settings.forest.blast),'wreck','razed'])for(let initial=1;initial<=12;initial++){
 let seed=initial,draws=0;const math=Object.create(Math);math.random=()=>{draws++;seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};context.Math=math;
 const localTrees=structuredClone(trees),fated=new Map;
 const decor={setFate(t,f){t.fate=f;fated.set(t.key,f);},forNear(x,y,r,fn){for(const t of localTrees){const d=Math.hypot(t.x-x,t.y-y);if(d<=r)fn(t,d);}}};
 const fire=new o.Ihe(decor,{},()=>{},null);fire.onScreen=()=>false;
 const size=(weapon==='blast'?settings.forest.blastSize:(settings.weaponBlast[weapon]||3))*1.15;
 fire.blast(8,7,size,weapon);
 forestBlasts.push({weapon,seed:initial,size,draws,burns:fire.burns.map(b=>({key:b.key,life:b.life})),fates:[...fated].map(([key,fate])=>({key,...fate})),hot:fire.hot});
 seed=initial;draws=0;
 const index=new Uint8Array(width*height*4),atlas=new Uint8Array(pw*ph*4);
 for(let i=0;i<width*height;i++)index[i*4]=i+1;for(let i=0;i<roof.length;i++)atlas[i*4+3]=roof[i]?roofFrom:0;
 const house=new o.Ohe({},()=>{},()=>{});house.w=width;house.h=height;house.noFire=new Uint8Array(width*height);
 house.setCity({size:tileSize,atlasW:pw,atlasH:ph,perRow:width,count:width*height,index,atlas,cells:new Uint8Array(width*height).fill(1)});
 house.charTo=(h,stage)=>{h.stage=stage;};house.blast(8/tileSize,8/tileSize,size,weapon);
 houseBlasts.push({weapon,seed:initial,size,draws,houses:house.houses.map(h=>({px:Array.from(h.px),life:h.life}))});
}
write('src/shared/GameData/FireBlastVectors.luau',{forest:forestBlasts,houses:houseBlasts});
console.log('Exported',forestBlasts.length,'forest and',houseBlasts.length,'house weapon-blast cases.');
const pixels=[];
for(let i=0;i<64;i++)for(const edge of [false,true])for(const stage of [1,2,3]){
 const side=tileSize,px=1+i%12,py=1+Math.floor(i/12)%12,p=py*side+px,original=[(i*31)%256,(i*47)%256,(i*71)%256,roofFrom+(i%8)*2];
 const atlas=new Uint8Array(side*side*4);for(let j=0;j<side*side;j++)atlas.set([original[0],original[1],original[2],edge?0:original[3]],j*4);atlas.set(original,p*4);
 const fire=new o.Ohe({},()=>{},()=>{});fire.w=1;fire.h=1;fire.setCity({size:side,atlasW:side,atlasH:side,perRow:1,count:1,index:Uint8Array.from([1,0,0,0]),atlas,cells:new Uint8Array(1).fill(1)});fire.keep(0);fire.char(p,stage);
 pixels.push({id:p,original,stage,edge,result:Array.from(atlas.subarray(p*4,p*4+4))});
}
write('src/shared/GameData/FirePixelVectors.luau',pixels);console.log('Exported',pixels.length,'original house char/ruin pixel cases.');
const textures=JSON.parse(/\bPM=(\[[^\]]+\])/.exec(s)?.[1]||'null'),houseTextures=JSON.parse(/\bAst=(\[[^\]]+\])/.exec(s)?.[1]||'null');
if(!textures||JSON.stringify(textures)!==JSON.stringify(houseTextures))throw Error('changed fire texture names');
vm.runInContext('const h1='+object('h1')+',U0='+object('U0')+',no={mix:0},iE='+object('iE')+',PM='+JSON.stringify(textures)+',Ast=PM,Sst=[h1.fire,h1.hot,h1.ember],Vhe=Sst,Hst=(a,b,t)=>a+(b-a)*t;'+fn('AH')+fn('$U')+
 ';globalThis.fxProfile={forest:$s.look,houses:Ws.look,colors:Sst,nightColors:U0.flames,nightFrom:U0.flameFrom,smoke:h1.smoke,forestEmbersFrom:iE.showPx,tileSize:'+tileSize+',textures:PM};globalThis.setFxMix=v=>{no.mix=v};',context,{timeout:10000});
const fxTrees=[{key:1,x:2,y:2,cell:1,size:.4,age:0,life:32,flameAcc:.98,smokeAcc:.99,emberAcc:.99},{key:2,x:3,y:2,cell:2,size:.7,age:12,life:32,flameAcc:.97,smokeAcc:.99,emberAcc:.99},
 {key:3,x:4,y:2,cell:3,size:.5,age:29,life:32,flameAcc:.98,smokeAcc:.99,emberAcc:.99},{key:4,x:100,y:2,cell:4,size:.5,age:12,life:32,flameAcc:.98,smokeAcc:.99,emberAcc:.99},{key:5,x:4,y:3,cell:-1,size:.5,age:12,life:32,flameAcc:.98,smokeAcc:.99,emberAcc:.99}];
const fxHouses=[{x:2,y:3,cell:6,r:.3,px:[65,66,129,130,-1],age:0,life:40,flameAcc:.98,smokeAcc:.99,emberAcc:.99},
 {x:3,y:3,cell:7,r:.6,px:Array.from({length:130},(_,i)=>200+i),age:20,life:40,flameAcc:.98,smokeAcc:.99,emberAcc:.99},{x:4,y:3,cell:8,r:.4,px:[600,601,664,665],age:37,life:40,flameAcc:.98,smokeAcc:.99,emberAcc:.99},
 {x:100,y:3,cell:9,r:.4,px:[600,601],age:10,life:40,flameAcc:.98,smokeAcc:.99,emberAcc:.99},{x:4,y:4,cell:-1,r:.4,px:[600,601],age:10,life:40,flameAcc:.98,smokeAcc:.99,emberAcc:.99}];
const fxCases=[];
for(const dt of [0,.016,.15,1])for(const zoom of [4,8,16,32])for(const mix of [0,1]){
 let seed=73,draws=0;const math=Object.create(Math);math.random=()=>{draws++;seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};context.Math=math;context.setFxMix(mix);
 const commands=[],fx={spawn:p=>commands.push({kind:'spawn',p}),puff:(x,y,h,size,life,vx,vy,color,small,ground,rise)=>commands.push({kind:'puff',p:{x,y,h,size,life,vx,vy,color,small,ground,rise}}),embers:(x,y,h,count,spread)=>commands.push({kind:'embers',p:{x,y,h,count,spread}})};
 const trees=structuredClone(fxTrees),houses=structuredClone(fxHouses),forest=new o.Ihe({},fx,()=>{},null),house=new o.Ohe(fx,()=>{},()=>{});
 forest.view.scale=house.view.scale=zoom;forest.onScreen=house.onScreen=x=>x<50;forest.sees=house.sees=(_g,cell)=>cell>=0;
 forest.burns=trees;house.houses=houses;house.city={size:tileSize};house.placeOf=p=>{if(p<0)return false;house.gx=p%64;house.gy=Math.floor(p/64);return true;};
 forest.draw({},dt);house.draw({},dt);fxCases.push({dt,zoom,mix,seed:73,draws,commands,treeAcc:trees.map(a=>[a.flameAcc,a.smokeAcc,a.emberAcc]),houseAcc:houses.map(a=>[a.flameAcc,a.smokeAcc,a.emberAcc])});
}
write('src/shared/GameData/FireEffectsRules.luau',context.fxProfile);write('src/shared/GameData/FireEffectsVectors.luau',{trees:fxTrees,houses:fxHouses,cases:fxCases});
console.log('Exported',fxCases.length,'original flame/smoke/ember emission frames.');
vm.runInContext('const $4t=(game,cell)=>game.townAt(cell);'+fn('B4t'),context,{timeout:10000});
const rebuildCases=[];
for(const mode of ['quiet','recent','nearby','lone']){
 const town={id:1,integrity:30,maxIntegrity:100,lastHitAt:-100},game={time:0,cfg:{settlements:{rebuild:{quietSec:20,fullSec:200}}},townAt:cell=>mode==='lone'||cell===4?null:town};
 const fire=new o.Ohe({},()=>{},()=>{});fire.shells=[1,2,3,4].map(id=>({id,cell:id,x:id,y:2,at:0,px:[id],tiles:[]}));
 fire.houses=mode==='nearby'?[{x:2,y:2}]:[];
 const raised=[];fire.raise=shell=>raised.push({id:shell.id,at:fire.time});
 const states=[];
 for(let time=1;time<=400;time++){
  fire.time=game.time=time;if(mode==='recent'&&time===15)town.lastHitAt=15;if(mode==='nearby'&&time===50)fire.houses=[];
  fire.rebuildShells(game);
  if([1,20,35,50,80,100,299,300,400].includes(time))states.push({time,remaining:fire.shells.map(h=>h.id),nextUp:[...fire.nextUp],raised:structuredClone(raised)});
 }
 rebuildCases.push({mode,states});
}
write('src/shared/GameData/HouseRebuildVectors.luau',rebuildCases);console.log('Exported',rebuildCases.length,'original house reconstruction trajectories.');
