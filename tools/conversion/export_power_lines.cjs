// Evaluate original planner/geometry/drawing from the local install; emit ignored data only.
// node export_power_lines.cjs <install> [output root]
const fs=require('fs'),path=require('path'),vm=require('vm');
const install=path.resolve(process.argv[2]||''),root=path.resolve(process.argv[3]||path.join(__dirname,'../..'));
if(!process.argv[2])throw Error('usage: export_power_lines.cjs <install> [output root]');
const rel=path.relative(install,root);if(!rel||(!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel)))throw Error('output must stay outside original install');
const bytes=fs.readFileSync(path.join(install,'resources/app.asar')),head=JSON.parse(bytes.subarray(16,16+bytes.readUInt32LE(12))),entries=head.files.dist.files.assets.files;
function asset(pattern){const e=entries[Object.keys(entries).find(n=>pattern.test(n))];if(!e)throw Error('missing bundle');const at=8+bytes.readUInt32LE(4)+Number(e.offset);return bytes.subarray(at,at+e.size).toString();}
const s=asset(/^main-.*\.js$/);
function block(at){if(at<0)throw Error('missing source declaration');let depth=0;for(let i=at;i<s.length;i++){
 if(['"',"'",'`'].includes(s[i])){const q=s[i];while(++i<s.length&&s[i]!==q)if(s[i]==='\\')i++;}
 else if(s[i]==='{')depth++;else if(s[i]==='}'&&--depth===0)return s.slice(at,i+1);
}throw Error('unterminated declaration');}
function fn(name){const i=s.indexOf('function '+name+'(');if(i<0)throw Error('missing original function '+name);const at=s.indexOf('{',i);return s.slice(i,at)+block(at);}
function object(name){const i=s.indexOf(name+'={');if(i<0)throw Error('missing original settings '+name);return block(s.indexOf('{',i));}
function array(name){const i=s.indexOf(name+'=[');if(i<0)throw Error('missing original array '+name);const start=s.indexOf('[',i);let depth=0;for(let at=start;at<s.length;at++){
 if(['"',"'",'`'].includes(s[at])){const q=s[at];while(++at<s.length&&s[at]!==q)if(s[at]==='\\')at++;}
 else if(s[at]==='[')depth++;else if(s[at]===']'&&--depth===0)return s.slice(start,at+1);
}throw Error('unterminated source array');}
let response;const self={postMessage:value=>{response=value}};
vm.runInNewContext(asset(/^genWorker-.*\.js$/),{self,console,TextEncoder,TextDecoder,structuredClone});self.onmessage({data:{id:1,map:'saddle'}});
if(!response?.map)throw Error('map generation failed');const map=response.map;
const context={E:(o,k,v)=>{o[k]=v},map};vm.createContext(context);
const fps=Number(/\bOa=([0-9.]+)/.exec(s)?.[1]);if(!Number.isFinite(fps))throw Error('source effect clock missing');
const start=s.indexOf('const UT='),end=s.indexOf('const Yp=',start),cls=s.indexOf('class BJt'),cb=s.indexOf('{',cls);
// Only the power pass of the original procedural feature builder is applied to this designed map.
vm.runInContext('const Fgt='+array('Fgt')+';'+fn('ho')+fn('Ga')+fn('G4')+fn('To')+s.slice(start,end)+
 'const mi=1,Yp='+object('Yp')+',FCt=[["power",(e,t)=>{const o=ECt(e);if(o)t.power=o}]];'+fn('$Ct')+fn('BCt')+
 'const Aa='+object('Aa')+',OJt='+object('OJt')+',zy='+array('zy')+',Rc=Math.PI*2,Ptt=new WeakMap,Itt=new Map,FJt=/^#([0-9a-f]{6})$/i,Oa='+fps+';'+
 fn('vU')+fn('dr')+fn('Ix')+fn('Rtt')+fn('$Jt')+s.slice(cls,cb)+block(cb)+
 ';globalThis.original={Aa,OJt,vU,Rtt,To,BJt,plan:BCt(map,map.theme,map.seed,map.seed,map.settlements,map.rigs).power};',context,{timeout:30000});
const o=context.original,plan=map.features?.power||o.plan;if(!plan)throw Error('no viable power layout');
const geo=o.vU(plan),renderer=Object.create(o.BJt.prototype);
const frame=48,facings=16,px=o.Aa.texel.towerPerCell,rows=['steel','wood','feed'],width=frame*facings,height=frame*rows.length,rgba=Buffer.alloc(width*height*4);
function rgb(css){if(css[0]==='#'){const v=parseInt(css.slice(1),16);return[v>>16&255,v>>8&255,v&255];}throw Error('unexpected source day colour');}
for(let row=0;row<rows.length;row++)for(let face=0;face<facings;face++){
 const angle=face/facings*Math.PI*2,g={x:[0],y:[0],ax:[Math.cos(angle)],ay:[Math.sin(angle)]};
 const c={fillStyle:'#000000',fillRect(x,y,w,h){const color=rgb(this.fillStyle);for(let py=Math.max(0,Math.floor(y));py<Math.min(frame,Math.ceil(y+h));py++)for(let pz=Math.max(0,Math.floor(x));pz<Math.min(frame,Math.ceil(x+w));pz++){const at=((row*frame+py)*width+face*frame+pz)*4;rgba[at]=color[0];rgba[at+1]=color[1];rgba[at+2]=color[2];rgba[at+3]=255;}}};
 const project=value=>frame/2+value*px;
 if(row===0)renderer.pylon(c,g,0,0,1,0,project,project);else renderer.pole(c,g,0,0,1,0,project,project,row===2);
}
const nodes=Array.from(geo.x,(x,i)=>({id:i+1,x,y:geo.y[i],ax:geo.ax[i],ay:geo.ay[i],up:geo.up[i]+1,
 plant:i<geo.np,steel:i>=geo.np&&!!plan.nodes[i-geo.np].steel,feed:!!geo.feeds[i],phase:o.To(i,11)*Math.PI*2}));
const links=[];for(let i=geo.np;i<nodes.length;i++)if(nodes[i].up>0)links.push({a:i+1,b:nodes[i].up});
const config={look:o.Aa,wireLook:o.OJt,facings,frame,px,fps,plannerApplied:!map.features?.power};
const data={id:map.id,width,height,frame,facings,px,nodes,links,plantCount:geo.np,config};
function lua(v){if(v===null)return'nil';if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';if(typeof v==='object')return'{'+Object.entries(v).map(([k,v])=>'['+JSON.stringify(k)+']='+lua(v)).join(',')+'}';return JSON.stringify(v);}
function write(rel,value){const out=path.join(root,rel);fs.mkdirSync(path.dirname(out),{recursive:true});fs.writeFileSync(out,typeof value==='string'?value:JSON.stringify(value));}
write('docs/private/power-art_saddle.json',{...data,rgba:rgba.toString('base64'),plant:vm.runInNewContext('('+object('I1')+')').buildings.powerplant});
const vectors=[];
context.H0=()=>1;context.no={mix:0};
renderer.sync=()=>({plan,geo,shown:{down:new Uint8Array(plan.nodes.length),fellAt:new Float64Array(plan.nodes.length),arcAt:new Float64Array(plan.nodes.length),plants:plan.plants.map(()=>({owner:-1,ruined:false}))}});
renderer.tower=()=>true;renderer.marks=()=>{};renderer.live=new Uint8Array(nodes.length).fill(1);
for(const time of [0,1.2,5.5,40]){
 let paths=[],current,strokes=[];
 renderer.tiled={at(){},moveTo(x,y){current=[x,y];paths.push(current)},lineTo(x,y){current.push(x,y)},stroke(c){if(paths.length)strokes.push(paths);paths=[]}};
 const canvas={fillRect(){},getTransform(){return{a:1}}};
 renderer.drawSky(canvas,{game:{cfg:{intel:{fog:false},horde:{deadWorld:false}}},cam:{k:8},view:{x0:-1000,y0:-1000,x1:1000,y1:1000},sx:x=>x*8,sy:y=>y*8,now:time*1000,night:0},false);
 vectors.push({time,paths:strokes[0].map(points=>points.map(v=>v/8))});
}
const shadows=[];renderer.plant=()=>{};
for(const sun of [[0,0],[-.6,1.1],[2.2,-1]]){
 let paths=[],current,strokes=[];
 renderer.tiled={at(){},moveTo(x,y){current=[x,y];paths.push(current)},lineTo(x,y){current.push(x,y)},stroke(){if(paths.length)strokes.push(paths);paths=[]}};
 renderer.drawGround({}, {game:{cfg:{intel:{fog:false}}},cam:{k:8},view:{x0:-1000,y0:-1000,x1:1000,y1:1000},sx:x=>x*8,sy:y=>y*8,now:0,night:0,sun},false);
 shadows.push({sun,paths:strokes[0].map(points=>points.map(v=>v/8))});
}
const styles=[2.2,3,4.5,8,14,28].map(pixels=>({pixels,...o.Rtt(pixels)}));
write('src/shared/GameData/PowerLineVectors.luau','-- GENERATED local-only original power wire vectors.\nreturn '+lua({config,nodes,links,vectors,shadows,styles})+'\n');
console.log('Power layout:',plan.plants.length,'plants,',plan.nodes.length,'nodes,',links.length,'spans;',width+'x'+height,'node atlas; generated procedural layout:',!map.features?.power);
