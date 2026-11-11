// OWNER-REQUESTED APPROX: anchor ambient smoke to actual raised-roof art, not an urban-cell guess.
// Original .city material codes: 224+ roof levels; 224/225 are low surfaces/platforms.
const fs=require('fs'),zlib=require('zlib');
function readRoofMap(file,w,h){
 const bytes=fs.readFileSync(file);
 if(bytes.subarray(0,4).toString()!=='WFCT')throw Error('invalid city file');
 const length=bytes.readUInt32LE(4),head=JSON.parse(bytes.subarray(8,8+length));
 if(head.key.split(':')[1]!==w+'x'+h)throw Error('smoke map/city dimensions differ');
 const parts={};let at=8+length;
 for(const p of head.parts){
  if(p.name==='atlas'||p.name==='index'){
   parts[p.name]=zlib.inflateRawSync(bytes.subarray(at,at+p.packed));
   if(parts[p.name].length!==p.raw)throw Error('city part size differs');
  }
  at+=p.packed;
 }
 const size=head.size;
 if(!parts.atlas||!parts.index||parts.index.length!==w*h*4)throw Error('missing city roof data');
 return {size,width:w*size,height:h*size,code(x,y){
  if(x<0||y<0||x>=w*size||y>=h*size)return 0;
  const cell=(Math.floor(y/size)*w+Math.floor(x/size))*4;
  const tile=parts.index[cell]+256*parts.index[cell+1]+65536*parts.index[cell+2]-1;
  if(tile<0)return 0;
  const tx=tile%head.perRow*size+x%size,ty=Math.floor(tile/head.perRow)*size+y%size;
  return parts.atlas[(ty*head.atlasW+tx)*4+3]||0;
 }};
}
function interior(map,x,y){
 for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++)if(map.code(x+dx,y+dy)<226)return false;
 return true;
}
function anchorTowns(towns,map,game,options={}){
 // Port choices: at most three cells from the source site, one-texel roof margin, spaced emitters.
 const reach=options.reach??3,separation=options.separation??.75;
 const used=[],audit=[];
 const result=towns.map(town=>{
  const chimneys=[];
  for(const [index,site] of town.chimneys.entries()){
   let best=null,bestDistance=reach*reach;
   const x0=Math.max(0,Math.floor((site.x-reach)*map.size)),x1=Math.min(map.width-1,Math.ceil((site.x+reach)*map.size));
   const y0=Math.max(0,Math.floor((site.y-reach)*map.size)),y1=Math.min(map.height-1,Math.ceil((site.y+reach)*map.size));
   for(let py=y0;py<=y1;py++)for(let px=x0;px<=x1;px++){
    const x=(px+.5)/map.size,y=(py+.5)/map.size,distance=(x-site.x)**2+(y-site.y)**2;
    if(distance>bestDistance)continue;
    if(Math.abs(x-town.x)>town.radius+1||Math.abs(y-town.y)>town.radius+1)continue;
    const cell=Math.floor(y)*game.w+Math.floor(x);
    if(!game.urban[cell]||game.road[cell]||!interior(map,px,py))continue;
    if(used.some(p=>(x-p.x)**2+(y-p.y)**2<separation**2))continue;
    if(best&&distance===bestDistance)continue; // deterministic y/x tie break
    best={...site,x,y};bestDistance=distance;
   }
   audit.push({town:town.id,index:index+1,sourceX:site.x,sourceY:site.y,
    sourceOnRoof:interior(map,Math.floor(site.x*map.size),Math.floor(site.y*map.size)),
    anchor:best,shift:best?Math.sqrt(bestDistance):null});
   if(best){chimneys.push(best);used.push(best);}
  }
  return {...town,chimneys};
 });
 return {towns:result,audit};
}
module.exports={readRoofMap,interior,anchorTowns};
