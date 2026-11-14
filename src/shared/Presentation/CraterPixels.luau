--!strict
-- Original procedural bowl, lip, thrown earth, broken paving and stepped water painter.
local Hash=if script then require(script.Parent.Parent.Utilities.Hash)else require('../Utilities/Hash')
local Pixels={}
local TAU=math.pi*2
local function rgb(hex:string):{number}local n=assert(tonumber(hex:sub(2),16));return {bit32.extract(n,16,8),bit32.extract(n,8,8),bit32.extract(n,0,8)}end
local function shade(c:{number},k:number):{number}return {math.min(255,math.floor(c[1]*k+.5)),math.min(255,math.floor(c[2]*k+.5)),math.min(255,math.floor(c[3]*k+.5))}end
function Pixels.bounds(config:any,h:any):any
 local P=config.paint;local n=P.texelsPerCell;local reach=h.r*P.throwTo+.5
 local x,y=math.floor((h.x-reach)*n)/n,math.floor((h.y-reach)*n)/n
 local size=math.max(2,math.ceil((h.x+reach-x)*n))
 return {left=x,top=y,width=size,height=size,scale=n}
end
function Pixels.paint(config:any,h:any,checkpoint:((number)->())?,allowed:((number,number)->boolean)?):any
 local P,A=config.paint,config.paved;local box=Pixels.bounds(config,h);local n,size=box.scale,box.width
 assert(size<=256,'crater raster bounds exceeded')
 local out=buffer.create(size*size*4);local soil=rgb(h.ground);local bands={};for _,s in P.bands do table.insert(bands,shade(soil,s))end
 local road=if h.paved then rgb(h.paved)else nil;local slabs={};if road then for _,s in A.tilt do table.insert(slabs,shade(road,s))end end
 local edge=if road then shade(road,A.edgeDark)else nil;local crack=if road then shade(road,A.crackDark)else nil
 local cracks={};local seed=h.seed
 if road then for i=0,A.cracks-1 do table.insert(cracks,{at=(i+Hash.seed(seed*53+i,97)*.8)/A.cracks*TAU-math.pi,to=1+(P.throwTo-1)*(.45+.55*Hash.seed(seed*59+i,98)),bend=(Hash.seed(seed*61+i,99)-.5)*2*A.crackBend,turns=2+Hash.seed(seed*67+i,100)*4})end end
 local water,sheen,rim=rgb(P.water),rgb(P.waterSheen),rgb(P.waterRim);local lx,ly,lz=table.unpack(P.light)
 local step=math.floor(h.fill*P.steps+.5);local pool=h.r*P.pool*(step/P.steps)
 for y=0,size-1 do
  if checkpoint and y%8==0 then checkpoint(y)end
  for x=0,size-1 do
   local wx,wy=box.left+(x+.5)/n,box.top+(y+.5)/n
   if allowed and not allowed(wx,wy)then continue end
   local dx,dy=wx-h.x,wy-h.y;local d=math.sqrt(dx*dx+dy*dy);local a=math.atan2(dy,dx)
   local wobble=1+P.wobble*(Hash.seed(math.floor((a+math.pi)/TAU*24)+seed*97,60)-.5)*2
   local r=d/(h.r*wobble);local color=nil
   if r<1 then
    local slope=2*P.depth/(h.r*wobble);local nx,ny=slope*(dx/(h.r*wobble)),slope*(dy/(h.r*wobble))
    local norm=math.sqrt(nx*nx+ny*ny+1);local light=(-nx*lx-ny*ly+lz)/norm;local depth=1-r*r
    local tone=math.clamp(.55+.9*(light-.53)-.35*depth,0,1);color=bands[math.min(4,math.floor(tone*5))+1]
    local radial=d/wobble
    if pool>0 and radial<pool then
     local facing=-(dx*lx+dy*ly)/(math.sqrt(lx*lx+ly*ly)*(if d==0 then 1 else d));local share=radial/pool
     color=if radial>pool-1/n then rim elseif share>P.sheen[1]and share<P.sheen[2]and facing>P.sheenFacing then sheen else water
    elseif pool>0 and radial<pool+1/n then color=bands[1]
    elseif edge and r>A.edge then color=edge end
   elseif road and r<P.lip then
    local slab=(a+math.pi)/TAU*A.slabs+Hash.seed(seed*71,101);local index=math.floor(slab)
    color=if slab-index<A.slabGap then crack else slabs[math.floor(Hash.seed(seed*73+index%A.slabs,102)*#slabs)+1]
   elseif r<P.lip then
    local ux,uy=dx/(if d==0 then 1 else d),dy/(if d==0 then 1 else d);local facing=ux*lx+uy*ly;local t=(r-1)/(P.lip-1)
    color=bands[(if facing>.25 then 5 elseif facing>-.25 then (if t<.5 then 4 else 3)else 2)+1]
   elseif r<P.throwTo then
    local noise=Hash.seed(math.floor(wx*n)*7919+math.floor(wy*n),bit32.band(seed,255));local t=(r-P.lip)/(P.throwTo-P.lip)
    if noise<P.clods*(1-t)*2 then color=bands[(if noise<P.clods*.5 then 1 else 3)+1]end
    if road then
     local rubble=Hash.seed(math.floor(wx*n)*6151+math.floor(wy*n),bit32.band(seed+91,255))
     if rubble<A.rubble*(1-t)*2 then color=slabs[math.floor(rubble/A.rubble*37)%#slabs+1]end
     for _,c in cracks do
      if r>c.to then continue end
      local angle=a-c.at-c.bend*math.sin(r*c.turns);local delta=math.atan2(math.sin(angle),math.cos(angle))
      if math.abs(delta)*d*n<A.crackTexels then color=crack end
     end
    end
   end
   if color then local at=(y*size+x)*4;buffer.writeu8(out,at,color[1]);buffer.writeu8(out,at+1,color[2]);buffer.writeu8(out,at+2,color[3]);buffer.writeu8(out,at+3,255)end
  end
 end
 box.pixels=out;return box
end
return Pixels
