--!strict
-- Runs only the street furniture tests: lune run tests/run_street_furniture
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
require("./street_furniture")(test, eq)
print(`{passed} passed, {failed} failed`)
if failed > 0 then
	error("street furniture tests failed")
end
