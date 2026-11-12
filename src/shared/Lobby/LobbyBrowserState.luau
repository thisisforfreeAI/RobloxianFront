--!strict
-- Port UI state. Requests are injected; obsolete browse replies never overwrite newer filters.
local Browser={}
function Browser.new(deps:any):any
	local self:any={view={open=false,loading=false,joining=nil,rows={},filter={hasSpace=true},message=""}}
	local alive=true;local browseToken:any=nil;local joinToken:any=nil;local nextBrowse=-math.huge;local refreshAt=math.huge;local joinUntil=0;local rowsAt=0;local problem:string?=nil
	local function changed() if alive and deps.changed then deps.changed(self.view) end end
	local function failMessage(r:any):string return if type(r)=="table" and type(r.message)=="string" then r.message else "The match list is unavailable. Try refreshing." end
	function self.refresh():boolean
		if not alive or not self.view.open or self.view.joining or browseToken then return false end
		local now=deps.now();if now<nextBrowse then refreshAt=nextBrowse;return false end
		local token={};browseToken=token;nextBrowse=now+(deps.cooldown or 2);self.view.loading=true;changed()
		local function done(r:any)
			if not alive or browseToken~=token then return end
			browseToken=nil;self.view.loading=false;local now=deps.now()
			if type(r)=="table" and r.ok==true and type(r.lobbies)=="table" then
				self.view.rows={};for i,row in r.lobbies do if i>100 then break end;if type(row)=="table" and type(row.lobbyId)=="string" then table.insert(self.view.rows,row) end end
				self.view.currentLobbyId=r.currentLobbyId;self.view.message=problem or (if #self.view.rows==0 then "No matching games right now. Try All matches or refresh." else "Choose a match to join.");rowsAt=now
			else self.view.message=failMessage(r) end
			refreshAt=now+math.clamp(if type(r)=="table" then tonumber(r.refreshAfter) or 10 else 10,2,60);changed()
		end
		local ok=pcall(deps.browse,table.clone(self.view.filter),done);if not ok then done(nil) end
		return true
	end
	function self.setOpen(open:boolean):boolean
		if not alive or (not open and self.view.joining) then return false end
		self.view.open=open
		if open then refreshAt=deps.now();self.refresh() else browseToken=nil;self.view.loading=false end
		changed();return true
	end
	function self.filter(filter:any)
		if not alive or self.view.joining then return end
		problem=nil;self.view.filter=table.clone(filter);self.view.rows={};self.view.message="Refreshing matches…"
		browseToken=nil;self.view.loading=false;refreshAt=math.max(deps.now(),nextBrowse);changed()
	end
	function self.join(id:string):boolean
		if not alive or not self.view.open or self.view.joining then return false end
		if id==self.view.currentLobbyId then self.view.message="You’re already in this match.";changed();return false end
		local selected=nil;for _,row in self.view.rows do if row.lobbyId==id then selected=row;break end end
		if not selected or not selected.joinable or (tonumber(selected.expiresIn) or 0)<=deps.now()-rowsAt then
			self.view.message="That seat is no longer available. Refreshing…";refreshAt=deps.now();changed();return false
		end
		local token={};problem=nil;joinToken=token;browseToken=nil;self.view.loading=false;self.view.joining=id;self.view.message="Joining match…";joinUntil=deps.now()+65;changed()
		local function done(r:any)
			if not alive or joinToken~=token then return end
			if type(r)=="table" and r.ok==true and r.route=="teleport" then self.view.message="Connecting to match…"
			else joinToken=nil;self.view.joining=nil;problem=if type(r)=="table" and r.ok then "You’re already in this match." else failMessage(r);self.view.message=problem;refreshAt=deps.now() end
			changed()
		end
		local ok=pcall(deps.join,id,done);if not ok then done(nil) end
		return true
	end
	function self.notice(r:any)
		if not alive or type(r)~="table" or r.reason~="teleportFailed" then return end
		joinToken=nil;self.view.joining=nil;problem=failMessage(r);self.view.message=problem;refreshAt=deps.now();changed()
	end
	function self.tick()
		if not alive then return end
		if self.view.joining and deps.now()>=joinUntil then self.notice({reason="teleportFailed",message="Joining took too long. Refresh and try again."}) end
		if self.view.open and not self.view.joining and deps.now()>=refreshAt then self.refresh() end
	end
	function self.destroy() alive=false;browseToken=nil;joinToken=nil;self.view.open=false end
	return self
end
return Browser
