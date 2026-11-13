// Extract local sprite metadata. Output is private input for pack_structures.py.
// node export_structure_art.cjs <app.asar> <private.json>
// Requires @napi-rs/canvas (or set NODE_PATH). All captured art stays in local ignored outputs.
const fs=require('fs'),vm=require('vm');
const bytes=fs.readFileSync(process.argv[2]);
const header=JSON.parse(bytes.subarray(16,16+bytes.readUInt32LE(12)));
const entries=header.files.dist.files.assets.files;
const main=Object.keys(entries).find(name=>/^main-.*\.js$/.test(name));
if(!main)throw Error('Main bundle not found');
const item=entries[main],start=8+bytes.readUInt32LE(4)+Number(item.offset);
const source=bytes.subarray(start,start+item.size).toString();
function object(name,context={}){
 const at=source.indexOf(name+'={');if(at<0)throw Error('Missing '+name);
 const first=source.indexOf('{',at);let depth=0;
 for(let i=first;i<source.length;i++){
  if('"\'`'.includes(source[i])){const quote=source[i];while(++i<source.length&&source[i]!==quote)if(source[i]==='\\')i++;}
  else if(source[i]==='{')depth++;
  else if(source[i]==='}'&&--depth===0)return vm.runInNewContext('('+source.slice(first,i+1)+')',context,{timeout:1000});
 }
 throw Error('Unterminated '+name);
}
const atlas=object('I1'),coalition=object('eU'),republic=object('qht',{eU:coalition}),look=object('Ji',{k0:Math.PI*2});
const projection=object('$7'),shadowLook=object('o4');
projection.alpha=shadowLook.alpha;projection.nightFade=shadowLook.nightFade;
const damage=object('bl');damage.fire={spots:damage.fire.spots,defenceSpots:damage.fire.defenceSpots};
const dither=source.match(/gXt=(\[[\d,]+\])/);if(!dither)throw Error('Missing damage dither');damage.dither=JSON.parse(dither[1]);
const initial=source.match(/const n=e\.id\*([\d.]+)%k0;o=/);if(!initial)throw Error('Missing gun initial heading');
const gunMotion={holdSec:look.holdSec,slits:look.slits,initialStep:Number(initial[1]),sam:look.sam};
const artillery=object('R8');artillery.motion=true;
const site=object('Pa'),survey=object('Qk');
const preview=object('i2');site.preview={from:preview.from,fadePx:preview.fadePx,defenceShare:preview.defenceShare};
const order=source.match(/function foe\(e,t\).*?let n=\(e\+1\)\*(\d+).*?Math.imul\(n\^n>>>(\d+),(\d+)\)\+(\d+)>>>0/);
const lift=source.match(/function Tte\(e,t\).*?Math.min\(1,e\*([\d.]+)\)/);
const pieceAt=source.indexOf('const d=i2.pieces,f=d*d'),pieceDraw=source.slice(pieceAt,pieceAt+1000);
const fade=pieceDraw.match(/Math.min\(1,m\*([\d.]+)\)/);
if(!order||!lift||!fade||pieceAt<0||!Number.isInteger(preview.pieces)||preview.pieces<1||preview.pieces>8)throw Error('Changed construction-piece settings');
site.pieces={count:preview.pieces,scaffold:preview.scaffold,seed:Number(order[1]),shift:Number(order[2]),mul:Number(order[3]),add:Number(order[4]),liftRate:Number(lift[1]),fadeRate:Number(fade[1])};
const ui=object('Je'),detection=object('DS'),range=object('IV');
const structureAt=source.indexOf('drawStructures(t,o,n,s,a,r,i,l,c='),structureDraw=source.slice(structureAt,structureAt+4200);
const widthShare=structureDraw.match(/Math.round\(T\*([\d.]+)\)/),buildGap=structureDraw.match(/P\+T\/2\+(\d+),I,f.built/),hpGap=structureDraw.match(/P-T\/2-(\d+),I,Math.max/);
const barAt=source.indexOf('bar(t,o,n,s,a,r){'),bar=source.slice(barAt,barAt+260),barStyle=bar.match(/fillStyle="(rgba\([\d, .]+\))",t.fillRect\(o,n,s,(\d+)\)/);
if(structureAt<0||!widthShare||!buildGap||!hpGap||!barStyle)throw Error('Changed structure bar styles');
site.tokens={buildingAlpha:preview.buildingAlpha,neutral:preview.neutral,stale:object('tU'),text:ui.text,accent:ui.accent,secured:ui.secured,contested:ui.contested,
 bar:{max:preview.barMaxPx,widthShare:Number(widthShare[1]),buildGap:Number(buildGap[1]),hpGap:Number(hpGap[1]),back:barStyle[1],height:Number(barStyle[2])}};
const warning=structureDraw.match(/const D=Math.max\(([\d.]+),Math.round\(A\*([\d.]+)\)\);V==="damaged"&&this.badge\(t,"status-damaged",_\+T\*([\d.]+),P-T\*([\d.]+),D,Je.under\)/);
const disc=source.match(/badge\(t,o,n,s,a,r\)\{.*?t.arc\(n,s,a\*([\d.]+)/);
if(!warning||!disc||warning[3]!==warning[4])throw Error('Changed damaged-building marker');
site.tokens.status={minPx:Number(warning[1]),sizeShare:Number(warning[2]),offsetShare:Number(warning[3]),discShare:Number(disc[1]),plate:ui.plate,ink:ui.under};
site.ground=object('doe');
if(site.ground.from<preview.from+preview.fadePx)throw Error('Ground symbols now overlap the building LOD transition');
const shade=site.ground.shade.match(/rgba\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)/);
if(!shade||!/^#[\da-f]{6}$/i.test(site.ground.ink))throw Error('Changed ground symbol colours');
site.ground.shadeRgb=shade.slice(1,4).map(Number);site.ground.shadeAlpha=Number(shade[4]);site.ground.inkRgb=site.ground.ink.slice(1).match(/../g).map(v=>parseInt(v,16));
const screenStart=source.indexOf('previewScreen(t,o,n,s,a,r,i,l)'),screen=source.slice(screenStart,source.indexOf('const p=n.ghost.ok',screenStart));
const radarAlpha=[...screen.matchAll(/DS\.ink\}, ([\d.]+)/g)].map(m=>Number(m[1])),radarLine=screen.match(/setLineDash\((\[[\d,]+\])\),t.lineWidth=([\d.]+)/);
const backing=source.match(/sameKindRing\(t,o,n,s,a,r\)\{.*?t\.strokeStyle="rgba\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)"/);
const sameWidth=screen.match(/t\.lineWidth=([\d.]+)/);
if(screenStart<0||radarAlpha.length!==2||!radarLine||!backing||!sameWidth)throw Error('Changed coverage preview styles');
site.coverage={same:{...range,linePx:Number(sameWidth[1])},marker:object('voe'),token:object('tr'),detail:site.preview,
 own:ui.secured,other:ui.isolated,backing:{rgb:backing.slice(1,4).map(Number),alpha:Number(backing[4])},
 radar:{rgb:detection.ink.split(',').map(Number),lineAlpha:radarAlpha[0],fillAlpha:radarAlpha[1],dash:JSON.parse(radarLine[1]),linePx:Number(radarLine[2])}};
const yard=[...source.matchAll(/buildYardShare:([\d.]+)/g)];if(yard.length!==1)throw Error('Ambiguous construction yard share');
site.yardShare=Number(yard[0][1]);site.survey={ink:survey.string,alpha:survey.stringAlpha,dash:survey.stringDash,pegPx:survey.pegPx};
function gradientInks(name,next){const at=source.indexOf('function '+name+'('),end=source.indexOf('function '+next+'(',at);if(at<0||end<0)throw Error('Missing site gradient');return [...source.slice(at,end).matchAll(/rgba\((\d+),(\d+),(\d+),[01]\)/g)].map(m=>m.slice(1).map(Number));}
const laser=gradientInks('Hte','Tte'),done=gradientInks('Rte','Pte');if(laser.length!==3||done.length!==3)throw Error('Changed site gradient inks');
site.site.laserInks=laser;site.done.inks=done;
async function exportMetadata(){
 const {createCanvas,loadImage}=require('@napi-rs/canvas');
 const mapping=object('C4'),icons=object('bkt'),images={};
 const size=Number(source.match(/function GT\([^)]*n=(\d+)\)/)?.[1]);
 const stroke=Number(source.match(/const Uj=(\d+);function My/)?.[1]);
 const fill=source.slice(screenStart).match(/fill:"(rgba\([\d, .]+\))",border:p,symbol:p,outline:Je.rim/)?.[1];
 if(!size||!stroke||!fill)throw Error('Changed source building-token styles');
 // Keep the original token painter order, split into stable dark backing and tintable ink.
 // This permits any side/refusal colour without per-colour images in the client.
 for(const id of new Set(Object.values(mapping))){
  const icon=icons[id];if(!icon)throw Error('Missing building token '+id);
  const paths=icon.body.replace(/#D9D9D9/gi,'currentColor').match(/<path\b[^>]*\/>|<svg\b[\s\S]*<\/svg>/g);
  if(!paths||paths.length<2)throw Error('Changed building token layers '+id);
  const [border,back,...symbol]=paths;
  const outline=shape=>shape.replace(/\s(?:fill|stroke|stroke-width|fill-opacity)="[^"]*"/g,'').replace(/\/>$/,` fill="none" stroke="${ui.rim}" stroke-width="${stroke}" stroke-linejoin="round"/>`);
  const [x,y,w,h]=icon.viewBox.split(/\s+/).map(Number),pad=stroke/2;
  const box=[x-pad,y-pad,w+2*pad,h+2*pad].join(' ');
  const bodies={back:outline(back)+outline(border)+back.replace(/currentColor/g,fill).replace(/fill-opacity="[^"]*"/,'fill-opacity="1"'),ink:[border,...symbol].join('').replace(/currentColor/g,'#ffffff'),
   fill:back.replace(/currentColor/g,'#ffffff').replace(/fill-opacity="[^"]*"/,'fill-opacity="1"'),
   face:border.replace(/currentColor/g,ui.text)+symbol.join('').replace(/currentColor/g,'#ffffff'),ghost:symbol.join('').replace(/currentColor/g,'#ffffff')};
  const layers={frame:size};
  for(const [layer,body] of Object.entries(bodies)){
   const svg=`<svg xmlns="http://www.w3.org/2000/svg" viewBox="${layer==='ghost'?icon.viewBox:box}" width="${size}" height="${size}">${body}</svg>`;
   const image=await loadImage(Buffer.from(svg)),canvas=createCanvas(size,size);canvas.getContext('2d').drawImage(image,0,0,size,size);
   layers[layer]=canvas.toBuffer('image/png').toString('base64');
  }
  images[id]=layers;
 }
 const warningIcon=icons['status-damaged'];if(!warningIcon)throw Error('Missing damaged status icon');
 const svg=`<svg xmlns="http://www.w3.org/2000/svg" viewBox="${warningIcon.viewBox}" width="${size}" height="${size}">${warningIcon.body.replace(/#D9D9D9/gi,'currentColor').replace(/currentColor/g,'#ffffff')}</svg>`;
 const warningImage=await loadImage(Buffer.from(svg)),warningCanvas=createCanvas(size,size);warningCanvas.getContext('2d').drawImage(warningImage,0,0,size,size);
 const badges={mapping,images,status:{damaged:{frame:size,image:warningCanvas.toBuffer('image/png').toString('base64')}}};
 fs.writeFileSync(process.argv[3],JSON.stringify({atlas,positions:{coalition,republic},dish:look.dish,gun:look.gun,gunMotion,factory:look.factory,factoryFps:look.stepFps,artillery,site,shadow:projection,nightAlpha:look.nightAlpha,construction:survey,damage,badges}));
 console.log('Exported local structure metadata and',Object.keys(images).length,'original building tokens');
}
exportMetadata().catch(error=>{console.error(error.message);process.exitCode=1;});
