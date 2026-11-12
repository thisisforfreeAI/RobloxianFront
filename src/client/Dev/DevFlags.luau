--!strict
-- Development switches. The atlas test board only ever runs inside Studio.
return {
	ATLAS_TEST_BOARD = false, -- Opt in only for the sprite check (docs/STUDIO_TESTS.md, test 6).
	FORCE_PART_GROUND = false, -- true draws the ground with Parts (orientation reference, test 2)
	OWNERSHIP_PROBE = false, -- Opt in for test 7; K is a normal gameplay binding.
}
