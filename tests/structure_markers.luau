--!strict
return function(test:any,eq:any)
	local M=require('../src/shared/Presentation/StructureMarkers');local fs=require('@lune/fs');local luau=require('@lune/luau')
	test('marker state queries only owned visible facilities and demolition takes precedence',function()
		local e={alive=true,kind='factory',side=1};local calls=0;local reason=function() calls+=1;return 'damaged' end
		eq(M.sample(e,1,true,reason),1);eq(calls,1)
		eq(M.sample(e,2,true,reason),0);eq(M.sample(e,0,true,reason),0);eq(M.sample(e,1,false,reason),0);eq(calls,1)
		e.demolishAt=0;eq(M.sample(e,1,true,reason),2);eq(M.sample(e,2,true,reason),2);eq(calls,1)
		e.alive=false;eq(M.sample(e,1,true,reason),0)
	end)
	test('optional marker tail preserves all existing payload positions and dense remote arrays',function()
		local row={1,'factory',1,4,5,100,100,0,0,0,1,0,'coalition'};local copy=table.clone(row)
		eq(M.append(row,0),row);eq(#row,13);M.append(copy,1);eq(#copy,17);for i=14,16 do eq(copy[i],false) end;eq(copy[17],1)
		local a,b,c={1},{2},{3};row[14]=a;row[15]=b;row[16]=c;M.append(row,2);eq(row[14],a);eq(row[15],b);eq(row[16],c);eq(row[17],2)
	end)
	test('actual server view includes own warning and visible demolition but omits enemy and fogged operation',function()
		local source=fs.readFile('src/server/Match/MatchService.luau');local function entity(id,side,state,reason,demolish)
			return {id=id,kind='factory',cat='structure',side=side,state=state,reason=reason,alive=true,x=id,y=4,hp=20,maxHp=100,built=1,demolishAt=demolish}
		end
		local list={entity(1,1,'seen','damaged'),entity(2,2,'seen','damaged'),entity(3,2,'stale','damaged',0),entity(4,2,'hidden','damaged',0),entity(5,2,'seen','demolishing',0),entity(6,1,'seen','building'),entity(7,1,'seen','demolishing',0)}
		local viewer={update=function() end,structureState=function(e) return e.state end,runs=function() return {} end,lastSeen={[3]={kind='factory',side=2,x=3,y=4}}}
		local env=setmetatable({StructureMarkers=M,sim={list=list,armyOf=function() return 'coalition' end,inactiveReason=function(e) return e.reason end,time=0},viewers={[1]=viewer},factoryViews={},weaponViews={},artilleryViews={},FactoryMotion={snapshot=function() return nil end},GunMotion={supports=function() return false end,snapshot=function() return nil end},ArtilleryMotion={snapshot=function() return nil end},rules={data={}}},{__index=getfenv()})
		local a=assert(source:find('local function structureRow(',1,true));local b=assert(source:find('-- 0 none',a,true));env.structureRow=luau.load(source:sub(a,b-1)..'\nreturn structureRow',{environment=env})()
		a=assert(source:find('local function viewFor(',1,true));b=assert(source:find('-- vehicles destroyed',a,true));local view=luau.load(source:sub(a,b-1)..'\nreturn viewFor',{environment=env})()
		local _,rows=view(1);local byId={};for _,row in rows do byId[row[1]]=row end
		eq(byId[1][17],1);eq(#byId[1],17);eq(byId[2][17],nil);eq(byId[3][17],nil);eq(byId[3][12],1);eq(#byId[3],13);eq(byId[4],nil);eq(byId[5][17],2);eq(byId[6][17],nil);eq(byId[7][17],2)
	end)
end
