--!strict
local passed,failed=0,0
local function test(name:string,fn:any)
 local ok,err=pcall(fn)
 if ok then passed+=1;print("  ok    "..name) else failed+=1;print("  FAIL  "..name..": "..tostring(err)) end
end
local function eq(a:any,b:any) assert(a==b,`expected {tostring(b)}, got {tostring(a)}`) end
require("./prematch_state")(test,eq)
require("./prematch_client")(test,eq)
require("./prematch_ui")(test,eq)
print(`{passed} passed, {failed} failed`)
if failed>0 then error("pre-match lobby tests failed") end
