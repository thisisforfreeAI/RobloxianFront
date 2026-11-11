// Read source cloud settings and execute local source shader/class references. All outputs ignored.
// node export_clouds.cjs <install> [output root]
const fs=require('fs'),path=require('path'),vm=require('vm');
const {evaluator}=require('./shader_reference.cjs');
const install=path.resolve(process.argv[2]||''),root=path.resolve(process.argv[3]||path.join(__dirname,'../..'));
if(!process.argv[2])throw Error('usage: export_clouds.cjs <install> [output root]');
const rel=path.relative(install,root);if(!rel||(!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel)))throw Error('output must stay outside original install');
const bytes=fs.readFileSync(path.join(install,'resources/app.asar')),head=JSON.parse(bytes.subarray(16,16+bytes.readUInt32LE(12)));
const entries=head.files.dist.files.assets.files,entry=entries[Object.keys(entries).find(n=>/^main-.*\.js$/.test(n))],at=8+bytes.readUInt32LE(4)+Number(entry.offset);
const source=bytes.subarray(at,at+entry.size).toString();
function braces(start){if(start<0)throw Error('missing source declaration');let depth=0;for(let i=start;i<source.length;i++){
 if(source[i]==='"'||source[i]==="'"||source[i]==='`'){const q=source[i];while(++i<source.length&&source[i]!==q)if(source[i]==='\\')i++;}
 else if(source[i]==='{')depth++;else if(source[i]==='}'&&--depth===0)return source.slice(start,i+1);
}throw Error('unterminated source declaration');}
function object(name){const i=source.indexOf(name+'={');if(i<0)throw Error('missing source settings '+name);return vm.runInNewContext('('+braces(source.indexOf('{',i))+')');}
const Nn=object('Nn'),ZI=object('ZI'),f2=object('f2');
const config={scale:Nn.cloudScale,dx:Nn.cloudDriftX,dy:Nn.cloudDriftY,cover:Nn.cloudCover,step:Nn.cloudStep,
 body:Nn.cloudBody,color:Nn.cloudColor,parallax:Nn.cloudParallax,nightThin:ZI.nightThin,golden:ZI.golden,
 shadow:Nn.cloudShadow,shadowReach:Nn.cloudShadowReach,shadowMax:Nn.cloudShadowMax,hidePx:Nn.cloudFar.hidePx,showPx:Nn.cloudFar.showPx};
if(Object.values(config).some(v=>v===undefined))throw Error('cloud settings schema changed');
const first=source.indexOf('float hash21(vec2 p)'),last=source.indexOf('`,jdt=',first);
if(first<0||last<first)throw Error('source cloud shader missing');
const uniforms={uCloud:[config.scale,config.dx,config.dy,config.shadow],uCloudCut:[config.cover,config.step]};
const over=/vec2 over = uEye[^;]+;/.exec(source),opacity=/float a = cloudAt\([^;]+\* uBody;/.exec(source);
if(!over||!opacity)throw Error('source sky sampling expressions changed');
const shader=evaluator(source.slice(first,last)+'\nfloat sampleCloud(vec2 vCell){'+over[0]+opacity[0]+'return a;}',uniforms);
const classStart=source.indexOf('class hde');
function method(name){const found=source.indexOf('}'+name+'(',classStart),start=found+1,body=source.indexOf('{',start);if(found<0||start>classStart+10000)throw Error('source sky method missing');return source.slice(start,body)+braces(body);}
const q=source.indexOf('function QU('),qBody=source.indexOf('{',q);
const context={Nn,ZI,f2,no:{mix:0},bF:()=>'clear',xH:value=>value};vm.createContext(context);
vm.runInContext(source.slice(q,qBody)+braces(qBody)+';class Ref{'+method('setDay')+method('pushBody')+'};globalThis.Ref=Ref;globalThis.QU=QU;',context);
const cases=[];let thick=0;
for(let i=0;i<720;i++){
 const x=(i*37%997)-350+.37,y=(i*61%733)-200+.19,time=(i*13%1200)/2;
 const density=shader.call('cloudAtCell',[[Math.floor(x+time*config.dx),Math.floor(y+time*config.dy)]]);
 if(density>0)thick++;
 cases.push({x,y,time,density,noise:shader.call('vnoise',[[x/config.scale,y/config.scale]])});
}
const lights=[{night:0,golden:0,mul:[1,.95,.85],add:[0,.01,.02],color:[1,.93,.8],shadow:[0,.8]},
 {night:0,golden:1,mul:[.9,.6,.4],add:[.04,.02,.01],color:[1,.65,.3],shadow:[3,-2]},
 {night:.5,golden:0,mul:[.45,.5,.7],add:[.01,.02,.04],color:[.5,.6,.82],shadow:[1,1]},
 {night:1,golden:0,mul:[.22,.27,.4],add:[.01,.02,.04],color:[.5,.6,.82],shadow:[0,2]}];
const tones=[];
for(const light of lights)for(const pixels of [2,3,4.5,6,20]){
 const ref=new context.Ref();ref.mesh={};ref.frontsInView=0;ref.hazeN=0;ref.uniforms={uWx:[0,0,0,0]};ref.near=context.QU(pixels);ref.setDay(light);
 tones.push({light,pixels,alpha:ref.uniforms.uBody,color:ref.uniforms.uCloudColor});
}
function lua(v){if(Array.isArray(v))return'{'+v.map(lua).join(',')+'}';if(typeof v==='object')return'{'+Object.entries(v).map(([k,v])=>'['+JSON.stringify(k)+']='+lua(v)).join(',')+'}';return JSON.stringify(v);}
function write(rel,value){const out=path.join(root,rel);fs.mkdirSync(path.dirname(out),{recursive:true});fs.writeFileSync(out,'-- GENERATED local-only original cloud settings/reference values.\nreturn '+lua(value)+'\n');}
const cloudy=cases.find(v=>v.density>0),view={cx:cloudy.x,cy:cloudy.y,rx:28,ry:18,time:cloudy.time,cellPixels:10};
const pixels=[];
for(const light of lights){
 const ref=new context.Ref();ref.mesh={};ref.frontsInView=0;ref.hazeN=0;ref.uniforms={uWx:[0,0,0,0]};ref.near=context.QU(view.cellPixels);ref.setDay(light);
 Object.assign(uniforms,{uEye:[view.cx,view.cy],uParallax:config.parallax,uTime:view.time,uBody:ref.uniforms.uBody});
 const alpha=[];for(let y=0;y<7;y++)for(let x=0;x<11;x++)alpha.push(shader.call('sampleCloud',[[view.cx+((x+.5)/11-.5)*view.rx*2,view.cy+((y+.5)/7-.5)*view.ry*2]]));
 pixels.push({light,view,width:11,height:7,alpha,color:ref.uniforms.uCloudColor});
}
write('src/shared/GameData/CloudLook.luau',config);write('src/shared/GameData/CloudVectors.luau',{cases,tones,pixels});
console.log('Cloud settings,',cases.length,'shader cases ('+thick+' cloudy),',tones.length,'source colour/opacity cases');
