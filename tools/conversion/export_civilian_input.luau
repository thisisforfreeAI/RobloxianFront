-- Local map/match inputs; output remains private. Run from the project root with Lune.
local fs=require("@lune/fs")
local serde=require("@lune/serde")
local Codec=require("../../src/shared/Maps/MapCodec")
local Roads=require("../../src/shared/Simulation/Roads")
local map=Codec.decode(require("../../src/shared/GameData/Maps/Saddle"))
local rules=require("../../src/shared/GameData/RulesMatch") ::any
local settlements={}
for i,s in map.data.settlements do
	settlements[i]={id=i-1,x=math.floor(s.x)+.5,y=math.floor(s.y)+.5,kind=s.kind,radius=rules["settlements."..s.kind.."Radius"],garrison={}}
end
local road=table.create(map.width*map.height,0)
local lines={}
for _,r in map.data.roads do if r.rank>=1 then
	table.insert(lines,r.pts)
	for i=3,#r.pts-1,2 do
		for _,c in Roads.line(map.width,map.height,r.pts[i-2],r.pts[i-1],r.pts[i],r.pts[i+1]) do road[c+1]=1 end
	end
end end
if not fs.isDir("docs/private") then fs.writeDir("docs/private") end
fs.writeFile("docs/private/civilian-input_saddle.json",serde.encode("json",{
	w=map.width,h=map.height,settlements=settlements,roadLines=lines,road=road,
	criticalBelow=rules["settlements.criticalBelow"],damagedBelow=rules["settlements.damagedBelow"],
}))
