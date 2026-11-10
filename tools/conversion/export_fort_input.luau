local fs=require("@lune/fs")
local serde=require("@lune/serde")
-- Run from the project root: lune run tools/conversion/export_fort_input
-- Original map/match data remains in ignored GameData and docs/private.
local root="../../"
local Codec=require(root.."src/shared/Maps/MapCodec")
local Roads=require(root.."src/shared/Simulation/Roads")
local map=Codec.decode(require(root.."src/shared/GameData/Maps/Saddle"))
local rules=require(root.."src/shared/GameData/RulesMatch")
local roads=table.create(map.width*map.height,0)
for _,road in map.data.roads do for i=1,#road.pts-3,2 do
	for _,cell in Roads.line(map.width,map.height,road.pts[i],road.pts[i+1],road.pts[i+2],road.pts[i+3]) do roads[cell+1]=1 end
end end
local terrain,urban={},{}
for c=0,map.width*map.height-1 do terrain[c+1]=buffer.readu8(map.terrain,c);urban[c+1]=buffer.readu8(map.urban,c) end
local settlements={}
for i,st in map.data.settlements do table.insert(settlements,{id=i,kind=st.kind,x=math.floor(st.x)+.5,y=math.floor(st.y)+.5,radius=rules["settlements."..st.kind.."Radius"]}) end
if not fs.isDir("docs/private") then fs.writeDir("docs/private") end
fs.writeFile("docs/private/fort-input_saddle.json",serde.encode("json",{w=map.width,h=map.height,terrain=terrain,urban=urban,road=roads,settlements=settlements}))
