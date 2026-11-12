// Extract local sprite metadata. Output is private input for pack_structures.py.
// node export_structure_art.cjs <app.asar> <private.json>
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
const damage=object('bl');damage.fire={spots:damage.fire.spots,defenceSpots:damage.fire.defenceSpots};
const dither=source.match(/gXt=(\[[\d,]+\])/);if(!dither)throw Error('Missing damage dither');damage.dither=JSON.parse(dither[1]);
const initial=source.match(/const n=e\.id\*([\d.]+)%k0;o=/);if(!initial)throw Error('Missing gun initial heading');
const gunMotion={holdSec:look.holdSec,slits:look.slits,initialStep:Number(initial[1]),sam:look.sam};
const artillery=object('R8');artillery.motion=true;
const site=object('Pa'),survey=object('Qk');
const yard=[...source.matchAll(/buildYardShare:([\d.]+)/g)];if(yard.length!==1)throw Error('Ambiguous construction yard share');
site.yardShare=Number(yard[0][1]);site.survey={ink:survey.string,alpha:survey.stringAlpha,dash:survey.stringDash,pegPx:survey.pegPx};
function gradientInks(name,next){const at=source.indexOf('function '+name+'('),end=source.indexOf('function '+next+'(',at);if(at<0||end<0)throw Error('Missing site gradient');return [...source.slice(at,end).matchAll(/rgba\((\d+),(\d+),(\d+),[01]\)/g)].map(m=>m.slice(1).map(Number));}
const laser=gradientInks('Hte','Tte'),done=gradientInks('Rte','Pte');if(laser.length!==3||done.length!==3)throw Error('Changed site gradient inks');
site.site.laserInks=laser;site.done.inks=done;
fs.writeFileSync(process.argv[3],JSON.stringify({atlas,positions:{coalition,republic},dish:look.dish,gun:look.gun,gunMotion,factory:look.factory,factoryFps:look.stepFps,artillery,site,shadow:object('$7'),nightAlpha:look.nightAlpha,construction:survey,damage}));
console.log('Exported local structure metadata');
