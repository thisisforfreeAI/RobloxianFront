-- Run from the project root. This exports local map data, never original source code.
local fs=require("@lune/fs")
local serde=require("@lune/serde")
local Codec=require("../../src/shared/Maps/MapCodec")
local map=Codec.decode(require("../../src/shared/GameData/Maps/Saddle"))
local urban=table.create(map.width*map.height)
for i=0,map.width*map.height-1 do urban[i+1]=buffer.readu8(map.urban,i) end
if not fs.isDir("docs/private") then fs.writeDir("docs/private") end
fs.writeFile("docs/private/night-input_saddle.json",serde.encode("json",{
	width=map.width,height=map.height,urban=urban,roads=map.data.roads,
}))
