// Run the installed game's procedural damaged-tree art and pose functions, without copying them.
// node export_tree_damage.cjs <install> <trees-top.png> <output directory>
// Output contains original art/reference data and MUST stay local/ignored. Requires @napi-rs/canvas.
const fs=require('fs'),path=require('path'),vm=require('vm'),zlib=require('zlib');
const {createCanvas,loadImage}=require('@napi-rs/canvas');
const [installArg,sheetArg,outArg,mapPath]=process.argv.slice(2);if(!outArg)throw Error('usage: export_tree_damage.cjs <install> <sheet.png> <ignored output dir> [map.json]');
const install=path.resolve(installArg),out=path.resolve(outArg),rel=path.relative(install,out);
if(!rel||(!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel)))throw Error('output must stay outside original install');
const bytes=fs.readFileSync(path.join(install,'resources/app.asar')),header=JSON.parse(bytes.subarray(16,16+bytes.readUInt32LE(12))),entries=header.files.dist.files.assets.files;
const entry=entries[Object.keys(entries).find(n=>/^main-.*\.js$/.test(n))];if(!entry)throw Error('missing installed main bundle');
const at=8+bytes.readUInt32LE(4)+Number(entry.offset),s=bytes.subarray(at,at+entry.size).toString();
function block(start){if(start<0)throw Error('missing declaration');let depth=0;for(let i=start;i<s.length;i++){
 if(['"',"'",'`'].includes(s[i])){const q=s[i];while(++i<s.length&&s[i]!==q)if(s[i]==='\\')i++;}
 else if(s[i]==='{')depth++;else if(s[i]==='}'&&--depth===0)return s.slice(start,i+1);
}throw Error('unterminated declaration');}
function object(name){const at=s.indexOf(name+'={');if(at<0)throw Error('missing settings '+name);return block(s.indexOf('{',at));}
function fn(name){const at=s.indexOf('function '+name+'(');if(at<0)throw Error('missing function '+name);const body=s.indexOf('{',at);return s.slice(at,body)+block(body);}
async function main(){
 const image=await loadImage(sheetArg);
 const charColors=JSON.parse(/\bQ\$=(\[[\d,]+\])/.exec(s)?.[1]||'null');
 const salt=Number(/\bYdt=(\d+)/.exec(s)?.[1]),scale=Number(/\bl0=([\d.]+)/.exec(s)?.[1]);
 const conifer=/T7e=([^;]+);function _7e/.exec(s)?.[1];
 if(!charColors||!Number.isFinite(salt)||!scale||!conifer)throw Error('missing source tree art declarations');
 class Rect{constructor(x,y,w,h){Object.assign(this,{x,y,width:w,height:h});}}
 class Source{constructor(o){Object.assign(this,o);}}
 class Texture{constructor(o){Object.assign(this,o);this.width=o.frame.width;this.height=o.frame.height;}}
 const ctx={_i:Rect,e9:Source,y1:Texture,document:{createElement:()=>createCanvas(1,1)},image};vm.createContext(ctx);
 vm.runInContext('const X2='+object('X2')+',wd='+object('wd')+',rE='+object('rE')+',Ydt='+salt+',T7e='+conifer+';'+fn('Ui')+fn('R7e')+fn('P7e')+fn('I7e')+fn('_7e')+
 ';globalThis.result=_7e({source:{resource:image,pixelWidth:image.width,pixelHeight:image.height}});globalThis.settings={shadow:rE,tiles:X2};',ctx,{timeout:10000});
 const result=ctx.result,frames={};for(const kind of ['standing','fallen','stump','burnt']){
  frames[kind]={};for(const [tile,texture] of Object.entries(result[kind])){const f=texture.frame;frames[kind][tile]=[f.x,f.y,f.width,f.height];}
 }
 fs.mkdirSync(out,{recursive:true});fs.writeFileSync(path.join(out,'tree-damage.png'),result.source.resource.toBuffer('image/png'));
 const dressAt=s.indexOf('dress(t){',5600000);if(dressAt<0)throw Error('missing original tree pose');
 const dress=block(s.indexOf('{',dressAt));
 const colors=charColors.map(c=>(-16777216|(c&255)<<16|c&65280|c>>16));
 const poseCtx={frames:result,colors};vm.createContext(poseCtx);
 vm.runInContext('const Jdt=-1,ist=colors,WS=Object.keys(frames.standing),rE='+object('rE')+';globalThis.pose=function(t)'+dress,poseCtx);
 const refs=[];for(const [i,tile] of Object.keys(result.standing).entries())for(const fate of [null,{kind:'burning',char:0},{kind:'burning',char:2},{kind:'fallen',rot:.71},{kind:'stump'},{kind:'burnt'}]){
  const leaf={},shadow={},mock={leaves:[leaf],shades:[shadow],tfate:[fate?1:0],handed:new Map([[0,{fate}]]),ttile:[i],frames:result,tscale:[1.25],pxAt:()=>137,pyAt:()=>211};
  poseCtx.pose.call(mock,0);refs.push({tile,fate,leaf:{x:leaf.x,y:leaf.y,anchorX:leaf.anchorX,anchorY:leaf.anchorY,rotation:leaf.rotation,color:leaf.color},shadow:{x:shadow.x,y:shadow.y}});
 }
 const keyExpr=/\bJS=([^,;]+)/.exec(s.slice(5600000))?.[1];if(!keyExpr)throw Error('missing source tree key stride');
 const keyStride=vm.runInNewContext(keyExpr);if(!Number.isSafeInteger(keyStride)||keyStride<=0)throw Error('invalid source tree key stride');
 let firebreaks;
 if(mapPath){const map=JSON.parse(fs.readFileSync(mapPath));for(const r of map.roads)r.pts=r.pts.data||r.pts;
  const rank=Number(/firebreakRank:(\d+)/.exec(object('$s'))?.[1]);if(!rank)throw Error('missing source firebreak rank');
  const mask=vm.runInNewContext(fn('G4')+';G4(map,rank)',{map,rank});
  firebreaks={width:map.width,height:map.height,rank,deflate:zlib.deflateRawSync(mask).toString('base64')};
 }
 fs.writeFileSync(path.join(out,'tree-damage.json'),JSON.stringify({scale,keyStride,shadow:ctx.settings.shadow,tiles:ctx.settings.tiles,frames,fallenAnchor:result.fallenAnchor,charColors,refs,firebreaks}));
 console.log('Exported original tree art:',Object.keys(frames.standing).length,'species;',refs.length,'original pose references;',result.source.resource.width+'x'+result.source.resource.height);
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
