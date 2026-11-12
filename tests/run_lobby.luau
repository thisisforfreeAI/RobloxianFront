--!strict
-- Runs only the lobby directory tests: lune run tests/run_lobby
local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ok    " .. name)
	else
		failed += 1
		print("  FAIL  " .. name .. ": " .. tostring(err))
	end
end
local function eq(a: any, b: any)
	assert(a == b, `expected {tostring(b)}, got {tostring(a)}`)
end
require("./lobby_directory")(test, eq)
require("./lobby_service")(test, eq)
print(`{passed} passed, {failed} failed`)
if failed > 0 then
	error("lobby tests failed")
end
